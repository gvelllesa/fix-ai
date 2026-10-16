import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'bmw_sensor_registry.dart';

class LiveTelemetryService {
  final EnetHsfzProtocol protocol;
  Timer? _pollingTimer;
  bool _isPolling = false;
  bool get isPolling => _isPolling;

  // Active sensor values cache: { 'engine_rpm': 850.0, 'battery_voltage': 14.2, ... }
  final Map<String, double> _currentReadings = {};
  Map<String, double> get currentReadings => Map.unmodifiable(_currentReadings);

  final StreamController<Map<String, double>> _readingsStreamController = StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get readingsStream => _readingsStreamController.stream;

  // Logging
  bool _isLogging = false;
  bool get isLogging => _isLogging;
  IOSink? _logSink;
  String? _currentLogPath;
  String? get currentLogPath => _currentLogPath;

  // List of enabled sensors for polling cycle
  final List<BmwSensorDefinition> _activeSensors = List.from(BmwSensorRegistry.allSensors);
  int _pollIndex = 0;

  LiveTelemetryService({required this.protocol});

  void enableSensor(String sensorId, bool enable) {
    final sensor = BmwSensorRegistry.findById(sensorId);
    if (sensor == null) return;
    if (enable && !_activeSensors.contains(sensor)) {
      _activeSensors.add(sensor);
    } else if (!enable) {
      _activeSensors.remove(sensor);
    }
  }

  /// Starts the high-speed sensor query cycle (sub-90ms round-trip)
  void startPolling({Duration interval = const Duration(milliseconds: 85)}) {
    if (_isPolling) return;
    _isPolling = true;

    _pollingTimer = Timer.periodic(interval, (_) async {
      if (!protocol.isConnected || _activeSensors.isEmpty) return;

      final sensor = _activeSensors[_pollIndex % _activeSensors.length];
      _pollIndex++;

      try {
        final List<int> reqPayload;
        final int headerLen;
        if (sensor.did > 0xFFFF) {
          reqPayload = [
            0x22,
            (sensor.did >> 24) & 0xFF,
            (sensor.did >> 16) & 0xFF,
            (sensor.did >> 8) & 0xFF,
            sensor.did & 0xFF,
          ];
          headerLen = 5;
        } else {
          reqPayload = [
            0x22,
            (sensor.did >> 8) & 0xFF,
            sensor.did & 0xFF,
          ];
          headerLen = 3;
        }

        // UDS 0x22 ReadDataByIdentifier
        final response = await protocol.sendUdsAndAwait(
          sensor.ecu,
          reqPayload,
          timeout: const Duration(milliseconds: 350),
        );

        if (response != null && response.length >= headerLen + sensor.size) {
          // Response format: [0x62, DID bytes..., byte0, byte1...]
          final dataBytes = response.sublist(headerLen, headerLen + sensor.size);
          int raw = 0;
          for (final b in dataBytes) {
            raw = (raw << 8) | b;
          }

          final physicalValue = sensor.convertRaw(raw);
          _currentReadings[sensor.id] = physicalValue;
          _readingsStreamController.add(Map.from(_currentReadings));

          if (_isLogging && _logSink != null) {
            _writeLogEntry(sensor.id, physicalValue);
          }
        }
      } catch (e) {
        debugPrint('[LiveTelemetry] Poll error on ${sensor.id}: $e');
      }
    });
  }

  void stopPolling() {
    _isPolling = false;
    _pollingTimer?.cancel();
    _pollingTimer = null;
  }

  /// Starts recording live sensor logs to a JSONL file
  Future<String?> startLogging() async {
    if (_isLogging) return _currentLogPath;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final file = File('${dir.path}/bmw_telemetry_$now.jsonl');

      _logSink = file.openWrite(mode: FileMode.writeOnlyAppend);
      // Write Header
      final header = {
        'type': 'header',
        'timestamp': DateTime.now().toIso8601String(),
        'sensors': _activeSensors.map((s) => {'id': s.id, 'label': s.label, 'unit': s.unit}).toList(),
      };
      _logSink!.writeln(jsonEncode(header));
      await _logSink!.flush();

      _currentLogPath = file.path;
      _isLogging = true;
      debugPrint('[LiveTelemetry] Logging started at: $_currentLogPath');
      return _currentLogPath;
    } catch (e) {
      debugPrint('[LiveTelemetry] Failed to start logging: $e');
      return null;
    }
  }

  Future<void> stopLogging() async {
    if (!_isLogging) return;
    _isLogging = false;
    await _logSink?.flush();
    await _logSink?.close();
    _logSink = null;
    debugPrint('[LiveTelemetry] Logging stopped. File saved: $_currentLogPath');
  }

  void _writeLogEntry(String sensorId, double value) {
    if (_logSink == null) return;
    final row = {
      'ts': DateTime.now().millisecondsSinceEpoch,
      'sensor': sensorId,
      'val': double.parse(value.toStringAsFixed(2)),
    };
    _logSink!.writeln(jsonEncode(row));
  }

  void dispose() {
    stopPolling();
    stopLogging();
    _readingsStreamController.close();
  }
}
