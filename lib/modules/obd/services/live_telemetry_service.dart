import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'bmw_sensor_registry.dart';
import 'connection_manager.dart';
import 'datalog_writer.dart';

enum TelemetryPriority {
  high, // RPM, Boost, Timing, Knock (20-50ms)
  medium, // STFT, AFR, Throttle (100-200ms)
  low, // Coolant, Oil, IAT (500-1000ms)
}

/// High-Frequency Live Telemetry Service for BMW Engine DME/DDE.
///
/// Features:
/// - Sequential, priority-based polling loop (P3.1) preventing packet collisions.
/// - Respects [ConnectionManager.instance.isExclusiveActive] to pause during flashing/coding.
/// - Individual [ValueNotifier<double>] per sensor for 60/120 FPS Cockpit HUD rendering (P3.2).
/// - Buffered CSV datalogging using [DatalogWriter] (P3.3).
class LiveTelemetryService {
  final EnetHsfzProtocol protocol;

  Timer? _schedulerTimer;
  bool _isPolling = false;
  bool _isQueryInFlight = false;
  bool get isPolling => _isPolling;

  // Active sensor values cache: { 'engine_rpm': 850.0, 'battery_voltage': 14.2, ... }
  final Map<String, double> _currentReadings = {};
  Map<String, double> get currentReadings => Map.unmodifiable(_currentReadings);

  // Per-sensor ValueNotifiers for granular RepaintBoundary UI updates
  final Map<String, ValueNotifier<double>> _sensorNotifiers = {};

  final StreamController<Map<String, double>> _readingsStreamController =
      StreamController<Map<String, double>>.broadcast();
  Stream<Map<String, double>> get readingsStream => _readingsStreamController.stream;

  // Timestamps of last queries for scheduling
  final Map<String, int> _lastPollTimestamp = {};

  // Buffered DatalogWriter
  DatalogWriter? _datalogWriter;
  String? _currentLogPath;
  String? get currentLogPath => _currentLogPath;
  bool get isLogging => _datalogWriter?.isOpen ?? false;

  // Enabled sensors
  final List<BmwSensorDefinition> _activeSensors = List.from(BmwSensorRegistry.allSensors);

  // Scheduling intervals in milliseconds
  static const int kHighPriorityIntervalMs = 40;
  static const int kMediumPriorityIntervalMs = 150;
  static const int kLowPriorityIntervalMs = 600;

  LiveTelemetryService({required this.protocol});

  /// Classifies a sensor ID into priority tier
  static TelemetryPriority priorityForSensor(String sensorId) {
    switch (sensorId) {
      case 'engine_rpm':
      case 'boost_pressure':
      case 'manifold_boost_pressure':
      case 'target_boost':
      case 'ignition_timing_cyl1':
      case 'knock_detected':
      case 'accelerator_pedal_position':
        return TelemetryPriority.high;
      case 'wideband_lambda_bank1':
      case 'short_term_fuel_trim_b1':
      case 'long_term_fuel_trim_b1':
      case 'throttle_valve_angle':
      case 'rail_pressure':
      case 'fuel_low_pressure_sensor':
      case 'vehicle_speed':
      case 'current_gear':
        return TelemetryPriority.medium;
      default:
        return TelemetryPriority.low;
    }
  }

  static int intervalForPriority(TelemetryPriority priority) {
    switch (priority) {
      case TelemetryPriority.high:
        return kHighPriorityIntervalMs;
      case TelemetryPriority.medium:
        return kMediumPriorityIntervalMs;
      case TelemetryPriority.low:
        return kLowPriorityIntervalMs;
    }
  }

  /// Returns dedicated ValueNotifier for a sensor for 60/120 FPS gauge updates
  ValueNotifier<double> getSensorNotifier(String sensorId, {double initialValue = 0.0}) {
    return _sensorNotifiers.putIfAbsent(
      sensorId,
      () => ValueNotifier<double>(_currentReadings[sensorId] ?? initialValue),
    );
  }

  void enableSensor(String sensorId, bool enable) {
    final sensor = BmwSensorRegistry.findById(sensorId);
    if (sensor == null) return;
    if (enable && !_activeSensors.contains(sensor)) {
      _activeSensors.add(sensor);
    } else if (!enable) {
      _activeSensors.remove(sensor);
    }
  }

  /// Starts the sequential priority telemetry scheduler loop
  void startPolling({Duration tick = const Duration(milliseconds: 20)}) {
    if (_isPolling) return;
    _isPolling = true;

    _schedulerTimer = Timer.periodic(tick, (_) async {
      await _executeSchedulerTick();
    });
  }

  /// Executes a single scheduler tick
  Future<void> _executeSchedulerTick() async {
    if (!_isPolling || _isQueryInFlight) return;
    if (!protocol.isConnected || _activeSensors.isEmpty) return;

    // Automotive Safety Rule: Pause telemetry when exclusive mutex is active (flashing/coding)
    if (ConnectionManager.instance.isExclusiveActive) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // Collect all due sensors sorted by priority
    final dueSensors = <BmwSensorDefinition>[];
    for (final sensor in _activeSensors) {
      final priority = priorityForSensor(sensor.id);
      final interval = intervalForPriority(priority);
      final lastPoll = _lastPollTimestamp[sensor.id] ?? 0;
      if (now - lastPoll >= interval) {
        dueSensors.add(sensor);
      }
    }

    if (dueSensors.isEmpty) return;

    // Sort: high priority first, then medium, then low
    dueSensors.sort((a, b) {
      final pa = priorityForSensor(a.id).index;
      final pb = priorityForSensor(b.id).index;
      return pa.compareTo(pb);
    });

    _isQueryInFlight = true;
    try {
      // Execute due sensors sequentially to prevent bus packet collisions
      for (final sensor in dueSensors) {
        if (!_isPolling || !protocol.isConnected || ConnectionManager.instance.isExclusiveActive) {
          break;
        }

        await _pollSensor(sensor);
        _lastPollTimestamp[sensor.id] = DateTime.now().millisecondsSinceEpoch;
      }
    } finally {
      _isQueryInFlight = false;
    }
  }

  /// Queries a single sensor over UDS 0x22 ReadDataByIdentifier
  Future<void> _pollSensor(BmwSensorDefinition sensor) async {
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

      final response = await protocol.sendUdsAndAwait(
        sensor.ecu,
        reqPayload,
        timeout: const Duration(milliseconds: 150),
      );

      if (response != null && response.length >= headerLen + sensor.size) {
        final dataBytes = response.sublist(headerLen, headerLen + sensor.size);
        int raw = 0;
        for (final b in dataBytes) {
          raw = (raw << 8) | b;
        }

        final physicalValue = sensor.convertRaw(raw);
        _currentReadings[sensor.id] = physicalValue;

        // Granular notifier update for RepaintBoundary
        final notifier = _sensorNotifiers[sensor.id];
        if (notifier != null) {
          notifier.value = physicalValue;
        }

        // Broadcast to stream
        _readingsStreamController.add(Map.from(_currentReadings));

        // Write to buffered CSV datalog
        if (_datalogWriter != null && _datalogWriter!.isOpen) {
          _recordTelemetryRow();
        }
      }
    } catch (e) {
      debugPrint('[LiveTelemetry] Poll error on ${sensor.id}: $e');
    }
  }

  void _recordTelemetryRow() {
    if (_datalogWriter == null || !_datalogWriter!.isOpen) return;

    final row = DatalogRow(
      timestampMs: DateTime.now().millisecondsSinceEpoch,
      rpm: _currentReadings['engine_rpm'] ?? 0.0,
      boostPsi: _currentReadings['manifold_boost_pressure'] ?? _currentReadings['boost_pressure'] ?? 0.0,
      targetBoostPsi: _currentReadings['target_boost'] ?? 0.0,
      timingCyl1: _currentReadings['ignition_timing_cyl1'] ?? 0.0,
      knockFlag: (_currentReadings['knock_detected'] ?? 0.0) >= 0.5,
      lambdaBank1: _currentReadings['wideband_lambda_bank1'] ?? 1.0,
      stftPct: _currentReadings['short_term_fuel_trim_b1'] ?? 0.0,
      iatC: _currentReadings['intake_air_temperature'] ?? 0.0,
      coolantC: _currentReadings['engine_coolant_temperature'] ?? 0.0,
    );
    _datalogWriter!.addRow(row);
  }

  void stopPolling() {
    _isPolling = false;
    _schedulerTimer?.cancel();
    _schedulerTimer = null;
    _isQueryInFlight = false;
  }

  /// Starts buffered CSV recording of live telemetry
  Future<String?> startLogging() async {
    if (isLogging) return _currentLogPath;

    try {
      final dir = await getApplicationDocumentsDirectory();
      final now = DateTime.now().toIso8601String().replaceAll(':', '-').replaceAll('.', '-');
      final file = File('${dir.path}/bmw_telemetry_$now.csv');

      _datalogWriter = DatalogWriter(
        file,
        bufferThreshold: 100,
        flushInterval: const Duration(seconds: 1),
      );
      await _datalogWriter!.open();

      _currentLogPath = file.path;
      debugPrint('[LiveTelemetry] Buffered CSV logging started at: $_currentLogPath');
      return _currentLogPath;
    } catch (e) {
      debugPrint('[LiveTelemetry] Failed to start logging: $e');
      return null;
    }
  }

  Future<void> stopLogging() async {
    if (_datalogWriter == null) return;
    final writer = _datalogWriter;
    _datalogWriter = null;
    await writer?.close();
    debugPrint('[LiveTelemetry] Logging stopped. CSV file finalized: $_currentLogPath');
  }

  void dispose() {
    stopPolling();
    stopLogging();
    _readingsStreamController.close();
    for (final notifier in _sensorNotifiers.values) {
      notifier.dispose();
    }
    _sensorNotifiers.clear();
  }
}
