import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class WifiStrategy {
  Socket? _socket;
  StreamSubscription? _socketSubscription;

  final StreamController<String> _dataStreamController = StreamController<String>.broadcast();
  Stream<String> get dataStream => _dataStreamController.stream;

  bool get isConnected => _socket != null;

  /// Connects to Wi-Fi ELM327 clone using standard universal IP and Port
  Future<bool> connect({String ip = '192.168.0.10', int port = 35000}) async {
    try {
      // Connect directly to the Socket
      _socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));

      // Listen to the socket stream
      _socketSubscription = _socket!.listen(
        (List<int> data) {
          final asciiString = ascii.decode(data, allowInvalid: true);
          _dataStreamController.add(asciiString);
        },
        onError: (error) {
          debugPrint("Wi-Fi Socket Error: $error");
          disconnect();
        },
        onDone: () {
          debugPrint("Wi-Fi Socket Done/Closed");
          disconnect();
        },
      );

      // Execute Mandatory AT Initialization Sequence
      final initSuccess = await _initializeElm327();
      if (!initSuccess) {
        throw Exception("ELM327 Wi-Fi Initialization Sequence Failed");
      }

      return true;
    } catch (e) {
      debugPrint("Wi-Fi Connection Error: $e");
      await disconnect();
      return false;
    }
  }

  Future<void> send(String command) async {
    if (_socket != null) {
      // Append Carriage Return for ELM327
      _socket!.write('$command\r');
      await _socket!.flush();
    } else {
      debugPrint("Warning: Tried to send command over Wi-Fi but socket is null.");
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
      debugPrint("ELM327 Wi-Fi Init Error: $e");
      return false;
    }
  }

  Future<void> disconnect() async {
    await _socketSubscription?.cancel();
    _socketSubscription = null;

    if (_socket != null) {
      _socket!.destroy();
      _socket = null;
    }
  }

  void dispose() {
    disconnect();
    _dataStreamController.close();
  }
}
