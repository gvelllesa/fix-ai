import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../classify_socket_exception_native.dart';
import '../../diagnostic_connection_exception.dart';
import '../../../../../core/services/obd_tcp_transport.dart';
import 'doip_constants.dart';

/// ISO 13400 DoIP client — routing activation, diagnostic messaging, and
/// TesterPresent keep-alive.
///
/// Logic adapted from [jacobschaer/doipclient](https://github.com/jacobschaer/doipclient):
/// open TCP → routing activation (payload type 0x0005) → exchange UDS inside
/// diagnostic messages (0x8001).
class DoipClient {
  DoipClient({
    int testerAddress = DoipConstants.defaultTesterAddress,
    int gatewayAddress = DoipConstants.defaultGatewayAddress,
  })  : _testerAddress = testerAddress,
        _gatewayAddress = gatewayAddress;

  ObdTcpTransport? _transport;
  StreamSubscription<Uint8List>? _subscription;
  final StreamController<Uint8List> _frameController =
      StreamController<Uint8List>.broadcast();
  final BytesBuilder _rxBuffer = BytesBuilder();

  Timer? _testerPresentTimer;
  bool _routingActivated = false;
  bool _disposed = false;

  // H5 FIX (audit): send mutex. Only one diagnostic request/response
  // exchange may be in flight at a time. The TesterPresent keep-alive timer
  // fires every 3s and also calls sendDiagnostic; without serialization both
  // the keep-alive and a real read would open a listener on the shared
  // broadcast _frameController and BOTH would receive the same response
  // frame — a keep-alive ack could then satisfy a real read's Completer,
  // silently delivering the wrong bytes to the wrong caller.
  Future<void> _sendMutex = Future<void>.value();

  final int _testerAddress;
  final int _gatewayAddress;

  bool get isRoutingActivated => _routingActivated;
  int get testerAddress => _testerAddress;
  int get gatewayAddress => _gatewayAddress;

  /// Attaches to an already-open TCP [transport], performs routing activation,
  /// and starts the TesterPresent timer loop.
  Future<void> attach(ObdTcpTransport transport) async {
    if (_disposed) {
      throw StateError('DoipClient has been disposed');
    }
    _transport = transport;
    _subscription = transport.inbound.listen(
      _onData,
      onError: (Object e) {
        debugPrint('DoipClient socket error: $e');
        _routingActivated = false;
      },
      onDone: () {
        debugPrint('DoipClient socket closed');
        _routingActivated = false;
      },
    );
    await activateRouting();
    _startTesterPresentLoop();
  }

  /// ISO 13400-2 routing activation handshake (payload type 0x0005).
  Future<void> activateRouting() async {
    final payload = <int>[
      (_testerAddress >> 8) & 0xFF,
      _testerAddress & 0xFF,
      DoipConstants.activationTypeDefault,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
    final frame = buildFrame(DoipConstants.routingActivationRequest, payload);

    final respCompleter = Completer<int>();
    StreamSubscription<Uint8List>? sub;
    sub = _frameController.stream.listen((f) {
      if (payloadTypeOf(f) == DoipConstants.routingActivationResponse) {
        final p = payloadOf(f);
        final code = p.length > 4 ? p[4] : 0xFF;
        if (!respCompleter.isCompleted) respCompleter.complete(code);
      }
    });

    try {
      await _write(frame);
      final code = await respCompleter.future.timeout(
        DoipConstants.routingActivationTimeout,
        onTimeout: () => -1,
      );
      if (code != DoipConstants.routingActivationSuccessful) {
        if (code == -1) {
          throw DiagnosticConnectionException(
            stage: DiagnosticStage.doipRoutingActivation,
            message: 'Socket opened, but DoIP Routing Activation timed out. '
                'The gateway did not reply within '
                '${DoipConstants.routingActivationTimeout.inSeconds}s.',
            wasTimeout: true,
            troubleshootingTip: 'The car is most likely off or not in ignition. '
                'Press START-STOP once (without brake) to reach terminal 15, '
                'then retry.',
          );
        }
        final codeName = doipCodeName(code) ?? 'Unknown DoIP response code';
        throw DiagnosticConnectionException(
          stage: DiagnosticStage.doipRoutingActivation,
          message: 'Gateway refused routing activation with code 0x'
              '${code.toRadixString(16).toUpperCase().padLeft(2, '0')} '
              '($codeName).',
          negativeResponseCode: code,
          troubleshootingTip: _tipForDoipCode(code),
        );
      }
      _routingActivated = true;
    } on DiagnosticConnectionException {
      rethrow;
    } on SocketException catch (e) {
      final base = classifySocketException(
        e,
        ip: '',
        port: DoipConstants.tcpPort,
      );
      throw DiagnosticConnectionException(
        stage: DiagnosticStage.doipRoutingActivation,
        message: 'Socket error during routing activation: ${base.message}',
        osError: base.osError,
        troubleshootingTip: base.troubleshootingTip,
        cause: e,
      );
    } finally {
      await sub.cancel();
    }
  }

  /// Sends a UDS PDU wrapped in a DoIP diagnostic message and waits for the
  /// ECU response bytes (without the 4-byte source/target header).
  Future<Uint8List> sendDiagnostic(
    List<int> udsRequest, {
    required int targetAddress,
    Duration timeout = DoipConstants.defaultUdsTimeout,
  }) async {
    if (_transport == null || !_routingActivated) {
      throw const DiagnosticConnectionException(
        stage: DiagnosticStage.socketEstablishment,
        message: 'DoIP client is not connected or routing is not activated.',
        troubleshootingTip: 'Retry the full connection flow.',
      );
    }

    // H5 FIX (audit): serialize diagnostic exchanges so the TesterPresent
    // keep-alive timer cannot race a real read on the shared frame stream.
    // We chain onto _sendMutex and only proceed once the previous send has
    // fully completed (response received or timeout). The next caller sees
    // a fresh Future and waits its turn.
    final wait = _sendMutex;
    final myRelease = Completer<void>();
    _sendMutex = myRelease.future;
    await wait;

    try {
      final payload = <int>[
        (_testerAddress >> 8) & 0xFF,
        _testerAddress & 0xFF,
        (targetAddress >> 8) & 0xFF,
        targetAddress & 0xFF,
        ...udsRequest,
      ];
      final frame = buildFrame(DoipConstants.diagnosticMessage, payload);

      final completer = Completer<Uint8List>();
      StreamSubscription<Uint8List>? sub;
      sub = _frameController.stream.listen((f) {
        final type = payloadTypeOf(f);
        if (type == DoipConstants.diagnosticMessageNegativeAck) {
          final p = payloadOf(f);
          final nackCode = p.length > 4 ? p[4] : 0x00;
          if (!completer.isCompleted) {
            completer.completeError(DiagnosticConnectionException(
              stage: DiagnosticStage.udsCommunication,
              message: 'Gateway refused to relay the UDS request '
                  '(DoIP NACK 0x${nackCode.toRadixString(16).toUpperCase().padLeft(2, '0')}).',
              negativeResponseCode: nackCode,
              troubleshootingTip: 'Confirm the chassis selection is correct and '
                  'that the target ECU is fitted to this car.',
            ));
          }
          return;
        }
        if (type == DoipConstants.diagnosticMessagePositiveAck) return;
        if (type == DoipConstants.diagnosticMessage) {
          final p = payloadOf(f);
          if (p.length > 4 && !completer.isCompleted) {
            completer.complete(Uint8List.fromList(p.sublist(4)));
          }
        }
      });

      try {
        await _write(frame);
        return await completer.future.timeout(timeout, onTimeout: () {
          throw DiagnosticConnectionException(
            stage: DiagnosticStage.udsCommunication,
            message: 'ECU 0x${targetAddress.toRadixString(16).toUpperCase().padLeft(6, '0')} '
                'did not answer within ${timeout.inSeconds}s.',
            wasTimeout: true,
            troubleshootingTip: 'The ECU may be asleep. Turn ignition ON and retry.',
          );
        });
      } on DiagnosticConnectionException {
        rethrow;
      } finally {
        await sub.cancel();
      }
    } finally {
      // Release the mutex for the next sender (real request or keep-alive).
      myRelease.complete();
    }
  }

  /// Sends TesterPresent (0x3E 0x00) to the gateway every 3 seconds.
  void _startTesterPresentLoop() {
    _testerPresentTimer?.cancel();
    _testerPresentTimer = Timer.periodic(
      DoipConstants.testerPresentInterval,
      (_) => _sendTesterPresent(),
    );
  }

  Future<void> _sendTesterPresent() async {
    if (_transport == null || !_routingActivated || _disposed) return;
    try {
      await sendDiagnostic(
        const [0x3E, 0x00],
        targetAddress: _gatewayAddress,
        timeout: const Duration(seconds: 2),
      );
    } catch (e) {
      debugPrint('DoipClient TesterPresent failed (non-fatal): $e');
    }
  }

  void stopTesterPresent() {
    _testerPresentTimer?.cancel();
    _testerPresentTimer = null;
  }

  void _onData(Uint8List chunk) {
    _rxBuffer.add(chunk);
    var bytes = _rxBuffer.toBytes();
    int offset = 0;
    while (bytes.length - offset >= 8) {
      final payloadLength = (bytes[offset + 4] << 24) |
          (bytes[offset + 5] << 16) |
          (bytes[offset + 6] << 8) |
          bytes[offset + 7];
      final frameTotal = 8 + payloadLength;
      if (bytes.length - offset < frameTotal) break;
      final frame = Uint8List.fromList(bytes.sublist(offset, offset + frameTotal));
      offset += frameTotal;
      if (!_frameController.isClosed) {
        _frameController.add(frame);
      }
    }
    _rxBuffer.clear();
    if (offset < bytes.length) {
      _rxBuffer.add(bytes.sublist(offset));
    }
  }

  Future<void> _write(Uint8List frame) async {
    await _transport!.write(frame);
    await _transport!.flush();
  }

  static Uint8List buildFrame(int payloadType, List<int> payload) {
    final len = payload.length;
    final frame = BytesBuilder();
    frame.addByte(DoipConstants.protocolVersion);
    frame.addByte(DoipConstants.inverseVersion);
    frame.addByte((payloadType >> 8) & 0xFF);
    frame.addByte(payloadType & 0xFF);
    frame.addByte((len >> 24) & 0xFF);
    frame.addByte((len >> 16) & 0xFF);
    frame.addByte((len >> 8) & 0xFF);
    frame.addByte(len & 0xFF);
    frame.add(payload);
    return frame.toBytes();
  }

  static int payloadTypeOf(Uint8List frame) => (frame[2] << 8) | frame[3];

  static Uint8List payloadOf(Uint8List frame) => frame.sublist(8);

  static String _tipForDoipCode(int code) {
    switch (code) {
      case 0x01:
        return 'All gateway sockets are busy. Wait for other testers to disconnect.';
      case 0x02:
      case 0x03:
        return 'Another tester holds this source address. Cycle ignition and retry.';
      case 0x04:
        return 'Gateway requires authentication this adapter cannot provide.';
      case 0x06:
        return 'Gateway rejected the activation type. Try a different ENET adapter.';
      case 0x07:
        return 'Gateway requires TLS. Plain DoIP cannot open a session on this car.';
      default:
        return 'Gateway refused routing (0x${code.toRadixString(16).toUpperCase().padLeft(2, '0')}).';
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    stopTesterPresent();
    _routingActivated = false;
    await _subscription?.cancel();
    _subscription = null;
    _transport = null;
    _rxBuffer.clear();
    if (!_frameController.isClosed) {
      await _frameController.close();
    }
  }
}
