import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'bluetooth_strategy.dart';
import 'kdcan_protocol.dart';

class AdapterEndpoint {
  final String host;
  final int port;
  final bool isDoip;
  final String? macAddress;
  final String? discoveredVin;

  const AdapterEndpoint({
    required this.host,
    required this.port,
    this.isDoip = false,
    this.macAddress,
    this.discoveredVin,
  });
}

/// Discovered BMW ZGW / BDC ENET Gateway metadata from UDP port 6811
class EnetGatewayIdentity {
  final String ipAddress;
  final int diagPort;
  final String? macAddress;
  final String? vin;
  final Uint8List rawPayload;

  const EnetGatewayIdentity({
    required this.ipAddress,
    this.diagPort = 6801,
    this.macAddress,
    this.vin,
    required this.rawPayload,
  });
}

/// Serializes all UDS requests in a FIFO queue to prevent concurrent
/// requests from colliding on the bus or stealing each other's completers.
class _UdsQueue {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() task) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await task());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }
}

/// BMW ENET / HSFZ / DoIP Low-level Diagnostic Protocol Engine
/// 
/// Hardened according to ISO 14229-1 (UDS), ISO 13400 (DoIP), and BMW HSFZ specifications.
/// Implements serialized request queuing, response-request echo matching,
/// NRC 0x78 (responsePending) extended P2* waiting, and DoIP routing activation validation.
class EnetHsfzProtocol {
  static const int testerAddress = 0xF4;       // Standard Diagnostic Tool Address (HSFZ)
  static const int doipTesterSa = 0x0EF4;      // ISO 13400 DoIP Diagnostic Source Address
  static const int functionalAddress = 0xDF;   // Functional broadcast address for BMW ZGW
  static const int zgwAddress = 0x10;          // Central Gateway Module (ZGW/FEM)
  static const int dmeAddress = 0x12;          // Digital Motor Electronics (Engine ECU)
  static const int egsAddress = 0x18;          // Electronic Transmission Control (Gearbox)
  static const int dscAddress = 0x29;          // Dynamic Stability Control
  static const int casAddress = 0x40;          // Car Access System / BDC
  static const int kombiAddress = 0x60;        // Instrument Cluster
  static const int huNbtAddress = 0x63;        // Headunit NBT / Navigation
  static const int ihkaAddress = 0x6D;         // Climate Control

  // HSFZ Message Types
  static const int hsfzTypeData = 0x0001;        // Valid Application Payload
  static const int hsfzTypeGatewayEcho = 0x0002; // Gateway Acknowledgment (Ignored)
  static const int hsfzTypeControlIgnit = 0x0010;// Control Port 6811 Ignition/Clamp State
  static const int hsfzTypeVehicleIdent = 0x0011;// UDP Port 6811 Vehicle Identification
  static const int hsfzTypeAliveCheck = 0x0012;  // Gateway Keepalive Ping
  static const int hsfzTypeAliveResp = 0x0013;   // Gateway Keepalive Pong

  static const int kEnetDiagPort = 6801;         // Standard BMW ZGW HSFZ TCP Port
  static const int kEnetControlPort = 6811;      // Standard BMW ZGW UDP/TCP Control Port
  static const int kDoipPort = 13400;            // ISO 13400-2 DoIP Port

  static const int _maxHsfzBody = 0x10000 + 2; // 64KB + 2 bytes addr header

  Socket? _socket;
  StreamSubscription? _subscription;
  BluetoothStrategy? _bleStrategy;
  BluetoothStrategy? get bleStrategy => _bleStrategy;
  KdcanProtocol? _kdcanProtocol;
  KdcanProtocol? get kdcanProtocol => _kdcanProtocol;

  Uint8List _rxBuffer = Uint8List(128 * 1024);
  int _rxLen = 0;
  int _rxOffset = 0;
  final StreamController<HsfzMessage> _messageStreamController = StreamController<HsfzMessage>.broadcast();
  Stream<HsfzMessage> get messageStream => _messageStreamController.stream;

  final _UdsQueue _queue = _UdsQueue();
  void Function(int type, Uint8List payload)? _doipControlHandler;

  static String? lastConnectedHost;
  static int? lastConnectedPort;

  bool _isDoIpMode = false;
  bool get isConnected =>
      _socket != null ||
      (_bleStrategy != null && _bleStrategy!.isConnected) ||
      (_kdcanProtocol != null && _kdcanProtocol!.isConnected);
  bool get isBleIsoTpMode =>
      _socket == null && _bleStrategy != null && _bleStrategy!.isConnected;
  bool get isKdcanMode =>
      _socket == null &&
      !isBleIsoTpMode &&
      _kdcanProtocol != null &&
      _kdcanProtocol!.isConnected;
  static const MethodChannel _netBindChannel = MethodChannel('fixai/netbind');

  /// Attaches an active [BluetoothStrategy] (ELM327 / STN / vLinker) so that all
  /// BMW UDS services seamlessly operate over ISO 15765-2 Extended CAN Addressing.
  void attachBleStrategy(BluetoothStrategy? strategy) {
    _bleStrategy = strategy;
  }

  /// Attaches an active [KdcanProtocol] (USB FTDI INPA K+DCAN cable) so that all
  /// BMW E-Series & F-Series services operate seamlessly over K-Line / D-CAN.
  void attachKdcanProtocol(KdcanProtocol? kdcan) {
    _kdcanProtocol = kdcan;
  }

  /// Builds the 6-byte HSFZ UDP Vehicle Identification broadcast packet (`00 00 00 00 00 11`)
  /// sent to UDP port 6811 (`EdiabasLib.EdInterfaceEnet` / `UNI_Flash.EnetConnectivityHelper`).
  static Uint8List buildUdpIdentRequest() {
    return Uint8List.fromList(const [0x00, 0x00, 0x00, 0x00, 0x00, hsfzTypeVehicleIdent]);
  }

  /// Builds the 6-byte HSFZ TCP Control Port 6811 Ignition / Terminal status request (`00 00 00 00 00 10`).
  static Uint8List buildControlIgnitRequest() {
    return Uint8List.fromList(const [0x00, 0x00, 0x00, 0x00, 0x00, hsfzTypeControlIgnit]);
  }

  /// Parses a UDP Port 6811 Vehicle Identification datagram from BMW ZGW / BDC.
  static EnetGatewayIdentity? parseUdpIdentResponse(String responderIp, Uint8List datagram) {
    if (datagram.length < 6) return null;
    final bd = ByteData.sublistView(datagram);
    final payloadLen = bd.getUint32(0, Endian.big);
    final msgType = bd.getUint16(4, Endian.big);
    if (msgType != hsfzTypeVehicleIdent) return null;

    final body = datagram.length >= 6 + payloadLen
        ? Uint8List.sublistView(datagram, 6, 6 + payloadLen)
        : Uint8List.sublistView(datagram, 6);

    String? mac;
    String? vin;

    // Extract ASCII fields (e.g. "DIAGADR10BMWMAC001A3F...VINWBA...") or raw 17-char VIN
    final asciiText = String.fromCharCodes(
      body.where((b) => b >= 0x20 && b <= 0x7E),
    );
    final vinMatch = RegExp(r'VIN([A-HJ-NPR-Z0-9]{17})').firstMatch(asciiText) ??
        RegExp(r'([WBA|WBS|WBY|5UX|5YM|4US][A-HJ-NPR-Z0-9]{14})').firstMatch(asciiText);
    if (vinMatch != null) {
      vin = vinMatch.group(1);
    }
    final macMatch = RegExp(r'BMWMAC([0-9A-Fa-f]{12})').firstMatch(asciiText);
    if (macMatch != null) {
      final rawMac = macMatch.group(1)!.toUpperCase();
      mac = List.generate(6, (i) => rawMac.substring(i * 2, i * 2 + 2)).join(':');
    } else if (body.length >= 6 && asciiText.length < 6) {
      mac = body
          .sublist(0, 6)
          .map((b) => b.toRadixString(16).toUpperCase().padLeft(2, '0'))
          .join(':');
    }

    return EnetGatewayIdentity(
      ipAddress: responderIp,
      diagPort: kEnetDiagPort,
      macAddress: mac,
      vin: vin,
      rawPayload: Uint8List.fromList(body),
    );
  }

  /// Parses TCP Control Port 6811 Ignition / Terminal 15 clamp status response (`msgType == 0x0010`).
  /// Returns `true` when ignition (KL15) is active.
  static bool? parseControlIgnitResponse(Uint8List frame) {
    if (frame.length < 7) return null;
    final bd = ByteData.sublistView(frame);
    final len = bd.getUint32(0, Endian.big);
    final msgType = bd.getUint16(4, Endian.big);
    if (msgType != hsfzTypeControlIgnit || len < 1) return null;
    final clampByte = frame[6];
    // Bit 0 / 0x01 or 0x04 indicates Terminal 15 / Ignition ON in ZGW control response
    return (clampByte & 0x0F) != 0;
  }

  /// Broadcasts a UDP Vehicle Identification request on port 6811 to dynamically discover
  /// any connected BMW ZGW/BDC gateway on Link-Local (169.254.x.x) or Wi-Fi/DHCP subnets.
  Future<EnetGatewayIdentity?> discoverGatewayViaUdp({
    Duration timeout = const Duration(milliseconds: 900),
  }) async {
    RawDatagramSocket? udp;
    StreamSubscription<RawSocketEvent>? sub;
    try {
      udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      udp.broadcastEnabled = true;

      final completer = Completer<EnetGatewayIdentity?>();
      sub = udp.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = udp?.receive();
          if (dg != null) {
            final parsed = parseUdpIdentResponse(dg.address.address, dg.data);
            if (parsed != null && !completer.isCompleted) {
              completer.complete(parsed);
            }
          }
        }
      });

      final req = buildUdpIdentRequest();
      final broadcastTargets = [
        '255.255.255.255',
        '169.254.255.255',
        '192.168.16.255',
        '192.168.0.255',
        '192.168.1.255',
      ];
      for (final target in broadcastTargets) {
        try {
          udp.send(req, InternetAddress(target), kEnetControlPort);
        } catch (_) {}
      }

      return await completer.future.timeout(timeout, onTimeout: () => null);
    } catch (e) {
      debugPrint('[ENET-HSFZ] UDP 6811 discovery notice: $e');
      return null;
    } finally {
      await sub?.cancel();
      udp?.close();
    }
  }

  /// Queries TCP Control Port 6811 on the BMW gateway to check hardware KL15 ignition status.
  Future<bool?> readControlPortIgnitionState({
    String? host,
    Duration timeout = const Duration(milliseconds: 1000),
  }) async {
    final targetHost = host ?? lastConnectedHost ?? '192.168.16.101';
    Socket? ctrlSocket;
    try {
      ctrlSocket = await Socket.connect(targetHost, kEnetControlPort, timeout: timeout);
      final completer = Completer<Uint8List>();
      final sub = ctrlSocket.listen(
        (data) {
          if (!completer.isCompleted) {
            completer.complete(Uint8List.fromList(data));
          }
        },
        onError: (_) {},
      );
      ctrlSocket.add(buildControlIgnitRequest());
      await ctrlSocket.flush();
      final rsp = await completer.future.timeout(timeout);
      await sub.cancel();
      return parseControlIgnitResponse(rsp);
    } catch (_) {
      return null;
    } finally {
      ctrlSocket?.destroy();
    }
  }

  /// Sweeps UDP port 6811 broadcast first, then candidate IPs and ports [35000, 6801, 13400, 50160]
  Future<AdapterEndpoint?> detectAdapter({String? preferredHost}) async {
    // 1. Dynamic UDP Broadcast Discovery on Port 6811 (EdInterfaceEnet / UNI_Flash standard)
    if (preferredHost == null || preferredHost.isEmpty) {
      final discovered = await discoverGatewayViaUdp();
      if (discovered != null) {
        for (final port in const [kEnetDiagPort, kDoipPort]) {
          try {
            final s = await Socket.connect(
              discovered.ipAddress,
              port,
              timeout: const Duration(milliseconds: 350),
            );
            await s.close();
            lastConnectedHost = discovered.ipAddress;
            lastConnectedPort = port;
            return AdapterEndpoint(
              host: discovered.ipAddress,
              port: port,
              isDoip: port == kDoipPort,
              macAddress: discovered.macAddress,
              discoveredVin: discovered.vin,
            );
          } catch (_) {}
        }
      }
    }

    // 2. Fallback to known candidate IPs and ports
    final candidateHosts = [
      if (preferredHost != null && preferredHost.isNotEmpty) preferredHost,
      if (lastConnectedHost != null && lastConnectedHost!.isNotEmpty) lastConnectedHost!,
      '192.168.1.10',   // Bench Simulator / PC host on LAN
      '192.168.16.101', // Hardware profile: Transparent UART-ETH-WIFI bridge
      '192.168.0.10',   // Common ENET WiFi bridge adapter
      '169.254.1.1',    // Direct ENET cable Link-Local fallback
    ];

    const ports = [35000, 6801, 13400, 50160];

    for (final host in candidateHosts) {
      for (final port in ports) {
        try {
          final s = await Socket.connect(host, port, timeout: const Duration(milliseconds: 300));
          await s.close();
          debugPrint('[ENET-HSFZ] Found active adapter port at $host:$port');
          lastConnectedHost = host;
          lastConnectedPort = port;
          return AdapterEndpoint(host: host, port: port, isDoip: port == 13400);
        } catch (_) {}
      }
    }
    return null;
  }

  /// Connects to vehicle endpoint with port auto-negotiation and DoIP routing activation
  Future<bool> connect({
    String host = '192.168.16.101', 
    int port = 35000, 
    bool? useDoip,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    await disconnect();
    _isDoIpMode = useDoip ?? (port == 13400);

    // On Android, force traffic through Wi-Fi adapter even when no internet connection is present
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _netBindChannel.invokeMethod('bindWifi');
      } catch (e) {
        debugPrint('[ENET-HSFZ] Network bind notice: $e');
      }
    }

    try {
      debugPrint('[ENET-HSFZ] Connecting to $host:$port (DoIP=$_isDoIpMode)...');
      _socket = await Socket.connect(host, port, timeout: timeout);
      _socket!.setOption(SocketOption.tcpNoDelay, true);
      lastConnectedHost = host;
      lastConnectedPort = port;

      _subscription = _socket!.listen(
        _handleRawIncomingBytes,
        onError: (err) {
          debugPrint('[ENET-HSFZ] Socket error: $err');
          disconnect();
        },
        onDone: () {
          debugPrint('[ENET-HSFZ] Socket closed by vehicle.');
          disconnect();
        },
      );

      if (_isDoIpMode) {
        // Send ISO 13400 Routing Activation Request and verify confirmation
        final activated = await _sendDoIpRoutingActivation();
        if (!activated) {
          debugPrint('[ENET-HSFZ] DoIP Routing Activation failed or rejected by gateway.');
          await disconnect();
          return false;
        }
      }

      debugPrint('[ENET-HSFZ] Connection established successfully to $host:$port');
      return true;
    } catch (e) {
      debugPrint('[ENET-HSFZ] Connection failed to $host:$port: $e');
      await disconnect();
      return false;
    }
  }

  @visibleForTesting
  void emitMessageForTest(HsfzMessage msg) => _messageStreamController.add(msg);

  @visibleForTesting
  void handleRawBytesForTest(List<int> chunk) => _handleRawIncomingBytes(chunk);

  void _handleRawIncomingBytes(List<int> chunk) {
    if (_rxOffset > 0 && _rxLen > 0) {
      _rxBuffer.setRange(0, _rxLen, _rxBuffer, _rxOffset);
      _rxOffset = 0;
    } else if (_rxLen == 0) {
      _rxOffset = 0;
    }

    if (_rxOffset + _rxLen + chunk.length > _rxBuffer.length) {
      final newCapacity = (_rxBuffer.length * 2).clamp(128 * 1024, 1024 * 1024);
      if (_rxLen + chunk.length > newCapacity) {
        debugPrint('[ENET-HSFZ] RX buffer overflow (${_rxLen + chunk.length} bytes) — disconnecting');
        disconnect();
        return;
      }
      final newBuf = Uint8List(newCapacity);
      if (_rxLen > 0) {
        newBuf.setRange(0, _rxLen, _rxBuffer, _rxOffset);
      }
      _rxBuffer = newBuf;
      _rxOffset = 0;
    }

    _rxBuffer.setRange(_rxOffset + _rxLen, _rxOffset + _rxLen + chunk.length, chunk);
    _rxLen += chunk.length;

    if (_isDoIpMode) {
      _processDoIpBuffer();
    } else {
      _processHsfzBuffer();
    }
  }

  static bool _isValidHsfzMsgType(int msgType) =>
      msgType == hsfzTypeData ||
      msgType == hsfzTypeGatewayEcho ||
      msgType == hsfzTypeAliveCheck ||
      msgType == hsfzTypeAliveResp ||
      (msgType >= 0x0040 && msgType <= 0x0049);

  /// Processes HSFZ packet format:
  /// [4 bytes: Body Length N] [2 bytes: Msg Type] [1 byte: Src] [1 byte: Dst] [N-2 bytes: UDS]
  void _processHsfzBuffer() {
    while (_rxLen >= 6) {
      final byteData = ByteData.sublistView(_rxBuffer, _rxOffset, _rxOffset + _rxLen);
      final bodyLength = byteData.getUint32(0, Endian.big);
      final msgType = byteData.getUint16(4, Endian.big);

      // Validate body length and message type to resynchronize corrupted streams
      if (bodyLength > _maxHsfzBody || bodyLength == 0 || !_isValidHsfzMsgType(msgType)) {
        _rxOffset++;
        _rxLen--;
        continue;
      }

      final totalPacketSize = 6 + bodyLength;
      if (_rxLen < totalPacketSize) {
        // Incomplete packet, wait for remaining bytes
        break;
      }

      final bodyBytes = Uint8List.sublistView(_rxBuffer, _rxOffset + 6, _rxOffset + totalPacketSize);
      _rxOffset += totalPacketSize;
      _rxLen -= totalPacketSize;

      switch (msgType) {
        case hsfzTypeData:
          if (bodyBytes.length >= 2) {
            final src = bodyBytes[0];
            final dst = bodyBytes[1];
            final udsPayload = Uint8List.sublistView(bodyBytes, 2);
            _messageStreamController.add(HsfzMessage(
              sourceAddress: src,
              targetAddress: dst,
              messageType: msgType,
              payload: Uint8List.fromList(udsPayload),
            ));
          }
          break;
        case hsfzTypeAliveCheck:
          // TODO(verify-on-ecu): verify HSFZ gateway keepalive ping 0x0012 / 0x0013 response on target vehicle
          _sendHsfzControl(hsfzTypeAliveResp, const [testerAddress, 0x00]);
          break;
        case hsfzTypeGatewayEcho:
          // Informational gateway echo, ignore safely
          break;
        default:
          if (msgType >= 0x0040) {
            debugPrint('[ENET-HSFZ] HSFZ NACK received: 0x${msgType.toRadixString(16)}');
          }
          break;
      }
    }
  }

  /// Processes ISO 13400 DoIP packet format:
  /// [1 byte: Version] [1 byte: InvVersion] [2 bytes: PayloadType] [4 bytes: Length N] [N bytes: Payload]
  void _processDoIpBuffer() {
    while (_rxLen >= 8) {
      final byteData = ByteData.sublistView(_rxBuffer, _rxOffset, _rxOffset + _rxLen);
      final ver = byteData.getUint8(0);
      final invVer = byteData.getUint8(1);
      final payloadType = byteData.getUint16(2, Endian.big);
      final payloadLength = byteData.getUint32(4, Endian.big);

      // ISO 13400 synchronization check: (ver ^ invVer) must equal 0xFF
      if ((ver ^ invVer) != 0xFF || payloadLength > _maxHsfzBody) {
        _rxOffset++;
        _rxLen--;
        continue;
      }

      final totalPacketSize = 8 + payloadLength;
      if (_rxLen < totalPacketSize) break;

      final payloadBytes = Uint8List.sublistView(_rxBuffer, _rxOffset + 8, _rxOffset + totalPacketSize);
      _rxOffset += totalPacketSize;
      _rxLen -= totalPacketSize;

      if (payloadType == 0x0006) {
        // Routing Activation Response
        _doipControlHandler?.call(payloadType, Uint8List.fromList(payloadBytes));
      } else if (payloadType == 0x8002 || payloadType == 0x0008) {
        // Diagnostic Message Positive Ack (0x8002) or Alive Check Response (0x0008)
        continue;
      } else if (payloadType == 0x8001 || payloadType == 0x0007) {
        // Diagnostic Message (ISO 13400 standard 0x8001): [2 bytes: SA] [2 bytes: TA] [UDS Payload]
        if (payloadBytes.length >= 4) {
          final sa = (payloadBytes[0] << 8) | payloadBytes[1];
          final ta = (payloadBytes[2] << 8) | payloadBytes[3];
          final uds = Uint8List.sublistView(payloadBytes, 4);

          final message = HsfzMessage(
            sourceAddress: sa & 0xFF,
            targetAddress: ta & 0xFF,
            messageType: hsfzTypeData,
            payload: Uint8List.fromList(uds),
          );
          _messageStreamController.add(message);
        }
      } else if (payloadType == 0x0003 || payloadType == 0x8003) {
        debugPrint('[ENET-DoIP] Gateway NACK 0x${payloadType.toRadixString(16)}');
      }
    }
  }

  /// Sends raw HSFZ message: [Length 4B] [0x0001 2B] [Src 1B] [Dst 1B] [UDS bytes]
  Future<void> sendHsfz(int dst, List<int> udsPayload, {int src = testerAddress}) async {
    if (isBleIsoTpMode) {
      await _bleStrategy!.sendUdsOverIsoTp(dst, udsPayload);
      return;
    }
    if (isKdcanMode) {
      await _kdcanProtocol!.sendKwpAndAwait(dst, udsPayload);
      return;
    }
    if (_socket == null) throw StateError('Not connected to vehicle socket');

    if (_isDoIpMode) {
      await _sendDoIpDiagMessage(dst, udsPayload, src: src);
      return;
    }

    final body = Uint8List(2 + udsPayload.length);
    body[0] = src;
    body[1] = dst;
    body.setRange(2, body.length, udsPayload);

    final frame = ByteData(6 + body.length);
    frame.setUint32(0, body.length, Endian.big);
    frame.setUint16(4, hsfzTypeData, Endian.big);
    for (int i = 0; i < body.length; i++) {
      frame.setUint8(6 + i, body[i]);
    }

    _socket!.add(frame.buffer.asUint8List());
    await _socket!.flush();
  }

  void _sendHsfzControl(int msgType, List<int> payload) {
    if (_socket == null) return;
    final frame = ByteData(6 + payload.length);
    frame.setUint32(0, payload.length, Endian.big);
    frame.setUint16(4, msgType, Endian.big);
    for (int i = 0; i < payload.length; i++) {
      frame.setUint8(6 + i, payload[i]);
    }
    _socket!.add(frame.buffer.asUint8List());
  }

  /// Functional broadcast to all ECUs (e.g. DTC disable 0x85 or comm control 0x28)
  Future<void> sendFunctional(List<int> udsPayload) => sendHsfz(functionalAddress, udsPayload);

  /// Fire-and-forget message without expecting positive response (e.g. TesterPresent 0x3E 0x80)
  Future<void> sendFireAndForget(int targetEcu, List<int> udsPayload) => sendHsfz(targetEcu, udsPayload);

  Future<bool> _sendDoIpRoutingActivation() async {
    // ISO 13400 Routing Activation: SA = doipTesterSa (0x0EF4), Activation Type = 0x00
    final completer = Completer<Uint8List>();
    _doipControlHandler = (type, payload) {
      if (type == 0x0006 && !completer.isCompleted) {
        completer.complete(payload);
      }
    };

    final packet = Uint8List(8 + 7);
    final bd = ByteData.sublistView(packet);
    bd.setUint8(0, 0x02); // DoIP version
    bd.setUint8(1, 0xFD); // Inv version
    bd.setUint16(2, 0x0005, Endian.big); // Routing Activation Req
    bd.setUint32(4, 7, Endian.big); // Length
    bd.setUint16(8, doipTesterSa, Endian.big); // Source address
    bd.setUint8(10, 0x00); // Default activation
    bd.setUint32(11, 0x00000000, Endian.big); // Reserved

    try {
      _socket!.add(packet);
      await _socket!.flush();
      final resp = await completer.future.timeout(const Duration(seconds: 3));
      // Response format: [testerSA 2B][entitySA 2B][responseCode 1B]
      final success = resp.length >= 5 && resp[4] == 0x10;
      debugPrint('[ENET-DoIP] Routing Activation response code: 0x${resp.length >= 5 ? resp[4].toRadixString(16) : "??"} (Success: $success)');
      return success;
    } on TimeoutException {
      debugPrint('[ENET-DoIP] Routing Activation timed out.');
      return false;
    } finally {
      _doipControlHandler = null;
    }
  }

  Future<void> _sendDoIpDiagMessage(int dst, List<int> udsPayload, {int src = testerAddress}) async {
    final payloadLen = 4 + udsPayload.length;
    final packet = Uint8List(8 + payloadLen);
    final bd = ByteData.sublistView(packet);
    bd.setUint8(0, 0x02);
    bd.setUint8(1, 0xFD);
    bd.setUint16(2, 0x8001, Endian.big); // Diagnostic Message (ISO 13400-2 standard)
    bd.setUint32(4, payloadLen, Endian.big);
    bd.setUint16(8, doipTesterSa, Endian.big); // Consistent SA matching routing activation
    bd.setUint16(10, dst, Endian.big);
    for (int i = 0; i < udsPayload.length; i++) {
      packet[12 + i] = udsPayload[i];
    }
    _socket!.add(packet);
    await _socket!.flush();
  }

  /// Sends a UDS command and awaits the corresponding response from the specific ECU.
  /// Execution is serialized via FIFO queue to completely eliminate race conditions.
  /// Handles NRC 0x78 (responsePending) with P2* extended timeout (up to 30s).
  /// Verifies exact request-response echo matching for DIDs, RIDs, and sub-functions.
  Future<Uint8List?> sendUdsAndAwait(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(milliseconds: 1500),
    Duration p2Star = const Duration(seconds: 10),
    int maxPending = 60,
  }) {
    return _queue.run(() async {
      final sid = udsPayload[0];
      final isSuppress = udsPayload.length > 1 && _hasSubFunction(sid) && (udsPayload[1] & 0x80) != 0;
      if (isSuppress) {
        await sendHsfz(targetEcu, udsPayload);
        return Uint8List(0);
      }

      if (isBleIsoTpMode) {
        final p = await _bleStrategy!.sendUdsOverIsoTp(
          targetEcu,
          udsPayload,
          timeout: timeout,
          p2Star: p2Star,
          maxPending: maxPending,
        );
        if (p == null || p.isEmpty) return null;
        if (p[0] == 0x7F && p.length >= 3 && p[1] == sid) {
          return p;
        }
        if (p[0] == ((sid + 0x40) & 0xFF) && _echoMatches(udsPayload, p)) {
          return p;
        }
        return null;
      }

      if (isKdcanMode) {
        final p = await _kdcanProtocol!.sendKwpAndAwait(
          targetEcu,
          udsPayload,
          timeout: timeout,
          p2Star: p2Star,
          maxPending: maxPending,
        );
        if (p == null || p.isEmpty) return null;
        if (p[0] == 0x7F && p.length >= 3 && p[1] == sid) {
          return p;
        }
        if (p[0] == ((sid + 0x40) & 0xFF)) {
          return p;
        }
        return null;
      }

      final inbox = StreamController<Uint8List>();
      final sub = messageStream
          .where((m) => m.sourceAddress == targetEcu && m.payload.isNotEmpty)
          .listen((m) => inbox.add(m.payload));
      final it = StreamIterator(inbox.stream);

      try {
        await sendHsfz(targetEcu, udsPayload);
        var currentWait = timeout;
        var pendingCount = 0;

        while (true) {
          final hasData = await it.moveNext().timeout(currentWait, onTimeout: () => false);
          if (!hasData) return null;

          final p = it.current;

          // Check Negative Response (NRC)
          if (p[0] == 0x7F && p.length >= 3 && p[1] == sid) {
            final nrc = p[2];
            if (nrc == 0x78 && ++pendingCount <= maxPending) {
              // ECU is actively processing (responsePending), wait extended P2*
              currentWait = p2Star;
              continue;
            }
            return p;
          }

          // Check Positive Response: SID + 0x40 and echo matching
          if (p[0] == ((sid + 0x40) & 0xFF) && _echoMatches(udsPayload, p)) {
            return p;
          }
          // Non-matching response (stale or delayed frame from another operation) — continue waiting
        }
      } finally {
        await sub.cancel();
        await it.cancel();
        await inbox.close();
      }
    });
  }

  static bool _hasSubFunction(int sid) =>
      const {0x10, 0x11, 0x19, 0x27, 0x28, 0x31, 0x3E, 0x85}.contains(sid);

  static bool _echoMatches(List<int> req, Uint8List rsp) {
    int echoBytes;
    switch (req[0]) {
      case 0x22: // ReadDataByIdentifier
      case 0x2E: // WriteDataByIdentifier
      case 0x2F: // InputOutputControlByIdentifier
        // If 4-byte DID (e.g. RAM DID 0xD0016096), echo is 4 bytes, otherwise 2
        echoBytes = (req.length >= 5 && req[1] == 0xD0 && req[2] == 0x01) ? 4 : 2;
        break;
      case 0x31: // RoutineControl (subFunction + 2 bytes RID)
        echoBytes = 3;
        break;
      case 0x36: // TransferData (blockSequenceCounter)
        echoBytes = 1;
        break;
      case 0x10: // DiagnosticSessionControl
      case 0x11: // ECUReset
      case 0x19: // ReadDTCInformation
      case 0x27: // SecurityAccess
      case 0x28: // CommunicationControl
      case 0x85: // ControlDTCSetting
        echoBytes = 1;
        break;
      default:
        echoBytes = 0;
        break;
    }

    if (rsp.length < 1 + echoBytes || req.length < 1 + echoBytes) return false;
    for (var i = 1; i <= echoBytes; i++) {
      final reqVal = (i == 1 && _hasSubFunction(req[0])) ? (req[i] & 0x7F) : req[i];
      if (rsp[i] != reqVal) return false;
    }
    return true;
  }

  /// Sends a UDS command and awaits response, returning Uint8List (or empty on failure)
  Future<Uint8List> sendUdsRequest(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(seconds: 2),
    Duration p2Star = const Duration(seconds: 10),
  }) async {
    final response = await sendUdsAndAwait(targetEcu, udsPayload, timeout: timeout, p2Star: p2Star);
    return response ?? Uint8List(0);
  }

  /// Requests Diagnostic Trouble Codes from an ECU (UDS 0x19 0x02 0x0A)
  Future<List<String>> readDtcCodes(int targetEcu) async {
    final response = await sendUdsAndAwait(targetEcu, [0x19, 0x02, 0x0A], timeout: const Duration(seconds: 4));
    if (response == null || response.length < 3) return [];

    final codes = <String>[];
    // Response format: 0x59 0x02 <status_availability_mask> [<DTC high> <DTC mid> <DTC low> <status>] * N
    final dtcBytes = response.sublist(3);
    for (int i = 0; i + 3 <= dtcBytes.length; i += 4) {
      final b1 = dtcBytes[i];
      final b2 = dtcBytes[i + 1];
      final b3 = dtcBytes[i + 2];
      final status = (i + 3 < dtcBytes.length) ? dtcBytes[i + 3] : 0;

      // Format DTC and include UDS status bit description (0x08: confirmed, 0x01: testFailed)
      final hexCode = ((b1 << 16) | (b2 << 8) | b3).toRadixString(16).toUpperCase().padLeft(6, '0');
      final standardDtc = _formatStandardDtc(b1, b2, b3);
      final statusDesc = (status & 0x08 != 0) ? 'Confirmed' : ((status & 0x01 != 0) ? 'Active' : 'History');
      codes.add('$standardDtc ($hexCode) [$statusDesc]');
    }
    return codes;
  }

  /// Clears Diagnostic Trouble Codes on an ECU (UDS 0x14 0xFF 0xFF 0xFF)
  Future<bool> clearDtcCodes(int targetEcu) async {
    final response = await sendUdsAndAwait(targetEcu, [0x14, 0xFF, 0xFF, 0xFF], timeout: const Duration(seconds: 4));
    return response != null && response.isNotEmpty && response[0] == 0x54;
  }

  /// Reads standard vehicle VIN (DID 0xF190)
  Future<String?> readVin(int targetEcu) async {
    final response = await sendUdsAndAwait(targetEcu, [0x22, 0xF1, 0x90], timeout: const Duration(seconds: 4));
    if (response == null || response.length < 3) return null;
    // Response: [0x62 0xF1 0x90 <VIN ASCII bytes 17>]
    final asciiBytes = response.sublist(3);
    try {
      final vin = String.fromCharCodes(asciiBytes).trim();
      if (vin.length >= 17) return vin.substring(0, 17);
      return vin;
    } catch (_) {
      return null;
    }
  }

  String _formatStandardDtc(int b1, int b2, int b3) {
    String prefix;
    final type = (b1 >> 6) & 0x03;
    switch (type) {
      case 0: prefix = 'P'; break;
      case 1: prefix = 'C'; break;
      case 2: prefix = 'B'; break;
      case 3: prefix = 'U'; break;
      default: prefix = 'P';
    }
    final digit1 = (b1 >> 4) & 0x03;
    final digit2 = b1 & 0x0F;
    final digit3 = (b2 >> 4) & 0x0F;
    final digit4 = b2 & 0x0F;
    return '$prefix$digit1${digit2.toRadixString(16).toUpperCase()}${digit3.toRadixString(16).toUpperCase()}${digit4.toRadixString(16).toUpperCase()}';
  }

  Future<void> disconnect() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _netBindChannel.invokeMethod('unbind');
      } catch (_) {}
    }
    await _subscription?.cancel();
    _subscription = null;
    _socket?.destroy();
    _socket = null;
    _rxLen = 0;
    _rxOffset = 0;
  }

  void dispose() {
    disconnect();
    _messageStreamController.close();
  }
}

class HsfzMessage {
  final int sourceAddress;
  final int targetAddress;
  final int messageType;
  final Uint8List payload;

  HsfzMessage({
    required this.sourceAddress,
    required this.targetAddress,
    required this.messageType,
    required this.payload,
  });
}
