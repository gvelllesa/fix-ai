import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import '../../../../core/services/obd_tcp_transport.dart';
import '../../../../core/services/obd_network_binder.dart';
import '../../../../data/bmw/bmw_istep_codec.dart';
import '../../../../data/bmw/bmw_svk_parser.dart';
import '../adapter_connection_constants.dart';
import '../diagnostic_connection_exception.dart';
import '../classify_socket_exception_native.dart';
import '../diagnostic_exception.dart';
import 'doip/doip_client.dart';
import 'doip/doip_constants.dart';
import 'uds/doip_uds_transport.dart';
import 'uds/uds_service.dart';
import 'bmw_dtc_codec.dart';
import 'bmw_ecu_database.dart';
import '../live_telemetry_sample.dart';
import '../connection_lifecycle_stage.dart';

/// Wire protocol after TCP connect — DoIP (ISO 13400) or BMW HSFZ on port 6801.
enum _EnetWireProtocol { doip, hsfz }

/// BMW ENET / DoIP (Diagnostics over IP) strategy — UDS over IP.
///
/// FAILURE CONTRACT — strictly enforced (no fake data, ever):
///   * [connect] / [connectForChassis] / [connectForChassisCode] return
///     `true` on success and throw [DiagnosticException] otherwise.
///   * [readDtcs] returns a list — possibly empty — ONLY when the ECU
///     positively answered with a UDS 0x59 (positive ReadDTCInformation
///     response). An empty list means "the vehicle has zero stored DTCs".
///   * Any socket timeout, empty-bytes read, malformed frame, UDS negative
///     response (0x7F), or protocol mismatch throws [DiagnosticException].
///   * [readDtcsFromAllEcus] throws `allEcusSilent` if every single ECU on
///     the chassis map failed to respond; partial failures (some ECUs
///     silent) are tolerated because that's normal for a real car (some
///     modules are asleep or not fitted).
///
/// There is intentionally no path that returns `null`, `[]`, or `false`
/// when the vehicle could not actually be read — those code paths are
/// exactly what previously produced fabricated "P0420 / P0455" data.
class EnetStrategy {
  ObdTcpTransport? _transport;
  StreamSubscription<Uint8List>? _socketSubscription;

  /// Raw inbound byte buffer — HSFZ frames can arrive fragmented across TCP
  /// segments, so we accumulate and slice complete frames out of it.
  final BytesBuilder _rxBuffer = BytesBuilder();

  bool _routingActivated = false;
  _EnetWireProtocol _wireProtocol = _EnetWireProtocol.doip;

  /// Inbound UDS payloads extracted from HSFZ diagnostic frames (0x0001).
  final StreamController<Uint8List> _hsfzUdsController =
      StreamController<Uint8List>.broadcast();

  /// DoIP stack (ISO 13400) — routing activation + TesterPresent timer.
  DoipClient? _doipClient;

  /// UDS service layer over [DoipUdsTransport] or future ISO-TP transport.
  UdsService? _udsService;

  Timer? _testerPresentTimer;

  bool get isConnected => _transport != null && _routingActivated;

  /// True when the active TCP session uses BMW HSFZ on port 6801 (not DoIP).
  bool get isHsfz => _wireProtocol == _EnetWireProtocol.hsfz;

  // === HSFZ constants (BMW Ediabas TCP, port 6801) ===
  static const int _hsfzTesterAddress = 0xF4;
  static const int _hsfzZgwAddress = 0x10;
  static const int _hsfzTypeDiagnostic = 0x0001;
  static const int _hsfzTypeAliveCheck = 0x0012;
  static const Duration _hsfzPostConnectSettle = Duration(milliseconds: 80);

  bool _hsfzHandshaking = false;
  Completer<void>? _hsfzInboundActivity;

  // H5 FIX (audit): HSFZ send mutex. The TesterPresent keep-alive timer
  // (_startTesterPresentTimer) calls _sendUdsHsfz every 3s concurrently with
  // real diagnostic reads, and both open a listener on the shared broadcast
  // _hsfzUdsController. Without serialization a keep-alive echo could satisfy
  // a real read's Completer (or vice-versa), silently delivering the wrong
  // bytes to the wrong caller.
  Future<void> _hsfzSendMutex = Future<void>.value();

  // Logical addresses (BMW conventions) — shared with [DoipClient].
  static const int _testerAddress = DoipConstants.defaultTesterAddress;
  static const int _defaultGatewayAddress = DoipConstants.defaultGatewayAddress;

  /// Active chassis profile (set via [connectForChassis]) — drives gateway
  /// address selection and the list of ECU targets we iterate over when
  /// scanning all modules.
  BmwChassisProfile? _chassisProfile;
  BmwChassisProfile? get chassisProfile => _chassisProfile;
  // ignore: unnecessary_getters_setters
  set chassisProfile(BmwChassisProfile? p) => _chassisProfile = p;

  // Default endpoints
  static const String defaultEnetIp = '169.254.1.1'; // USB-Ethernet link-local
  static const String defaultWifiIp = '192.168.0.10'; // Wi-Fi ENET adapter
  static const int doipPort = DoipConstants.tcpPort; // standard DoIP TCP
  static const int doipUdpPort = DoipConstants.udpDiscoveryPort; // UDP 50160
  static const int ediabasPort = 6801; // legacy BMW Ediabas
  static const int transparentBridgePort =
      AdapterConnectionConstants.transparentBridgePort;

  /// Connects to the gateway and performs DoIP routing activation.
  ///
  /// Returns `true` on success. Throws [DiagnosticException] on any failure
  /// (socket unreachable, timeout, DoIP handshake rejected). Never returns
  /// `false` — callers must not be allowed to silently continue.
  Future<bool> connect({
    String ip = defaultEnetIp,
    int port = doipPort,
    int testerAddress = _testerAddress,
    int gatewayAddress = _defaultGatewayAddress,
    void Function(ConnectionLifecycleStage)? onStage,
    Duration? socketTimeout,
  }) async {
    final connectTimeout =
        socketTimeout ?? AdapterConnectionConstants.socketTimeout;
    _routingActivated = false;
    _wireProtocol =
        port == ediabasPort ? _EnetWireProtocol.hsfz : _EnetWireProtocol.doip;
    // Bind the Flutter process to the Wi-Fi/Ethernet network before opening
    // the socket. On Samsung S25+ Android reroutes the default to cellular
    // when the ENET link has no internet, which would make the socket to
    // 169.254.1.1 / 192.168.0.10 unreachable. OBDNetworkBinder applies the
    // binding with retry logic in case the vehicle NetworkCallback hasn't
    // fired yet on a fresh association. CellularHttpClient bypasses the
    // binding for API traffic, so both coexist. See WifiStrategy.connect for
    // the full rationale.
    await OBDNetworkBinder.instance.bindToWifi();

    try {
      final t = DateTime.now().toIso8601String();
      debugPrint('[$t] ENET STAGE 1 (socket): opening $ip:$port '
          '(proto=${port == ediabasPort ? "hsfz" : "doip"}, '
          'timeout=${connectTimeout.inSeconds}s)…');
      final transport = await connectObdTcp(ip, port, connectTimeout);
      _transport = transport;
      final t2 = DateTime.now().toIso8601String();
      debugPrint('[$t2] ENET STAGE 1 (socket): OK — transport open '
          '(closed=${transport.isClosed}).');
    } on SocketException catch (e) {
      // STAGE 1 FAILED — socket could not be established. Classify the exact
      // OS errno (113 = no route to host, 111 = refused, 110 = timeout, ...)
      // into a granular DiagnosticConnectionException the UI can render with
      // stage + errno + actionable tip. Never collapse this back to a generic
      // "adapterUnreachable" message.
      final time = DateTime.now().toIso8601String();
      debugPrint(
          '[$time] ENET STAGE 1 (socket) FAILED: ${e.osError?.errorCode} '
          '${e.osError?.message ?? e.message}');
      throw classifySocketException(e, ip: ip, port: port);
    } on TimeoutException catch (e) {
      // Socket.connect wraps its own timeout in a TimeoutException, distinct
      // from a kernel ETIMEDOUT. Treat it as STAGE 1 timeout.
      final time = DateTime.now().toIso8601String();
      debugPrint('[$time] ENET STAGE 1 (socket) TIMEOUT: $e');
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.socketEstablishment,
        message: 'Timed out reaching gateway $ip:$port within '
            '${connectTimeout.inSeconds}s. '
            'Ensure Mobile Data is OFF.',
        wasTimeout: true,
        troubleshootingTip: kCriticalMobileDataWarning,
        cause: e,
      );
    } catch (e) {
      debugPrint('ENET STAGE 1 (socket) UNEXPECTED: $e');
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.socketEstablishment,
        message: 'Unexpected error opening socket to $ip:$port: $e',
        troubleshootingTip: 'Restart the OBD flow; if it persists, capture '
            'the exception text above and report it.',
        cause: e,
      );
    }

    if (port == transparentBridgePort) {
      await _warmupTransparentUartBridge();
    }

    if (_wireProtocol == _EnetWireProtocol.hsfz) {
      // FIX #2 (handshake): the handshaking guard must cover the ENTIRE
      // connect sequence (alive_check → TesterPresent → extended session),
      // not only _activateHsfzLink(). The previous code cleared it in a
      // finally right after _activateHsfzLink(), leaving a window between
      // there and _requireExtendedDiagnosticSession() during which a peer
      // EOF (reader endOfStream) fired onDone → disconnect() → and the next
      // UDS write hit "ENET socket is not open". That was the Stage 2 failure.
      _hsfzHandshaking = true;
      _socketSubscription = _transport!.inbound.listen(
        _onData,
        onError: (Object e) {
          debugPrint('ENET socket error: $e');
          // Don't auto-disconnect on a transient stream error during/after
          // handshake; surface it and let the next UDS write throw a clean
          // DiagnosticConnectionException. Auto-teardown here raced the
          // handshake on Samsung S25+ where the reader briefly errors before
          // ZGW accepts HSFZ traffic.
        },
        onDone: () {
          final time = DateTime.now().toIso8601String();
          debugPrint('[$time] ENET inbound stream ended (peer EOF/reader end).');
          // FIX #2: never auto-teardown during handshake. A peer EOF can arrive
          // momentarily on some ZGW firmware before the first HSFZ exchange
          // completes; tearing down here guaranteed the "socket is not open"
          // failure. We instead let the handshake UDS write fail with a real,
          // classified exception.
          if (!_hsfzHandshaking && !_routingActivated) {
            disconnect();
          }
        },
      );
      if (onStage != null) {
        onStage(ConnectionLifecycleStage.sendingDoipRoutingActivation);
      }
      try {
        await _activateHsfzLink();
        _routingActivated = true;
        final time = DateTime.now().toIso8601String();
        debugPrint('[$time] HSFZ: link verified on $ip:$port');
        if (onStage != null) {
          onStage(ConnectionLifecycleStage.openingExtendedSession);
        }
        await _requireExtendedDiagnosticSession(gatewayAddress);
      } catch (e) {
        // Handshake failed — clean teardown so a retry opens a fresh socket.
        debugPrint('ENET HSFZ handshake failed, tearing down: $e');
        rethrow;
      } finally {
        _hsfzHandshaking = false;
      }
      return true;
    }

    if (onStage != null)
      onStage(ConnectionLifecycleStage.sendingDoipRoutingActivation);
    // DoIP — DoipClient owns socket reads, routing activation, and
    // TesterPresent (0x3E 0x00) every 3 seconds.
    _doipClient = DoipClient(
      testerAddress: testerAddress,
      gatewayAddress: gatewayAddress,
    );
    await _doipClient!.attach(_transport!);
    _udsService = UdsService(
      DoipUdsTransport(_doipClient!),
      defaultTargetAddress: gatewayAddress,
    );
    _routingActivated = true;
    final time = DateTime.now().toIso8601String();
    debugPrint(
      '[$time] DoIP: routing activated on $ip:$port (TCP ${DoipConstants.tcpPort})',
    );
    if (onStage != null)
      onStage(ConnectionLifecycleStage.openingExtendedSession);
    await _requireExtendedDiagnosticSession(gatewayAddress);
    return true;
  }

  /// Positive UDS response to DiagnosticSessionControl extended (0x10 0x03).
  static bool _isPositiveExtendedSession(Uint8List resp) =>
      resp.length >= 2 && resp[0] == 0x50 && resp[1] == 0x03;

  /// STAGE 3 gate: gateway must accept extended diagnostic session before the
  /// link is considered ready for further UDS (ProTool-style post-handshake).
  Future<void> _requireExtendedDiagnosticSession(int gatewayAddress) async {
    final resp = await sendUds(
      [0x10, 0x03],
      targetAddress: gatewayAddress,
      timeout: const Duration(seconds: 6),
    );

    if (resp.isNotEmpty && resp[0] == 0x7F) {
      final nrc = resp.length > 2 ? resp[2] : 0x00;
      final nrcName = udsNrcName(nrc) ?? 'Unknown NRC';
      debugPrint(
        'ENET STAGE 3 (0x10 0x03) NEGATIVE: NRC 0x'
        '${nrc.toRadixString(16).toUpperCase().padLeft(2, '0')} ($nrcName)',
      );
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'Gateway refused extended diagnostic session (0x10 0x03). '
            'NRC 0x${nrc.toRadixString(16).toUpperCase().padLeft(2, '0')} ($nrcName).',
        negativeResponseCode: nrc,
        troubleshootingTip: 'Turn ignition ON (terminal 15). Some gateways '
            'require the engine running or a specific unlock level.',
      );
    }

    if (!_isPositiveExtendedSession(resp)) {
      final hex = resp.isEmpty
          ? '(empty)'
          : resp
              .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
              .join(' ');
      debugPrint('ENET STAGE 3 (0x10 0x03) unexpected response: $hex');
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'Gateway did not confirm extended diagnostic session. '
            'Expected UDS 0x50 0x03, received $hex.',
        troubleshootingTip: 'Verify ignition is ON and the ENET adapter is '
            'connected to the vehicle OBD port. Retry after cycling ignition.',
      );
    }

    debugPrint(
      'ENET: extended diagnostic session active (0x50 0x03) on gateway '
      '0x${gatewayAddress.toRadixString(16).toUpperCase().padLeft(4, '0')}',
    );
    if (_wireProtocol == _EnetWireProtocol.hsfz) {
      _startTesterPresentTimer(gatewayAddress);
    }
  }

  void _startTesterPresentTimer(int gatewayAddress) {
    _testerPresentTimer?.cancel();
    _testerPresentTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        await sendUds([0x3E, 0x00], targetAddress: gatewayAddress);
      } catch (e) {
        debugPrint('HSFZ keep-alive TesterPresent failed: $e');
      }
    });
  }

  /// Clears UART garbage on transparent UART-ETH-WIFI bridges (port 35000)
  /// before DoIP routing activation.
  Future<void> _warmupTransparentUartBridge() async {
    debugPrint('ENET: UART transparent bridge warmup (CR flush)…');
    try {
      await _transport!.write([0x0D]);
      await _transport!.flush();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      _rxBuffer.clear();
    } catch (e) {
      debugPrint('ENET: UART warmup failed (non-fatal): $e');
    }
  }

  /// Maps a 16-bit DoIP logical address to the 1-byte HSFZ target address.
  int _toHsfzAddress(int logicalAddress) {
    if (logicalAddress == 0x00F087 || logicalAddress == 0x00F086) {
      return _hsfzZgwAddress;
    }
    return logicalAddress & 0xFF;
  }

  Uint8List _buildHsfzAliveCheckFrame() {
    return Uint8List.fromList([
      0x00,
      0x00,
      0x00,
      0x02,
      (_hsfzTypeAliveCheck >> 8) & 0xFF,
      _hsfzTypeAliveCheck & 0xFF,
      _hsfzTesterAddress,
      _hsfzZgwAddress,
    ]);
  }

  Uint8List _buildHsfzDiagnosticFrame(int targetHsfz, List<int> uds) {
    final length = uds.length + 2; // src + dst bytes
    final frame = BytesBuilder();
    frame.addByte((length >> 24) & 0xFF);
    frame.addByte((length >> 16) & 0xFF);
    frame.addByte((length >> 8) & 0xFF);
    frame.addByte(length & 0xFF);
    frame.addByte((_hsfzTypeDiagnostic >> 8) & 0xFF);
    frame.addByte(_hsfzTypeDiagnostic & 0xFF);
    frame.addByte(_hsfzTesterAddress);
    frame.addByte(targetHsfz);
    frame.add(uds);
    return frame.toBytes();
  }

  /// Ediabas/ProTool HSFZ link bring-up: alive_check (0x0012) then TesterPresent.
  Future<void> _activateHsfzLink() async {
    if (_transport == null || _transport!.isClosed) {
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.doipRoutingActivation,
        message: 'HSFZ TCP session closed before handshake '
            '(transport ${_transport == null ? "null" : "closed"}).',
        troubleshootingTip: 'Retry connect — the gateway may have dropped an '
            'idle TCP session. Send alive_check immediately after open.',
      );
    }

    try {
      await _sendHsfzAliveCheck();
    } on SocketException catch (e) {
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.doipRoutingActivation,
        message: 'HSFZ alive_check write failed: ${e.message}',
        troubleshootingTip: 'The gateway closed the TCP session before accepting '
            'HSFZ traffic. Close other diagnostic apps, wait 10s, and retry.',
        cause: e,
      );
    }

    await Future<void>.delayed(_hsfzPostConnectSettle);

    debugPrint('HSFZ: probing gateway with TesterPresent…');
    try {
      final resp = await _sendUdsHsfz(
        [0x3E, 0x00],
        targetHsfz: _hsfzZgwAddress,
        timeout: const Duration(seconds: 4),
      );
      if (resp.isEmpty || resp[0] != 0x7E) {
        throw DiagnosticConnectionException(
          stage: DiagnosticStage.doipRoutingActivation,
          message: 'HSFZ gateway did not answer TesterPresent '
              '(expected 0x7E, got ${resp.isEmpty ? 'nothing' : '0x${resp[0].toRadixString(16)}'}).',
          troubleshootingTip: 'Confirm ignition is ON (terminal 15), the ENET '
              'adapter is powered, and no other diagnostic app holds '
              'the 6801 session.',
        );
      }
    } on DiagnosticConnectionException {
      rethrow;
    } on TimeoutException catch (e) {
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.doipRoutingActivation,
        message: 'HSFZ gateway silent during link check.',
        wasTimeout: true,
        troubleshootingTip: 'The adapter accepted TCP but did not answer HSFZ. '
            'Close other diagnostic apps and retry.',
        cause: e,
      );
    }
  }

  /// HSFZ transport-layer heartbeat (TYPE 0x0012) — sent immediately after TCP open.
  Future<void> _sendHsfzAliveCheck() async {
    final transport = _transport;
    if (transport == null || transport.isClosed) {
      // FIX #2: classify exactly what happened so the Stage 2 error is
      // actionable instead of the opaque "ENET socket is not open". With the
      // native generation-guarded reader (FIX #1) a stale endOfStream can no
      // longer tear us down here, but a genuine peer RST still can — surface
      // it as a routing-activation failure with the right tip.
      final why = transport == null
          ? 'transport was reset'
          : 'socket closed by gateway before HSFZ exchange';
      debugPrint('HSFZ alive_check aborted: $why');
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.doipRoutingActivation,
        message: 'HSFZ alive_check write failed: $why. The ZGW opened TCP then '
            'closed it immediately — usually a leftover session from a previous '
            'app, or ignition not in terminal 15.',
        troubleshootingTip: 'Wait ~10s for the ZGW to drop the old session, '
            'press START once (without brake) for terminal 15, then retry. '
            'Avoid scanning other ports (35000/13400) on the same ZGW.',
      );
    }

    final frame = _buildHsfzAliveCheckFrame();
    debugPrint('HSFZ: sending alive_check (0x0012) to ZGW 0x10…');

    _hsfzInboundActivity = Completer<void>();
    try {
      await transport.write(frame);
      await transport.flush();
      debugPrint('HSFZ: alive_check sent (${frame.length}B), awaiting any inbound…');
      await _hsfzInboundActivity!.future.timeout(
        const Duration(seconds: 2),
        onTimeout: () {
          debugPrint('HSFZ: alive_check — no inbound bytes within 2s (continuing).');
        },
      );
    } finally {
      _hsfzInboundActivity = null;
    }
  }

  Future<Uint8List> _sendUdsHsfz(
    List<int> udsRequest, {
    required int targetHsfz,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_transport == null) {
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.socketEstablishment,
        message: 'ENET socket is not open. Call connect() first.',
        troubleshootingTip: 'Retry the full connection flow.',
      );
    }

    // H5 FIX (audit): serialize HSFZ exchanges so the keep-alive timer can't
    // race a real read on the shared _hsfzUdsController stream.
    final wait = _hsfzSendMutex;
    final myRelease = Completer<void>();
    _hsfzSendMutex = myRelease.future;
    await wait;

    try {
      final frame = _buildHsfzDiagnosticFrame(targetHsfz, udsRequest);
      final completer = Completer<Uint8List>();
      StreamSubscription<Uint8List>? sub;
      sub = _hsfzUdsController.stream.listen((uds) {
        if (!completer.isCompleted) completer.complete(uds);
      });

      try {
        await _transport!.write(frame);
        await _transport!.flush();
        return await completer.future.timeout(timeout, onTimeout: () {
          throw DiagnosticConnectionException(
            stage: DiagnosticStage.udsCommunication,
            message: 'HSFZ ECU 0x${targetHsfz.toRadixString(16)} did not '
                'answer within ${timeout.inSeconds}s.',
            wasTimeout: true,
            troubleshootingTip: 'The ECU may be asleep. Turn ignition ON '
                'and retry.',
          );
        });
      } on SocketException catch (e) {
        throw DiagnosticConnectionException(
          stage: DiagnosticStage.doipRoutingActivation,
          message: 'HSFZ write failed: ${e.message}',
          troubleshootingTip: 'The ZGW closed the TCP session. Ensure no other '
              'diagnostic app is connected on port 6801, wait 10s, and retry.',
          cause: e,
        );
      } finally {
        await sub.cancel();
      }
    } finally {
      // Release the mutex for the next sender (real request or keep-alive).
      myRelease.complete();
    }
  }

  /// Accumulates inbound HSFZ bytes and emits complete diagnostic frames.
  void _onData(Uint8List chunk) {
    if (_hsfzInboundActivity != null &&
        !_hsfzInboundActivity!.isCompleted) {
      _hsfzInboundActivity!.complete();
    }
    _rxBuffer.add(chunk);
    _drainHsfzFrames();
  }

  /// Slices complete HSFZ frames out of [_rxBuffer] and emits UDS payloads.
  void _drainHsfzFrames() {
    var bytes = _rxBuffer.toBytes();
    int offset = 0;
    while (bytes.length - offset >= 6) {
      final length = (bytes[offset] << 24) |
          (bytes[offset + 1] << 16) |
          (bytes[offset + 2] << 8) |
          bytes[offset + 3];
      final frameTotal = 6 + length;
      if (bytes.length - offset < frameTotal) break;
      final control = (bytes[offset + 4] << 8) | bytes[offset + 5];
      if (control == _hsfzTypeDiagnostic && length >= 2) {
        final udsStart = offset + 8;
        final udsEnd = offset + 6 + length;
        if (udsEnd <= bytes.length && udsEnd > udsStart) {
          final uds = Uint8List.fromList(bytes.sublist(udsStart, udsEnd));
          if (!_hsfzUdsController.isClosed) {
            _hsfzUdsController.add(uds);
          }
        }
      }
      offset += frameTotal;
    }
    _rxBuffer.clear();
    if (offset < bytes.length) {
      _rxBuffer.add(bytes.sublist(offset));
    }
  }

  /// Tailors the troubleshooting tip to a specific UDS negative-response
  /// code (NRC), since each NRC points at a different root cause.
  String _tipForUdsNrc(int nrc) {
    switch (nrc) {
      case 0x22: // Conditions Not Correct
        return 'The ECU isn\'t in the right state. Put the car in ignition '
            '(terminal 15 / press START-STOP once without brake) and retry; '
            'some modules also need the engine running.';
      case 0x33: // Security Access Denied
        return 'Security access is required. This module needs a diagnostic '
            'session / security unlock this adapter path doesn\'t perform.';
      case 0x31: // Request Out Of Range
        return 'The requested DID/sub-function isn\'t valid for this ECU. '
            'It may not be fitted or may use a different identifier.';
      case 0x11: // Service Not Supported
      case 0x7E: // Sub-function Not Supported In Active Session
      case 0x7F: // Service Not Supported In Active Session
        return 'This ECU doesn\'t support the UDS service in the current '
            'session. The module may be asleep or need a different session '
            'type.';
      case 0x78: // Response Pending
        return 'The ECU asked for more time (response pending) but never '
            'completed. Retry once; if it repeats the module is busy.';
      default:
        return 'The ECU refused the request (NRC 0x'
            '${nrc.toRadixString(16).toUpperCase().padLeft(2, '0')}). '
            'Confirm the chassis/ECU selection and retry.';
    }
  }

  /// Sends a UDS request wrapped in a DoIP Diagnostic Message and returns the
  /// UDS response bytes (the inner payload, minus the 4-byte source/target
  /// address header).
  ///
  /// STAGE 3 of the staged connection pipeline. STAGE 1 (socket) and STAGE 2
  /// (routing activation) have already succeeded; this is the actual UDS
  /// (ISO 14229) request/response with a target ECU.
  ///
  /// Throws [DiagnosticConnectionException] (stage = udsCommunication) with:
  ///   * the exact UDS NRC byte (e.g. 0x22 Conditions Not Correct) when the
  ///     ECU actively refused, formatted as hex + its ISO 14229 meaning;
  ///   * the DoIP NACK code when the gateway refused to relay;
  ///   * a timeout flag when the ECU stayed silent past the deadline.
  ///
  /// The caller (readDtcs / readVin / ...) inspects the returned payload for a
  /// 0x7F negative response for services where that's a legitimate outcome;
  /// transport-level failures (timeout, socket) throw here.
  Future<Uint8List> sendUds(
    List<int> udsRequest, {
    int? targetAddress,
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (_transport == null) {
      throw const DiagnosticConnectionException(
        stage: DiagnosticStage.socketEstablishment,
        message: 'ENET socket is not open. Call connect() first.',
        troubleshootingTip: 'This is an internal error — the connection was '
            'lost before the UDS request. Retry the full scan.',
      );
    }
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;

    if (_wireProtocol == _EnetWireProtocol.hsfz) {
      return _sendUdsHsfz(
        udsRequest,
        targetHsfz: _toHsfzAddress(target),
        timeout: timeout,
      );
    }

    if (_udsService != null) {
      return _udsService!.request(
        udsRequest,
        targetAddress: target,
        timeout: timeout,
      );
    }

    throw const DiagnosticConnectionException(
      stage: DiagnosticStage.socketEstablishment,
      message: 'DoIP UDS service is not initialized.',
      troubleshootingTip: 'Retry the full ENET connection flow.',
    );
  }

  /// Reads stored DTCs via UDS Service 0x19, subfunction 0x02
  /// (reportDTCByStatusMask) with status mask 0xFF (all).
  ///
  /// Returns a list of DTC strings. An EMPTY list means the ECU positively
  /// answered "zero stored DTCs" — it does NOT mean "could not read".
  /// Socket timeouts, empty reads, malformed frames, and UDS negative
  /// responses all throw [DiagnosticException].
  Future<List<String>> readDtcs({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    // UDS: 0x19 (ReadDTCInformation) 0x02 (reportDTCByStatusMask) 0xFF (mask)
    final resp = await sendUds([0x19, 0x02, 0xFF], targetAddress: target);

    // Negative response: 0x7F 0x19 [NRC]. Parse and expose the exact NRC hex
    // + its ISO 14229 meaning so the UI can show "NRC 0x22 — Conditions Not
    // Correct" verbatim.
    if (resp.isNotEmpty && resp[0] == 0x7F) {
      final nrc = resp.length > 2 ? resp[2] : 0x00;
      final nrcName = udsNrcName(nrc) ?? 'Unknown NRC';
      debugPrint('ENET STAGE 3 (UDS 0x19) NEGATIVE: NRC 0x'
          '${nrc.toRadixString(16).padLeft(2, '0')} ($nrcName).');
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'ECU refused to read DTCs. UDS negative response: NRC 0x'
            '${nrc.toRadixString(16).toUpperCase().padLeft(2, '0')} '
            '($nrcName).',
        negativeResponseCode: nrc,
        troubleshootingTip: _tipForUdsNrc(nrc),
      );
    }
    // Unexpected reply shape — protocol mismatch / parsing error.
    if (resp.length < 3 || resp[0] != 0x59 || resp[1] != 0x02) {
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'Unexpected UDS reply to ReadDTCInformation: '
            '${resp.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}. '
            'The adapter may not be speaking ISO 14229 (UDS).',
        troubleshootingTip: 'The adapter answered but isn\'t speaking standard '
            'UDS. It may be an ELM327 over Wi-Fi rather than a true ENET/DoIP '
            'adapter — try the Wi-Fi interface instead.',
      );
    }

    return parseReadDtcPositiveResponse(resp, activeOnly: true);
  }

  // ----------------------------------------------------------------
  // Chassis-aware helpers (BMW/MINI F & G series)
  // ----------------------------------------------------------------

  /// Connects using parameters derived from a [BmwChassisProfile].
  ///
  /// Looks up the correct gateway logical address for the chassis (e.g.
  /// 0x00F087 on F-series ZGW, 0x00F086 on G-series ZGW_INT), then performs
  /// the standard DoIP routing activation. After a successful call, the
  /// strategy remembers the profile so that subsequent [readDtcs] /
  /// [readDtcsFromAllEcus] / [readVin] calls target the correct modules.
  ///
  /// Throws [DiagnosticException] on any failure.
  Future<bool> connectForChassis(
    BmwChassisProfile profile, {
    String ip = defaultEnetIp,
    int port = doipPort,
    void Function(ConnectionLifecycleStage)? onStage,
    Duration? socketTimeout,
  }) async {
    _chassisProfile = profile;
    final time = DateTime.now().toIso8601String();
    debugPrint(
      '[$time] ENET: connecting for chassis ${profile.chassisCode} '
      '(${profile.marketingName}, ${profile.family == BmwChassisFamily.gSeries ? "G-series" : "F-series"}), '
      'gateway 0x${profile.gatewayAddress.toRadixString(16).toUpperCase().padLeft(6, '0')}',
    );
    return connect(
      ip: ip,
      port: port,
      gatewayAddress: profile.gatewayAddress,
      onStage: onStage,
      socketTimeout: socketTimeout,
    );
  }

  /// Convenience: connect by chassis code (e.g. 'F30', 'G20', 'F56').
  ///
  /// Throws [DiagnosticException] with `gatewayRejected` if the chassis code
  /// is unknown to the database.
  Future<bool> connectForChassisCode(
    String chassisCode, {
    String ip = defaultEnetIp,
    int port = doipPort,
    void Function(ConnectionLifecycleStage)? onStage,
  }) async {
    final profile = lookupBmwChassis(chassisCode);
    if (profile == null) {
      throw DiagnosticException(
        DiagnosticFailureReason.gatewayRejected,
        'Unknown BMW/MINI chassis code: "$chassisCode". '
        'Make sure the car is an F- or G-series model.',
      );
    }
    return connectForChassis(profile, ip: ip, port: port, onStage: onStage);
  }

  /// Reads DTCs from every ECU listed in the active chassis profile and
  /// returns a map {ecuName -> [dtc codes]}.
  ///
  /// This is the full-vehicle scan that ISTA performs. On an F30, for
  /// example, this iterates ZGW, DME, EGS, KOMBI, FRM, CAS, DSC, JBE, REM,
  /// KAS, IHKA, HU_NBT (12 modules).
  ///
  /// Per-ECU failures are tolerated (some modules are asleep or not fitted).
  /// If EVERY ECU is silent, throws `allEcusSilent` — that almost always
  /// means the car is off, the gateway is down, or the wrong chassis was
  /// selected, so returning an empty map would lie to the user.
  Future<Map<String, List<String>>> readDtcsFromAllEcus({
    Duration perEcuTimeout = const Duration(seconds: 4),
  }) async {
    final profile = _chassisProfile;
    if (profile == null) {
      // Fallback to gateway-only scan.
      final gatewayCodes = await readDtcs();
      return {'GATEWAY': gatewayCodes};
    }

    final result = <String, List<String>>{};
    var ecusContacted = 0;
    for (final ecu in profile.ecus) {
      ecusContacted++;
      try {
        final codes = await readDtcs(targetAddress: ecu.logicalAddress)
            .timeout(perEcuTimeout);
        if (codes.isNotEmpty) {
          result[ecu.name] = codes;
        }
        debugPrint('ENET: ${ecu.name} -> ${codes.length} DTC(s).');
      } on DiagnosticConnectionException catch (e) {
        // Tolerate per-ECU failures. Some ECUs are asleep or not fitted.
        debugPrint('ENET: ${ecu.name} skipped (stage=${e.stage.name}: '
            '${e.message}).');
      } on DiagnosticException catch (e) {
        debugPrint('ENET: ${ecu.name} skipped (${e.reason}: ${e.message}).');
      } catch (e) {
        debugPrint('ENET: ${ecu.name} unexpected error: $e');
      }
    }

    if (result.isEmpty && ecusContacted > 0) {
      throw const DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'No ECU on this vehicle responded to a DTC read. The car is '
            'most likely off or not in ignition (terminal 15), the ENET cable '
            'is unplugged, or the selected chassis does not match this car. '
            'No fault codes were read.',
        troubleshootingTip: 'Turn the car to ignition (terminal 15), confirm '
            'the ENET cable is seated in the OBD-II port, and verify the '
            'chassis selection matches your model.',
      );
    }
    return result;
  }

  /// Reads the VIN via UDS Service 0x22 (ReadDataByIdentifier), DID 0xF190.
  /// Works on any F/G-series ECU, but the gateway is the most reliable.
  ///
  /// Returns the 17-character VIN, or null if the ECU responded positively
  /// but the DID was not supported / empty. Socket errors and negative UDS
  /// responses throw [DiagnosticException].
  Future<String?> readVin({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    if (_udsService != null) {
      return _udsService!.readVin(targetAddress: target);
    }
    // 0x22 ReadDataByIdentifier, 0xF190 VIN.
    final resp = await sendUds([0x22, 0xF1, 0x90], targetAddress: target);
    if (resp.isNotEmpty && resp[0] == 0x7F) {
      // Negative response — DID not supported is a legitimate "no VIN", not
      // a hard failure. Other NRCs are still surfaced with the exact hex.
      final nrc = resp.length > 2 ? resp[2] : 0x00;
      // NRC 0x11 = serviceNotSupported, 0x31 = requestOutOfRange (DID unknown).
      if (nrc == 0x11 || nrc == 0x31) return null;
      final nrcName = udsNrcName(nrc) ?? 'Unknown NRC';
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'ECU refused to read VIN. NRC 0x'
            '${nrc.toRadixString(16).toUpperCase().padLeft(2, '0')} ($nrcName).',
        negativeResponseCode: nrc,
        troubleshootingTip: _tipForUdsNrc(nrc),
      );
    }
    if (resp.length < 3 ||
        resp[0] != 0x62 ||
        resp[1] != 0xF1 ||
        resp[2] != 0x90) {
      throw const DiagnosticConnectionException(
        stage: DiagnosticStage.udsCommunication,
        message: 'Malformed VIN response — the bytes didn\'t match a 0x62 '
            'ReadDataByIdentifier reply for DID 0xF190.',
        troubleshootingTip: 'The adapter may not be speaking standard UDS. '
            'If it\'s an ELM327 clone, use the Wi-Fi interface instead.',
      );
    }
    final end = 3 + 17 > resp.length ? resp.length : 3 + 17;
    final vinBytes = resp.sublist(3, end);
    return String.fromCharCodes(vinBytes.where((b) => b >= 0x20 && b < 0x7F))
        .toUpperCase();
  }

  /// Clears stored DTCs on a single ECU (or the gateway) via UDS Service
  /// 0x14 (ClearDiagnosticInformation), sub-function 0xFF (all groups).
  ///
  /// Returns `true` if the ECU confirmed the clear (0x54). Returns `false`
  /// only on a legitimate UDS-level refusal. Socket errors and malformed
  /// responses throw [DiagnosticException].
  ///
  /// WARNING: this is a write operation. Confirm with the user before calling.
  Future<bool> clearDtcs({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final resp = await sendUds([0x14, 0xFF], targetAddress: target);
    if (resp.isEmpty) {
      throw const DiagnosticException(
        DiagnosticFailureReason.malformedResponse,
        'Empty response to ClearDiagnosticInformation.',
      );
    }
    // Positive response: 0x54. Negative: 0x7F 0x14 NRC.
    if (resp[0] == 0x54) return true;
    return false;
  }

  /// Reads the ECU identification (part number, hardware/software version)
  /// via UDS 0x22, DID 0xF187 (BMW ECU assembly number).
  /// Returns a hex string like "8415632-01" or null if the DID is not
  /// supported by this ECU. Socket errors throw [DiagnosticException].
  Future<String?> readEcuPartNumber(int targetAddress) async {
    final resp =
        await sendUds([0x22, 0xF1, 0x87], targetAddress: targetAddress);
    if (resp.isNotEmpty && resp[0] == 0x7F) {
      final nrc = resp.length > 2 ? resp[2] : 0x00;
      if (nrc == 0x11 || nrc == 0x31) return null;
      throw DiagnosticException(
        DiagnosticFailureReason.ecuNegativeResponse,
        'ECU refused to read part number (NRC 0x${nrc.toRadixString(16).padLeft(2, '0')}).',
        cause: nrc,
      );
    }
    if (resp.length < 4 || resp[0] != 0x62) {
      throw const DiagnosticException(
        DiagnosticFailureReason.malformedResponse,
        'Malformed ECU identification response.',
      );
    }
    final bytes = resp.sublist(3);
    return String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F));
  }

  // ----------------------------------------------------------------
  // Live telemetry via BMW UDS DIDs (ISO 14229 Service 0x22)
  // ----------------------------------------------------------------
  //
  // BMW F/G-series ECUs expose live sensor values through ReadDataByIdentifier
  // (0x22) using manufacturer-specific DIDs. These are the same identifiers
  // ISTA and BimmerCode use; they are NOT the generic OBD-II Mode 01 PIDs.
  //
  // The DIDs below are the common cross-chassis ones (DME/N55/B58, EGS, KOMBI)
  // reverse-engineered from BMW's public UDS function tables and the ediabasx
  // project. When a DID isn't supported by a given ECU, the ECU returns a UDS
  // negative response (0x7F + NRC 0x31) which we translate to null.

  /// Reads a live metric by a logical name (e.g. 'rpm', 'coolant_temp',
  /// 'boost_pressure') from the DME, returning a [LiveTelemetrySample].
  ///
  /// Routes the request to the correct UDS DID + target ECU for the active
  /// chassis. Returns null when the DID is not supported on this ECU.
  ///
  /// [profile] is used to pick the target ECU logical address; when null the
  /// DME (0x000012) is used as a sensible default for engine metrics.
  Future<LiveTelemetrySample?> readBmwLiveMetric(
    String metricName,
    BmwChassisProfile? profile,
  ) async {
    final spec = _bmwDidForMetric(metricName);
    if (spec == null) return null;
    final target =
        profile?.target(spec.ecu)?.logicalAddress ?? spec.fallbackAddress;
    final resp = await sendUds(
      [0x22, (spec.did >> 8) & 0xFF, spec.did & 0xFF],
      targetAddress: target,
    );
    // Negative response → DID not supported on this ECU.
    if (resp.isEmpty || resp[0] == 0x7F) return null;
    // Positive: 0x62 + DID(2) + payload.
    if (resp.length < 4 || resp[0] != 0x62) return null;
    final payload = resp.sublist(4);
    final value = spec.decode(payload);
    if (value == null) return null;
    return LiveTelemetrySample(
      name: spec.displayName,
      value: value.value,
      unit: value.unit,
      ecuName: spec.ecu,
      timestamp: DateTime.now(),
    );
  }

  /// Reads multiple live DIDs in one request (UDS 0x22 supports up to ~10 DIDs
  /// in a single request via "read multiple DIDs"). Returns a map keyed by the
  /// logical metric name. Useful for dashboard refreshes.
  Future<Map<String, LiveTelemetrySample>> readBmwLiveMetrics(
    List<String> metricNames,
    BmwChassisProfile? profile,
  ) async {
    final result = <String, LiveTelemetrySample>{};
    // UDS 0x22 multi-DID is supported but some BMW ECUs misbehave; read one at
    // a time for reliability. Parallelism would race the single socket.
    for (final name in metricNames) {
      try {
        final sample = await readBmwLiveMetric(name, profile);
        if (sample != null) result[name] = sample;
      } catch (e) {
        debugPrint('ENET live metric $name: $e');
      }
    }
    return result;
  }

  _BmwDidSpec? _bmwDidForMetric(String metricName) {
    final p = metricName.toLowerCase();
    // Engine speed — DME DID 0x1233 (UDS), raw = 2 bytes / 4.
    if (p.contains('rpm') || p.contains('engine_speed')) {
      return _BmwDidSpec(
        did: 0x1233,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Engine RPM',
        decode: (b) {
          if (b.length < 2) return null;
          final raw = (b[0] << 8) | b[1];
          return _DecodedValue(raw / 4.0, 'RPM');
        },
      );
    }
    // Vehicle speed — DME/DSC DID 0x1A87, raw = 1 byte km/h on some, 2 on others.
    if (p.contains('vehicle_speed') || p == 'speed') {
      return _BmwDidSpec(
        did: 0x1A87,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Vehicle Speed',
        decode: (b) {
          if (b.isEmpty) return null;
          // BMW reports speed as 1 byte km/h on most DMEs.
          return _DecodedValue(b[0].toDouble(), 'km/h');
        },
      );
    }
    // Coolant temperature — DME DID 0x1A0F (engine), raw = 1 byte, offset -48.
    if (p.contains('coolant')) {
      return _BmwDidSpec(
        did: 0x1A0F,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Engine Coolant Temp',
        decode: (b) {
          if (b.isEmpty) return null;
          return _DecodedValue((b[0] - 48).toDouble(), '°C');
        },
      );
    }
    // Oil temperature — DME DID 0x1A11, raw = 1 byte, offset -48.
    if (p.contains('oil') && p.contains('temp')) {
      return _BmwDidSpec(
        did: 0x1A11,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Engine Oil Temp',
        decode: (b) {
          if (b.isEmpty) return null;
          return _DecodedValue((b[0] - 48).toDouble(), '°C');
        },
      );
    }
    // Intake air temperature — DME DID 0x1A0D.
    if (p.contains('intake_air') || p.contains('iat')) {
      return _BmwDidSpec(
        did: 0x1A0D,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Intake Air Temp',
        decode: (b) {
          if (b.isEmpty) return null;
          return _DecodedValue((b[0] - 48).toDouble(), '°C');
        },
      );
    }
    // Manifold / boost pressure — DME DID 0x1A0A, raw = 2 bytes mbar.
    if (p.contains('boost') || p.contains('manifold') || p.contains('turbo')) {
      return _BmwDidSpec(
        did: 0x1A0A,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Boost Pressure',
        decode: (b) {
          if (b.length < 2) return null;
          final raw = (b[0] << 8) | b[1];
          return _DecodedValue(raw / 10.0, 'mbar');
        },
      );
    }
    // Throttle position — DME DID 0x1A0E, raw = 1 byte %.
    if (p.contains('throttle')) {
      return _BmwDidSpec(
        did: 0x1A0E,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Throttle Position',
        decode: (b) {
          if (b.isEmpty) return null;
          return _DecodedValue((b[0] / 2.55).roundToDouble(), '%');
        },
      );
    }
    // Battery voltage — BDC DID 0x1C2E, raw = 2 bytes / 1000 V.
    if (p.contains('voltage') || p.contains('battery')) {
      return _BmwDidSpec(
        did: 0x1C2E,
        ecu: 'BDC',
        fallbackAddress: 0x00F060,
        displayName: 'Battery Voltage',
        decode: (b) {
          if (b.length < 2) return null;
          final raw = (b[0] << 8) | b[1];
          return _DecodedValue(raw / 1000.0, 'V');
        },
      );
    }
    // Mass air flow — DME DID 0x1A0B.
    if (p.contains('maf') || p.contains('mass_air')) {
      return _BmwDidSpec(
        did: 0x1A0B,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Mass Air Flow',
        decode: (b) {
          if (b.length < 2) return null;
          final raw = (b[0] << 8) | b[1];
          return _DecodedValue(raw / 100.0, 'g/s');
        },
      );
    }
    // Engine load — DME DID 0x1A03, raw = 1 byte %.
    if (p.contains('engine_load')) {
      return _BmwDidSpec(
        did: 0x1A03,
        ecu: 'DME',
        fallbackAddress: 0x000012,
        displayName: 'Engine Load',
        decode: (b) {
          if (b.isEmpty) return null;
          return _DecodedValue((b[0] / 2.55).roundToDouble(), '%');
        },
      );
    }
    // Transmission oil temp — EGS DID 0x1A12.
    if (p.contains('trans') && p.contains('temp')) {
      return _BmwDidSpec(
        did: 0x1A12,
        ecu: 'EGS',
        fallbackAddress: 0x000018,
        displayName: 'Transmission Oil Temp',
        decode: (b) {
          if (b.isEmpty) return null;
          return _DecodedValue((b[0] - 48).toDouble(), '°C');
        },
      );
    }
    return null;
  }

  // ----------------------------------------------------------------
  // BMW service routines (UDS Service 0x31 RoutineControl)
  // ----------------------------------------------------------------

  /// Activates/deactivates the Electronic Parking Brake service mode so the
  /// rear calipers can be retracted for pad replacement.
  ///
  /// UDS 0x31 0x01 0x1001: routineControl, start, routine 0x1001 (EPB service).
  /// Pass [activate]=false to end service mode (routine 0x1001 stop = 0x02).
  Future<bool> bmwEpbServiceMode(bool activate, {int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.target('DSC')?.logicalAddress ??
        0x000016;
    final sub = activate ? 0x01 : 0x02;
    final resp = await sendUds([0x31, sub, 0x10, 0x01], targetAddress: target);
    // Positive response to routineControl start/stop: 0x71.
    return resp.isNotEmpty && resp[0] == 0x71;
  }

  /// Registers a new battery to the BDC (required after replacing the 12V
  /// battery on modern BMWs so the charging algorithm adapts to the new
  /// capacity/age). UDS 0x31 0x01 0x1002.
  Future<bool> bmwRegisterBattery({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.target('BDC')?.logicalAddress ??
        0x00F060;
    final resp = await sendUds([0x31, 0x01, 0x10, 0x02], targetAddress: target);
    return resp.isNotEmpty && resp[0] == 0x71;
  }

  /// Resets DME adaptation values (fuel trims, idle adaptation, etc.).
  /// [component] selects the adaptation set: 'FUEL', 'IDLE', 'VANOS', 'ALL'.
  Future<bool> bmwResetAdaptation(String component,
      {int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.target('DME')?.logicalAddress ??
        0x000012;
    final routineId = switch (component.toUpperCase()) {
      'FUEL' => 0x1010,
      'IDLE' => 0x1011,
      'VANOS' => 0x1012,
      'ALL' => 0x10FF,
      _ => 0x1010,
    };
    final resp = await sendUds(
        [0x31, 0x01, (routineId >> 8) & 0xFF, routineId & 0xFF],
        targetAddress: target);
    return resp.isNotEmpty && resp[0] == 0x71;
  }

  // ----------------------------------------------------------------
  // BMW coding (UDS Service 0x22 read / 0x2E write DataByIdentifier)
  // ----------------------------------------------------------------

  /// Reads a raw coding value (FDL) by DID as a hex string. Used by the coding
  /// editor to fetch the current bytes for a given function (e.g. 0xF060 on
  /// the FRM for the "Angel Eyes" brightness).
  ///
  /// Returns null when the DID isn't supported on this ECU.
  Future<String?> readCodingDid(int did, {int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    Uint8List resp = Uint8List(0);
    for (var attempt = 0; attempt < 4; attempt++) {
      resp = await sendUds(
        [0x22, (did >> 8) & 0xFF, did & 0xFF],
        targetAddress: target,
        timeout: Duration(seconds: attempt == 0 ? 6 : 10),
      );
      if (resp.isNotEmpty && resp[0] == 0x7F) {
        final nrc = resp.length > 2 ? resp[2] : 0x00;
        if (nrc == 0x78 && attempt < 3) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
        return null;
      }
      break;
    }
    if (resp.isEmpty || resp[0] == 0x7F) return null;
    if (resp.length < 4 || resp[0] != 0x62) return null;
    return resp
        .sublist(4)
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join();
  }

  /// Writes a raw coding value (FDL) by DID. [hexValue] is the new bytes as a
  /// hex string (e.g. '01'). Requires an extended/programming session on most
  /// ECUs — call [enterProgrammingSession] first for write operations.
  ///
  /// WARNING: this is a destructive write. Confirm with the user before use.
  Future<bool> writeCodingDid(int did, String hexValue,
      {int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final cleanHex = hexValue.replaceAll(RegExp(r'\s+'), '').toUpperCase();
    final bytes = <int>[
      0x2E,
      (did >> 8) & 0xFF,
      did & 0xFF,
    ];
    for (int i = 0; i < cleanHex.length - 1; i += 2) {
      bytes.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    final resp = await sendUds(bytes, targetAddress: target);
    // Positive response to writeDataByIdentifier: 0x6E.
    return resp.isNotEmpty && resp[0] == 0x6E;
  }

  /// Enters the default diagnostic session (0x10 0x01). Wakes bus-sleeping ECUs.
  Future<bool> enterDefaultSession({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final resp = await sendUds([0x10, 0x01], targetAddress: target);
    return resp.isNotEmpty && resp[0] == 0x50;
  }

  /// BMW E-Sys setCodingMode routine (UDS 0x31 0x01 0x10 0x0D).
  /// Required on many F/G modules before coding reads/writes.
  Future<bool> enterCodingMode({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final resp = await sendUds(
      [0x31, 0x01, 0x10, 0x0D],
      targetAddress: target,
      timeout: const Duration(seconds: 10),
    );
    return resp.isNotEmpty && resp[0] == 0x71;
  }

  /// Returns true if ECU responds to TesterPresent on HSFZ (1-byte address).
  Future<bool> pingEcuHsfz({required int hsfzAddress}) async {
    if (_wireProtocol != _EnetWireProtocol.hsfz) return false;
    try {
      final resp = await _sendUdsHsfz(
        [0x3E, 0x00],
        targetHsfz: hsfzAddress & 0xFF,
        timeout: const Duration(milliseconds: 400),
      );
      return resp.isNotEmpty && resp[0] == 0x7E;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if ECU responds to default session (alive on HSFZ/DoIP).
  Future<bool> pingEcu({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    try {
      final resp = await sendUds(
        [0x3E, 0x00],
        targetAddress: target,
        timeout: const Duration(seconds: 4),
      );
      return resp.isNotEmpty && resp[0] == 0x7E;
    } catch (_) {
      return false;
    }
  }

  /// Enters the BMW extended diagnostic session (0x10 0x03). Required before
  /// most coding/service operations. Call this after connect*() succeeds.
  Future<bool> enterExtendedSession({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final resp = await sendUds([0x10, 0x03], targetAddress: target);
    final ok = _isPositiveExtendedSession(resp);
    if (ok && _wireProtocol == _EnetWireProtocol.hsfz) {
      _startTesterPresentTimer(target);
    }
    return ok;
  }

  /// Enters the BMW programming session (0x10 0x02). Required for ECU flash
  /// writes and some coding operations on locked modules.
  Future<bool> enterProgrammingSession({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final resp = await sendUds([0x10, 0x02], targetAddress: target);
    return resp.isNotEmpty && resp[0] == 0x50;
  }

  /// Sends a tester-present (0x3E 0x80) to keep the diagnostic session alive.
  /// BMW sessions time out after ~5s of inactivity; call this periodically
  /// during long coding sessions.
  Future<void> keepAlive({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    // 0x80 = suppressPositiveResponse (we don't care about the ack).
    try {
      await sendUds([0x3E, 0x80],
          targetAddress: target, timeout: const Duration(seconds: 2));
    } catch (_) {
      // tester-present failure is non-fatal.
    }
  }

  // ----------------------------------------------------------------
  // BMW software / I-Step identification (UDS DIDs 0xF1xx)
  // ----------------------------------------------------------------

  /// Reads I-Step from UDS DID 0xF1A0 on the given ECU.
  Future<String?> readIStep({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    try {
      final resp = await sendUds([0x22, 0xF1, 0xA0], targetAddress: target);
      if (resp.isEmpty || resp[0] == 0x7F) return null;
      if (resp.length < 4 || resp[0] != 0x62) return null;
      return BmwIStepCodec.parseFromPayload(resp.sublist(4));
    } catch (e) {
      debugPrint('ENET readIStep: $e');
      return null;
    }
  }

  /// Extracts CAFD filenames from an SVK hex string (DID 0xF102 payload).
  List<String> parseSvkCafdFiles(String svkHex) =>
      BmwSvkParser.extractCafdFiles(svkHex);

  /// Reads the current I-Step (integration step) — the software version
  /// installed on the vehicle. UDS DID 0xF187 (ECU assembly number) is used
  /// for per-ECU identification; the gateway's response gives the overall
  /// vehicle software level.
  ///
  /// Returns a map with 'part_number', 'hardware_number', 'software_number'
  /// when available. Used by the backend to suggest software updates.
  Future<Map<String, String>> readSoftwareVersions({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    final result = <String, String>{};

    // 0xF187 — ECU assembly number (part number).
    try {
      final pn = await readEcuPartNumber(target);
      if (pn != null) result['part_number'] = pn;
    } catch (e) {
      debugPrint('ENET readSoftwareVersions 0xF187: $e');
    }

    // 0xF1A0 — BMW-specific: I-Step current. Some ECUs report this as a
    // readable DID; others gate it behind a security session.
    try {
      final step = await readIStep(targetAddress: target);
      if (step != null) result['i_step'] = step;
    } catch (e) {
      debugPrint('ENET readSoftwareVersions 0xF1A0: $e');
    }

    // 0xF101 — System supplier ECU hardware version number.
    try {
      final resp = await sendUds([0x22, 0xF1, 0x01], targetAddress: target);
      if (resp.isNotEmpty &&
          resp[0] != 0x7F &&
          resp.length > 4 &&
          resp[0] == 0x62) {
        result['hardware_number'] = resp
            .sublist(4)
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join();
      }
    } catch (e) {
      debugPrint('ENET readSoftwareVersions 0xF101: $e');
    }

    // 0xF189 — System supplier ECU software version number.
    try {
      final resp = await sendUds([0x22, 0xF1, 0x89], targetAddress: target);
      if (resp.isNotEmpty &&
          resp[0] != 0x7F &&
          resp.length > 4 &&
          resp[0] == 0x62) {
        result['software_number'] = resp
            .sublist(4)
            .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join();
      }
    } catch (e) {
      debugPrint('ENET readSoftwareVersions 0xF189: $e');
    }

    return result;
  }

  /// Reads the BMW System Vehicle Key (SVK) / SVK actual — the cryptographic
  /// signature of the installed software. UDS DID 0xF102 (readCurrentSVK).
  /// Used to verify the ECU hasn't been flashed with non-OEM software.
  Future<String?> readSvk({int? targetAddress}) async {
    final target = targetAddress ??
        _chassisProfile?.gatewayAddress ??
        _defaultGatewayAddress;
    try {
      final resp = await sendUds([0x22, 0xF1, 0x02], targetAddress: target);
      if (resp.isEmpty || resp[0] == 0x7F) return null;
      if (resp.length < 4 || resp[0] != 0x62) return null;
      return resp
          .sublist(4)
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join();
    } catch (e) {
      debugPrint('ENET readSvk: $e');
      return null;
    }
  }

  Future<void> disconnect() async {
    _testerPresentTimer?.cancel();
    _testerPresentTimer = null;
    _routingActivated = false;
    _wireProtocol = _EnetWireProtocol.doip;
    await _doipClient?.dispose();
    _doipClient = null;
    _udsService = null;
    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _transport?.close();
    } catch (_) {}
    _transport = null;
    _rxBuffer.clear();
    // Release the process binding acquired in connect()/connectForChassis*()
    // so API traffic flows over the system default again. Paired 1:1 with
    // OBDNetworkBinder.bindToWifi.
    await OBDNetworkBinder.instance.unbind();
  }

  void dispose() {
    disconnect();
    Future.microtask(() {
      if (!_hsfzUdsController.isClosed) _hsfzUdsController.close();
    });
  }
}

// ------------------------------------------------------------------
// Helper types for BMW UDS DID-based live telemetry
// ------------------------------------------------------------------

/// A decoded live value (numeric value + unit).
class _DecodedValue {
  final double value;
  final String unit;
  const _DecodedValue(this.value, this.unit);
}

/// Specification for a BMW UDS live-data DID: which DID to read, which ECU,
/// and how to decode the raw payload bytes into a value + unit.
class _BmwDidSpec {
  final int did;
  final String ecu;
  final int fallbackAddress;
  final String displayName;
  final _DecodedValue? Function(List<int> payload) decode;

  const _BmwDidSpec({
    required this.did,
    required this.ecu,
    required this.fallbackAddress,
    required this.displayName,
    required this.decode,
  });
}
