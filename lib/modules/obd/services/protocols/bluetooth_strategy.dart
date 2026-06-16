import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class BluetoothStrategy {
  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;
  BluetoothCharacteristic? _rxCharacteristic;
  StreamSubscription? _rxSubscription;

  final StreamController<String> _dataStreamController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  bool get isConnected => _device != null && _device!.isConnected;

  /// Connects to a target Bluetooth device and initializes ELM327 protocol
  Future<bool> connect(BluetoothDevice targetDevice) async {
    try {
      _device = targetDevice;
      await _device!.connect(license: License.nonprofit);

      // Discover Services
      final services = await _device!.discoverServices();

      // Look for SPP (Serial Port Profile) RX/TX characteristics
      // Cheap ELM327/vLinker adapters use FFF0/FFF1/FFF2 or FFE0/FFE1
      for (var service in services) {
        for (var characteristic in service.characteristics) {
          final uuid = characteristic.uuid.toString().toUpperCase();
          if (uuid.contains('FFF1') || uuid.contains('FFE1') || characteristic.properties.notify) {
            _rxCharacteristic = characteristic;
          }
          if (uuid.contains('FFF2') || uuid.contains('FFE2') || characteristic.properties.write || characteristic.properties.writeWithoutResponse) {
            _txCharacteristic = characteristic;
          }
        }
      }

      if (_txCharacteristic == null || _rxCharacteristic == null) {
        // Fallback: Just grab the first notify and first write if specific UUIDs fail
        for (var service in services) {
          for (var c in service.characteristics) {
            if (c.properties.notify && _rxCharacteristic == null) _rxCharacteristic = c;
            if ((c.properties.write || c.properties.writeWithoutResponse) && _txCharacteristic == null) _txCharacteristic = c;
          }
        }
      }

      if (_txCharacteristic == null || _rxCharacteristic == null) {
        throw Exception("Could not find SPP RX/TX Characteristics on this device.");
      }

      // Start listening to RX
      await _rxCharacteristic!.setNotifyValue(true);
      _rxSubscription = _rxCharacteristic!.onValueReceived.listen((value) {
        final asciiString = ascii.decode(value, allowInvalid: true);
        _dataStreamController.add(asciiString);
      });

      // Execute Mandatory AT Initialization Sequence
      final initSuccess = await _initializeElm327();
      if (!initSuccess) {
        throw Exception("ELM327 Initialization Sequence Failed");
      }

      return true;
    } catch (e) {
      debugPrint("Bluetooth Connection Error: $e");
      await disconnect();
      return false;
    }
  }

  Future<void> send(String command) async {
    if (_txCharacteristic != null && isConnected) {
      // Append Carriage Return for ELM327
      final bytes = ascii.encode('$command\r');
      await _txCharacteristic!.write(bytes, withoutResponse: _txCharacteristic!.properties.writeWithoutResponse);
    } else {
      debugPrint("Warning: Tried to send command but not connected or missing TX characteristic.");
    }
  }

  Future<bool> _initializeElm327() async {
    try {
      // Reset Adapter
      await send('AT Z');
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Turn off Echo
      await send('AT E0');
      await Future.delayed(const Duration(milliseconds: 200));
      
      // Set Protocol to Auto
      await send('AT SP 0');
      await Future.delayed(const Duration(milliseconds: 200));

      return true;
    } catch (e) {
      debugPrint("ELM327 Init Error: $e");
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
  }

  void dispose() {
    disconnect();
    _dataStreamController.close();
  }
}
