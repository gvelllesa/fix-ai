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

  bool get isConnected => _device != null && _device!.isConnected;

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
    try {
      // 1. Reset Adapter (AT Z) - allows up to 1500ms
      await sendAndAwaitPrompt('AT Z', timeout: const Duration(milliseconds: 1500));

      // 2. Turn off Echo (AT E0)
      final echoRsp = await sendAndAwaitPrompt('AT E0', timeout: const Duration(milliseconds: 800));
      if (echoRsp == null && !isConnected) return false;

      // 3. Linefeeds off (AT L0)
      await sendAndAwaitPrompt('AT L0', timeout: const Duration(milliseconds: 500));

      // 4. Spaces off for faster byte parsing (AT S0)
      await sendAndAwaitPrompt('AT S0', timeout: const Duration(milliseconds: 500));

      // 5. Automatic Protocol Negotiation (AT SP 0)
      final spRsp = await sendAndAwaitPrompt('AT SP 0', timeout: const Duration(milliseconds: 1000));
      return spRsp != null || isConnected;
    } catch (e) {
      debugPrint("[BluetoothStrategy] ELM327 Init Error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    await _rxSubscription?.cancel();
    _rxSubscription = null;

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
