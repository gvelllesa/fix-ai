import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Bluetooth Low Energy (BLE) OBD-II Transport Strategy
/// 
/// Supports high-speed telemetry on OBDLink CX, Vgate vLinker BM+/MC+,
/// Veepeak OBDCheck BLE, and generic ELM327/STN2120 adapters.
class BluetoothStrategy {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription? _rxSubscription;

  final StreamController<String> _dataStreamController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  final StringBuffer _rxAccumulator = StringBuffer();
  Completer<String>? _promptCompleter;

  /// Optional command runner override for unit testing ELM327 / BMW ISO-TP framing
  @visibleForTesting
  Future<String?> Function(String command, {Duration timeout})? commandRunnerOverride;

  int? _activeTargetEcu;
  bool _bmwIsoTpInitialized = false;
  bool get isBmwIsoTpInitialized => _bmwIsoTpInitialized;
  int? get activeTargetEcu => _activeTargetEcu;

  bool get isConnected =>
      commandRunnerOverride != null || (_device != null && _device!.isConnected);

  // Known Automotive BLE Service & Characteristic UUID signatures
  static const List<String> _knownServiceUuids = [
    'FFF0', // Vgate vLinker / Veepeak / Generic ELM327
    'FFE0', // CC2541 / HM-10 BLE Serial Module
    '18F0', // Vgate vLinker proprietary
    'E7810A71-73AE-499D-8C15-FAA9AEF0C3F2', // OBDLink CX
    '49535343-FE7D-4AE5-8FA9-9FAFD205E455', // Microchip Transparent UART (ISSC)
  ];

  static const List<String> _knownTxUuids = [
    'FFF2', 'FFE1', '2AB8', 'BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F', '49535343-8841-43F4-A8D4-ECBE34729BB3'
  ];

  static const List<String> _knownRxUuids = [
    'FFF1', 'FFE1', '2AB7', 'BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F', '49535343-1E4D-4BD9-BA61-23C647249616'
  ];

  /// Connects to a target BLE OBD adapter, requests maximum MTU (512 bytes),
  /// discovers UART characteristics, and initializes ELM327/STN command engine.
  Future<bool> connect(BluetoothDevice targetDevice) async {
    try {
      _device = targetDevice;
      await _device!.connect(license: License.nonprofit);

      // 1. Request 512-byte MTU immediately upon connection to maximize telemetry throughput
      try {
        await _device!.requestMtu(512);
        debugPrint('[BluetoothStrategy] Requested MTU 512 on ${_device!.remoteId}');
      } catch (e) {
        debugPrint('[BluetoothStrategy] MTU request notice: $e');
      }

      // 2. Discover Services and match known OBD-II profiles
      final services = await _device!.discoverServices();
      _matchCharacteristics(services);

      if (_txCharacteristic == null || _rxCharacteristic == null) {
        throw Exception("Could not find valid SPP/UART RX and TX characteristics on this BLE OBD adapter.");
      }

      // 3. Start listening to RX notifications
      await _rxCharacteristic!.setNotifyValue(true);
      _rxSubscription = _rxCharacteristic!.onValueReceived.listen((value) {
        final asciiString = ascii.decode(value, allowInvalid: true);
        _dataStreamController.add(asciiString);
        _rxAccumulator.write(asciiString);

        // Check if ELM327 '>' prompt has arrived
        if (_rxAccumulator.toString().contains('>')) {
          final completeResponse = _rxAccumulator.toString();
          _rxAccumulator.clear();
          if (_promptCompleter != null && !_promptCompleter!.isCompleted) {
            _promptCompleter!.complete(completeResponse);
          }
        }
      });

      // 4. Execute Robust AT Command Handshake
      final initSuccess = await _initializeElm327();
      if (!initSuccess) {
        throw Exception("ELM327 initialization handshake timed out or failed to return '>' prompt.");
      }

      debugPrint('[BluetoothStrategy] Successfully initialized ELM327 on ${_device!.remoteId}');
      return true;
    } catch (e) {
      debugPrint('[BluetoothStrategy] Bluetooth Connection Error: $e');
      await disconnect();
      return false;
    }
  }

  void _matchCharacteristics(List<BluetoothService> services) {
    for (final service in services) {
      final sUuid = service.uuid.toString().toUpperCase();
      final isKnownService = _knownServiceUuids.any((u) => sUuid.contains(u));

      for (final c in service.characteristics) {
        final cUuid = c.uuid.toString().toUpperCase();

        final isKnownTx = _knownTxUuids.any((u) => cUuid.contains(u));
        final isKnownRx = _knownRxUuids.any((u) => cUuid.contains(u));

        if (isKnownRx || (isKnownService && c.properties.notify)) {
          _rxCharacteristic = c;
        }
        if (isKnownTx || (isKnownService && (c.properties.write || c.properties.writeWithoutResponse))) {
          _txCharacteristic = c;
        }
      }
    }

    // Fallback if vendor UUIDs differ: first writeable and first notify characteristic
    if (_txCharacteristic == null || _rxCharacteristic == null) {
      for (final service in services) {
        for (final c in service.characteristics) {
          if (c.properties.notify && _rxCharacteristic == null) _rxCharacteristic = c;
          if ((c.properties.write || c.properties.writeWithoutResponse) && _txCharacteristic == null) {
            _txCharacteristic = c;
          }
        }
      }
    }
  }

  /// Sends raw command without waiting for response
  Future<void> send(String command) async {
    if (_txCharacteristic != null && isConnected) {
      final bytes = ascii.encode('$command\r');
      await _txCharacteristic!.write(
        bytes,
        withoutResponse: _txCharacteristic!.properties.writeWithoutResponse,
      );
    } else {
      debugPrint("[BluetoothStrategy] Warning: send called while disconnected or missing TX.");
    }
  }

  /// Sends an AT or OBD command and awaits the '>' prompt up to [timeout] ms with retry support
  Future<String?> sendAndAwaitPrompt(
    String command, {
    Duration timeout = const Duration(milliseconds: 1500),
    int retries = 2,
  }) async {
    if (commandRunnerOverride != null) {
      return await commandRunnerOverride!(command, timeout: timeout);
    }

    for (int attempt = 0; attempt <= retries; attempt++) {
      _rxAccumulator.clear();
      _promptCompleter = Completer<String>();

      await send(command);

      try {
        final result = await _promptCompleter!.future.timeout(timeout);
        return result;
      } on TimeoutException {
        debugPrint('[BluetoothStrategy] Command "$command" timed out (attempt ${attempt + 1}/${retries + 1})');
        if (attempt == retries) return null;
        await Future.delayed(const Duration(milliseconds: 150));
      }
    }
    return null;
  }

  Future<bool> _initializeElm327() async {
    return initializeBmwIsoTpCan();
  }

  /// Configures ELM327 / STN2120 / vLinker adapter for BMW ISO 15765-2 Extended CAN Addressing
  /// (EdiabasLib.EdElmInterface / BimmerLink / ProTool standard):
  /// - AT SP 6 (ISO 15765-4 CAN 11-bit ID, 500 kbaud)
  /// - AT H1 (Headers ON to distinguish CAN ID 6xx and Extended Address F1)
  /// - AT CAF1 / AT CFC1 (ISO-TP PCI formatting and Flow Control ON)
  /// - AT SH 6F1 (Tester Physical CAN ID 0x6F1)
  /// - AT FC SH 6F1 (Flow Control Header 0x6F1)
  Future<bool> initializeBmwIsoTpCan() async {
    try {
      await sendAndAwaitPrompt('AT Z', timeout: const Duration(milliseconds: 1500));
      final echoRsp = await sendAndAwaitPrompt('AT E0', timeout: const Duration(milliseconds: 800));
      if (echoRsp == null && !isConnected) return false;

      await sendAndAwaitPrompt('AT L0', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT S0', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT H1', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT SP 6', timeout: const Duration(milliseconds: 800));
      await sendAndAwaitPrompt('AT CAF1', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT CFC1', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT SH 6F1', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT FC SH 6F1', timeout: const Duration(milliseconds: 500));
      await sendAndAwaitPrompt('AT FC SM 1', timeout: const Duration(milliseconds: 500));

      _bmwIsoTpInitialized = true;
      _activeTargetEcu = null;
      return true;
    } catch (e) {
      debugPrint('[BluetoothStrategy] BMW ISO-TP CAN Init Error: $e');
      return false;
    }
  }

  /// Selects the target BMW ECU via CAN Extended Addressing (`AT CEA <ecuHex>`, `AT CRA 6<ecuHex>`).
  Future<bool> selectTargetEcu(int targetEcu) async {
    if (!_bmwIsoTpInitialized) {
      final ok = await initializeBmwIsoTpCan();
      if (!ok) return false;
    }
    final ecuByte = targetEcu & 0xFF;
    if (_activeTargetEcu == ecuByte) return true;

    final hex = ecuByte.toRadixString(16).toUpperCase().padLeft(2, '0');
    await sendAndAwaitPrompt('AT CEA $hex', timeout: const Duration(milliseconds: 400));

    if (ecuByte == 0xDF) {
      // Functional broadcast across all BMW ECUs
      await sendAndAwaitPrompt('AT CRA 6XX', timeout: const Duration(milliseconds: 400));
    } else {
      await sendAndAwaitPrompt('AT CRA 6$hex', timeout: const Duration(milliseconds: 400));
      await sendAndAwaitPrompt('AT FC SD ${hex}300000', timeout: const Duration(milliseconds: 400));
    }

    _activeTargetEcu = ecuByte;
    return true;
  }

  /// Sends a UDS request over BMW ISO-TP Extended CAN Addressing and reassembles
  /// Single-Frame (0L) or Multi-Frame (1L LL + 21..2F/20) UDS responses.
  Future<Uint8List?> sendUdsOverIsoTp(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(milliseconds: 1500),
    Duration p2Star = const Duration(seconds: 5),
    int maxPending = 10,
  }) async {
    if (udsPayload.isEmpty) return null;
    final selected = await selectTargetEcu(targetEcu);
    if (!selected) return null;

    final hexReq = udsPayload
        .map((b) => (b & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join('');

    final rawRsp = await sendAndAwaitPrompt(hexReq, timeout: timeout);
    if (rawRsp == null || rawRsp.isEmpty) return null;

    var parsed = parseIsoTpResponse(rawRsp, expectedEcu: targetEcu);

    // Handle UDS NRC 0x78 (ResponsePending) if returned as a separate prompt
    int pendingCount = 0;
    final sid = udsPayload[0] & 0xFF;
    while (parsed != null &&
        parsed.length >= 3 &&
        parsed[0] == 0x7F &&
        parsed[1] == sid &&
        parsed[2] == 0x78 &&
        pendingCount < maxPending) {
      pendingCount++;
      final followUp = await sendAndAwaitPrompt('', timeout: p2Star, retries: 0);
      if (followUp == null || followUp.isEmpty) break;
      final nextParsed = parseIsoTpResponse(followUp, expectedEcu: targetEcu);
      if (nextParsed == null) break;
      parsed = nextParsed;
    }

    return parsed;
  }

  /// Parses raw ELM327 ASCII output into a reassembled UDS payload.
  /// Supports:
  /// - BMW Extended CAN Header ON (`612F10362F190...` or `640F1101462F190...`)
  /// - Standard Header OFF (`0362F190...` or `101462F190...` / `014\n0:62F190...`)
  /// - Single Frame (`0x01`..`0x07`)
  /// - First Frame (`0x10`..`0x1F`) + Consecutive Frames (`0x20`..`0x2F`) with 0x2F->0x20 wrap
  /// - Automatic skipping of intermediate `7F <SID> 78` (ResponsePending) frames when final response is in the same stream
  static Uint8List? parseIsoTpResponse(String rawResponse, {int? expectedEcu}) {
    final cleanedLines = rawResponse
        .replaceAll('>', '')
        .split(RegExp(r'[\r\n]+'))
        .map((l) => l.trim().toUpperCase())
        .where((l) =>
            l.isNotEmpty &&
            !l.startsWith('SEARCHING') &&
            !l.startsWith('NO DATA') &&
            !l.startsWith('STOPPED') &&
            !l.startsWith('UNABLE') &&
            !l.startsWith('CAN ERROR') &&
            !l.startsWith('AT') &&
            l != 'OK' &&
            l != '?')
        .toList();

    if (cleanedLines.isEmpty) return null;

    // Handle ELM327 CAF1 colon format (e.g. "014" header line followed by "0: 62 F1 90 ...")
    final colonBytes = <int>[];
    int? declaredColonLen;
    for (final line in cleanedLines) {
      final compact = line.replaceAll(' ', '');
      if (RegExp(r'^[0-9A-F]{3}$').hasMatch(compact) && colonBytes.isEmpty) {
        declaredColonLen = int.parse(compact, radix: 16);
        continue;
      }
      final colonIdx = compact.indexOf(':');
      if (colonIdx == 1 && RegExp(r'^[0-9A-F]:[0-9A-F]+$').hasMatch(compact)) {
        final dataHex = compact.substring(2);
        colonBytes.addAll(_hexToBytes(dataHex));
      }
    }
    if (colonBytes.isNotEmpty) {
      if (declaredColonLen != null && declaredColonLen <= colonBytes.length) {
        return Uint8List.fromList(colonBytes.sublist(0, declaredColonLen));
      }
      return Uint8List.fromList(colonBytes);
    }

    // Parse raw CAN / ISO-TP frames line by line
    final completedMessages = <Uint8List>[];
    List<int>? multiFrameBuffer;
    int expectedMultiFrameLen = 0;

    final ecuHex = expectedEcu != null
        ? (expectedEcu & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0')
        : null;

    for (final line in cleanedLines) {
      var hex = line.replaceAll(' ', '');
      if (!RegExp(r'^[0-9A-F]+$').hasMatch(hex) || hex.length < 2) continue;

      // Strip 11-bit CAN ID (6xx) + Extended Address (F1 or F4) if headers (AT H1) are present
      if (hex.startsWith('6') && hex.length >= 7) {
        final canEcu = hex.substring(1, 3);
        final extAddr = hex.substring(3, 5);
        if ((extAddr == 'F1' || extAddr == 'F4') && (ecuHex == null || canEcu == ecuHex)) {
          hex = hex.substring(5);
        }
      } else if ((hex.startsWith('F1') || hex.startsWith('F4')) && hex.length >= 4) {
        // Extended address byte only
        hex = hex.substring(2);
      }

      final frameBytes = _hexToBytes(hex);
      if (frameBytes.isEmpty) continue;

      final pciType = (frameBytes[0] >> 4) & 0x0F;

      if (pciType == 0x0) {
        // Single Frame: [0L, d1, d2, ...]
        final sfLen = frameBytes[0] & 0x0F;
        if (sfLen > 0 && frameBytes.length >= 1 + sfLen) {
          final msg = Uint8List.fromList(frameBytes.sublist(1, 1 + sfLen));
          completedMessages.add(msg);
        } else if (sfLen == 0 && frameBytes.length >= 2) {
          // Unframed direct UDS response (when CAF1 strips PCI on single frame)
          completedMessages.add(Uint8List.fromList(frameBytes));
        }
      } else if (pciType == 0x1 && frameBytes.length >= 3) {
        // First Frame: [1L, LL, d1, d2, ...]
        expectedMultiFrameLen = ((frameBytes[0] & 0x0F) << 8) | frameBytes[1];
        multiFrameBuffer = List<int>.from(frameBytes.sublist(2));
        if (multiFrameBuffer.length >= expectedMultiFrameLen) {
          completedMessages.add(
            Uint8List.fromList(multiFrameBuffer.sublist(0, expectedMultiFrameLen)),
          );
          multiFrameBuffer = null;
        }
      } else if (pciType == 0x2 && multiFrameBuffer != null && frameBytes.length >= 2) {
        // Consecutive Frame: [2N, d1, d2, ...]
        multiFrameBuffer.addAll(frameBytes.sublist(1));
        if (multiFrameBuffer.length >= expectedMultiFrameLen) {
          completedMessages.add(
            Uint8List.fromList(multiFrameBuffer.sublist(0, expectedMultiFrameLen)),
          );
          multiFrameBuffer = null;
        }
      } else {
        // Direct UDS bytes (when adapter returns unframed positive/negative response e.g. 62F190...)
        completedMessages.add(Uint8List.fromList(frameBytes));
      }
    }

    if (multiFrameBuffer != null && multiFrameBuffer.isNotEmpty) {
      final len = expectedMultiFrameLen > 0 && expectedMultiFrameLen <= multiFrameBuffer.length
          ? expectedMultiFrameLen
          : multiFrameBuffer.length;
      completedMessages.add(Uint8List.fromList(multiFrameBuffer.sublist(0, len)));
    }

    if (completedMessages.isEmpty) return null;

    // Filter out intermediate NRC 0x78 (ResponsePending) if a subsequent message exists
    for (int i = 0; i < completedMessages.length; i++) {
      final msg = completedMessages[i];
      final isPending = msg.length >= 3 && msg[0] == 0x7F && msg[2] == 0x78;
      if (isPending && i < completedMessages.length - 1) {
        continue;
      }
      return msg;
    }

    return completedMessages.last;
  }

  static List<int> _hexToBytes(String hex) {
    final clean = hex.length.isOdd ? '0$hex' : hex;
    final out = <int>[];
    for (int i = 0; i + 2 <= clean.length; i += 2) {
      final byte = int.tryParse(clean.substring(i, i + 2), radix: 16);
      if (byte != null) out.add(byte);
    }
    return out;
  }

  Future<void> disconnect() async {
    await _rxSubscription?.cancel();
    _rxSubscription = null;
    _bmwIsoTpInitialized = false;
    _activeTargetEcu = null;

    if (_device != null) {
      await _device!.disconnect();
      _device = null;
    }

    _txCharacteristic = null;
    _rxCharacteristic = null;
    _rxAccumulator.clear();
    if (_promptCompleter != null && !_promptCompleter!.isCompleted) {
      _promptCompleter!.completeError(Exception('Disconnected'));
    }
    _promptCompleter = null;
  }

  void dispose() {
    disconnect();
    _dataStreamController.close();
  }
}
