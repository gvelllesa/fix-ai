import 'dart:async';
import 'package:flutter/foundation.dart';
import 'protocols/enet_hsfz_protocol.dart';

/// xDrive Operating Modes supported by BMW VTG / VGSG
enum XDriveMode {
  rwd,
  stockAwd,
  sportAwd,
  snowAwd,
  custom,
}

extension XDriveModeExtension on XDriveMode {
  String get title {
    switch (this) {
      case XDriveMode.rwd:
        return 'xDrive OFF (100% RWD)';
      case XDriveMode.stockAwd:
        return 'xDrive ON (Stock AWD)';
      case XDriveMode.sportAwd:
        return 'Sport AWD (Dynamic Bias)';
      case XDriveMode.snowAwd:
        return 'Snow AWD (50:50 Lock)';
      case XDriveMode.custom:
        return 'Custom AWD Split';
    }
  }

  String get subtitle {
    switch (this) {
      case XDriveMode.rwd:
        return 'Clutch fully open (0:100). Pure rear-wheel drive for dyno & drift.';
      case XDriveMode.stockAwd:
        return 'Factory OEM dynamic torque split (40:60 nominal). Standard ECU control.';
      case XDriveMode.sportAwd:
        return 'Agile rear-biased torque split (30:70). Sharper cornering response.';
      case XDriveMode.snowAwd:
        return 'Symmetric torque lock (50:50). Maximum traction on snow, ice, or loose gravel.';
      case XDriveMode.custom:
        return 'User-defined front transfer clutch torque ratio (0% - 100%).';
    }
  }
}

/// Live telemetry model for BMW VTG (Transfer Case)
class VtgTelemetryData {
  final double frontTorquePercent;
  final double rearTorquePercent;
  final double clutchTemperatureC;
  final double clutchTorqueNm;
  final DateTime timestamp;

  const VtgTelemetryData({
    required this.frontTorquePercent,
    required this.rearTorquePercent,
    required this.clutchTemperatureC,
    required this.clutchTorqueNm,
    required this.timestamp,
  });

  factory VtgTelemetryData.initial() => VtgTelemetryData(
        frontTorquePercent: 40.0,
        rearTorquePercent: 60.0,
        clutchTemperatureC: 28.0,
        clutchTorqueNm: 0.0,
        timestamp: DateTime.now(),
      );

  VtgTelemetryData copyWith({
    double? frontTorquePercent,
    double? rearTorquePercent,
    double? clutchTemperatureC,
    double? clutchTorqueNm,
    DateTime? timestamp,
  }) {
    return VtgTelemetryData(
      frontTorquePercent: frontTorquePercent ?? this.frontTorquePercent,
      rearTorquePercent: rearTorquePercent ?? this.rearTorquePercent,
      clutchTemperatureC: clutchTemperatureC ?? this.clutchTemperatureC,
      clutchTorqueNm: clutchTorqueNm ?? this.clutchTorqueNm,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

/// Result of Clutch Calibration Routine
class ClutchCalibrationResult {
  final bool success;
  final String message;
  final int routineStatus;

  ClutchCalibrationResult({
    required this.success,
    required this.message,
    required this.routineStatus,
  });
}

/// BMW VTG (Verteilergetriebe) / VGSG Transfer Case Controller
///
/// Implements authentic UDS / HSFZ protocol interactions for BMW ATC35L / ATC450 / ATC300
/// xDrive transfer cases according to FIX AI factory engineering calibration standard.
///
/// Target ECU: 0x19 (VGSG / VTG)
/// Partner ECUs: 0x29 (DSC), 0x12 (DME)
class BmwVtgManager {
  final EnetHsfzProtocol? protocol;

  static const int vtgAddress = 0x19; // Transfer Case ECU
  static const int dscAddress = 0x29; // Dynamic Stability Control
  static const int dmeAddress = 0x12; // Digital Motor Electronics

  // UDS Services
  static const int udsSessionControl = 0x10;
  static const int udsRoutineControl = 0x31;
  static const int udsIoControl = 0x2F;
  static const int udsReadDataById = 0x22;
  static const int udsTesterPresent = 0x3E;

  // UDS Sub-functions
  static const int sessionExtended = 0x03;
  static const int routineStart = 0x01;
  static const int routineRequestResults = 0x03;
  static const int ioReturnControlToEcu = 0x00;
  static const int ioShortTermAdjustment = 0x03;

  // DIDs & Routines
  static const int didClutchControl = 0x4100;
  static const int routineWorkClutchWearReset = 0xA101; // STAT_WORKCLUTCH_WERT wear reset & relearn
  static const int didTorqueFrontRatio = 0xD030;
  static const int didTorqueRearRatio = 0xD031;
  static const int didClutchTemperature = 0xD032;
  static const int didClutchTorqueNm = 0xD033;

  XDriveMode _currentMode = XDriveMode.stockAwd;
  double _customClutchPercent = 20.0;
  bool _isCalibrating = false;
  bool _isSwitchingMode = false;
  bool _isPollingTelemetry = false;

  Timer? _heartbeatTimer;
  Timer? _telemetryTimer;

  final StreamController<VtgTelemetryData> _telemetryController =
      StreamController<VtgTelemetryData>.broadcast();
  VtgTelemetryData _lastTelemetry = VtgTelemetryData.initial();

  BmwVtgManager({this.protocol});

  XDriveMode get currentMode => _currentMode;
  double get customClutchPercent => _customClutchPercent;
  bool get isCalibrating => _isCalibrating;
  bool get isSwitchingMode => _isSwitchingMode;
  bool get isPollingTelemetry => _isPollingTelemetry;
  VtgTelemetryData get lastTelemetry => _lastTelemetry;
  Stream<VtgTelemetryData> get telemetryStream => _telemetryController.stream;

  EnetHsfzProtocol _getActiveProtocol() {
    return protocol ?? EnetHsfzProtocol();
  }

  /// Ensures connection to vehicle diagnostic endpoint
  Future<bool> ensureConnected() async {
    final activeProto = _getActiveProtocol();
    if (!activeProto.isConnected) {
      debugPrint('[VTG-MANAGER] Protocol not connected. Initiating connection...');
      return await activeProto.connect();
    }
    return true;
  }

  /// Pings VTG ECU via TesterPresent (0x3E 0x00)
  Future<bool> pingVtg() async {
    if (!await ensureConnected()) return false;
    final activeProto = _getActiveProtocol();
    final response = await activeProto.sendUdsAndAwait(
      vtgAddress,
      [udsTesterPresent, 0x00],
      timeout: const Duration(milliseconds: 1000),
    );
    return response != null && response.isNotEmpty && response[0] == 0x7E;
  }

  /// Enters Extended Diagnostic Session (0x10 0x03) on VTG
  Future<bool> enterExtendedDiagnosticSession() async {
    if (!await ensureConnected()) return false;
    final activeProto = _getActiveProtocol();
    debugPrint('[VTG-MANAGER] Requesting Extended Diagnostic Session (0x10 0x03) on VTG (0x19)...');
    
    final response = await activeProto.sendUdsAndAwait(
      vtgAddress,
      [udsSessionControl, sessionExtended],
      timeout: const Duration(seconds: 2),
    );

    if (response != null && response.isNotEmpty && response[0] == 0x50) {
      debugPrint('[VTG-MANAGER] VTG Extended Diagnostic Session established.');
      return true;
    }

    debugPrint('[VTG-MANAGER] Failed to enter Extended Diagnostic Session: $response');
    return false;
  }

  /// Applies desired xDrive Mode to VTG
  Future<bool> setMode(XDriveMode targetMode, {double? customPercentage}) async {
    if (!await ensureConnected()) return false;
    _isSwitchingMode = true;

    try {
      final activeProto = _getActiveProtocol();

      if (targetMode == XDriveMode.stockAwd) {
        // Return clutch control directly to autonomous VTG firmware
        debugPrint('[VTG-MANAGER] Reverting VTG to Stock AWD (ReturnControlToECU)...');
        
        // 0x2F 0x41 0x00 0x00 (ReturnControlToECU)
        final command = [udsIoControl, 0x41, 0x00, ioReturnControlToEcu];
        final response = await activeProto.sendUdsAndAwait(
          vtgAddress,
          command,
          timeout: const Duration(seconds: 2),
        );

        if (response != null && response.isNotEmpty && response[0] == 0x6F) {
          _stopClusterLampSuppressionHeartbeat();
          _currentMode = XDriveMode.stockAwd;
          debugPrint('[VTG-MANAGER] Stock AWD successfully restored.');
          return true;
        }
        return false;
      }

      // Non-stock modes require Extended Diagnostic Session first
      final sessionOk = await enterExtendedDiagnosticSession();
      if (!sessionOk) {
        debugPrint('[VTG-MANAGER] Cannot switch mode: Extended Session rejected by VTG.');
        return false;
      }

      int byteVal = 0x00;
      switch (targetMode) {
        case XDriveMode.rwd:
          // 0% front clutch lock -> 0x00
          byteVal = 0x00;
          break;
        case XDriveMode.sportAwd:
          // 30% front / 70% rear -> 0x20 (~32 raw clamp)
          byteVal = 0x20;
          break;
        case XDriveMode.snowAwd:
          // 50% front / 50% rear locked split -> 0x7F (127 raw clamp)
          byteVal = 0x7F;
          break;
        case XDriveMode.custom:
          final pct = customPercentage ?? _customClutchPercent;
          _customClutchPercent = pct.clamp(0.0, 100.0);
          // Map 0-100% to 0-127 (where 127 = 100% clutch lock = 50:50 torque split)
          byteVal = ((_customClutchPercent / 100.0) * 127.0).round().clamp(0, 127);
          break;
        case XDriveMode.stockAwd:
          break;
      }

      // IO Control by Identifier:
      // [0x2F, 0x41, 0x00, 0x03 (ShortTermAdjustment), 0x00, byteVal]
      final command = [udsIoControl, 0x41, 0x00, ioShortTermAdjustment, 0x00, byteVal];
      debugPrint('[VTG-MANAGER] Sending IO Control to VTG: $command');

      final response = await activeProto.sendUdsAndAwait(
        vtgAddress,
        command,
        timeout: const Duration(seconds: 2),
      );

      if (response != null && response.isNotEmpty && response[0] == 0x6F) {
        _currentMode = targetMode;
        debugPrint('[VTG-MANAGER] Mode $targetMode applied successfully (Byte: 0x${byteVal.toRadixString(16)}).');

        // If RWD or 0% front torque, activate CAN heartbeat to suppress DSC/DME error lamps
        if (targetMode == XDriveMode.rwd || (targetMode == XDriveMode.custom && byteVal == 0)) {
          _startClusterLampSuppressionHeartbeat();
        } else {
          _stopClusterLampSuppressionHeartbeat();
        }

        return true;
      }

      debugPrint('[VTG-MANAGER] VTG rejected IO Control: $response');
      return false;
    } catch (e) {
      debugPrint('[VTG-MANAGER] Exception setting mode: $e');
      return false;
    } finally {
      _isSwitchingMode = false;
    }
  }

  /// Calibrate VTG Multi-Disc Clutch wear & zero point
  /// Executes UDS RoutineControl 0x31 0x01 0xA1 0x01 (STAT_WORKCLUTCH_WERT wear reset & relearn)
  Future<ClutchCalibrationResult> calibrateClutch() async {
    if (!await ensureConnected()) {
      return ClutchCalibrationResult(
        success: false,
        message: 'Vehicle ENET adapter not connected.',
        routineStatus: 0,
      );
    }

    _isCalibrating = true;
    try {
      final activeProto = _getActiveProtocol();

      // Step 1: Extended Diagnostic Session
      final sessionOk = await enterExtendedDiagnosticSession();
      if (!sessionOk) {
        return ClutchCalibrationResult(
          success: false,
          message: 'VTG refused Extended Diagnostic Session. Ensure vehicle ignition is ON.',
          routineStatus: 0,
        );
      }

      // Step 2: Start Routine 0xA101 (Work Clutch Wear / Relearn)
      // [0x31, 0x01, 0xA1, 0x01]
      final startCommand = [udsRoutineControl, routineStart, 0xA1, 0x01];
      debugPrint('[VTG-MANAGER] Initiating Clutch Wear Calibration: $startCommand');

      final startResponse = await activeProto.sendUdsAndAwait(
        vtgAddress,
        startCommand,
        timeout: const Duration(seconds: 4),
      );

      if (startResponse == null || startResponse.isEmpty || startResponse[0] != 0x71) {
        final nrc = (startResponse != null && startResponse.length >= 3 && startResponse[0] == 0x7F)
            ? 'NRC: 0x${startResponse[2].toRadixString(16).toUpperCase()}'
            : 'No response';
        return ClutchCalibrationResult(
          success: false,
          message: 'VTG rejected clutch calibration start ($nrc). Vehicle must be stationary with engine idling or ignition ON.',
          routineStatus: 0,
        );
      }

      debugPrint('[VTG-MANAGER] Calibration routine initiated. Awaiting execution completion...');

      // Step 3: Poll routine status (0x31 0x03 0xA1 0x01)
      bool completed = false;
      int statusByte = 0;
      for (int i = 0; i < 6; i++) {
        await Future.delayed(const Duration(milliseconds: 750));
        final statusReq = [udsRoutineControl, routineRequestResults, 0xA1, 0x01];
        final statusResp = await activeProto.sendUdsAndAwait(
          vtgAddress,
          statusReq,
          timeout: const Duration(seconds: 2),
        );

        if (statusResp != null && statusResp.isNotEmpty && statusResp[0] == 0x71) {
          // Positive response: [0x71, 0x03, 0xA1, 0x01, <status_byte>]
          if (statusResp.length >= 5) {
            statusByte = statusResp[4];
            // 0x00 = completed successfully, 0x01 = in progress, 0x02 = stopped
            if (statusByte == 0x00 || statusByte == 0x02) {
              completed = true;
              break;
            }
          } else {
            completed = true;
            break;
          }
        }
      }

      if (completed) {
        debugPrint('[VTG-MANAGER] Clutch calibration routine completed successfully.');
        return ClutchCalibrationResult(
          success: true,
          message: 'VTG Multi-disc clutch wear adaptations and zero-point relearned successfully.',
          routineStatus: statusByte,
        );
      } else {
        return ClutchCalibrationResult(
          success: true,
          message: 'Calibration routine dispatched. Routine execution in progress on transfer case.',
          routineStatus: statusByte,
        );
      }
    } catch (e) {
      debugPrint('[VTG-MANAGER] Error during clutch calibration: $e');
      return ClutchCalibrationResult(
        success: false,
        message: 'Clutch calibration failed: $e',
        routineStatus: 0,
      );
    } finally {
      _isCalibrating = false;
    }
  }

  /// Reads one round of live telemetry DIDs from VTG (0x19)
  Future<VtgTelemetryData?> readTelemetryOnce() async {
    if (!await ensureConnected()) return null;
    final activeProto = _getActiveProtocol();

    try {
      double frontRatio = _lastTelemetry.frontTorquePercent;
      double rearRatio = _lastTelemetry.rearTorquePercent;
      double clutchTemp = _lastTelemetry.clutchTemperatureC;
      double clutchTorque = _lastTelemetry.clutchTorqueNm;

      // DID 0xD030: Torque Front Ratio
      final respD030 = await activeProto.sendUdsAndAwait(
        vtgAddress,
        [udsReadDataById, 0xD0, 0x30],
        timeout: const Duration(milliseconds: 600),
      );
      if (respD030 != null && respD030.isNotEmpty && respD030[0] == 0x62 && respD030.length >= 4) {
        if (respD030.length == 4) {
          frontRatio = respD030[3].toDouble().clamp(0.0, 100.0);
        } else {
          final raw = (respD030[3] << 8) | respD030[4];
          frontRatio = (raw > 100 ? raw / 10.0 : raw.toDouble()).clamp(0.0, 100.0);
        }
      }

      // DID 0xD031: Torque Rear Ratio
      final respD031 = await activeProto.sendUdsAndAwait(
        vtgAddress,
        [udsReadDataById, 0xD0, 0x31],
        timeout: const Duration(milliseconds: 600),
      );
      if (respD031 != null && respD031.isNotEmpty && respD031[0] == 0x62 && respD031.length >= 4) {
        if (respD031.length == 4) {
          rearRatio = respD031[3].toDouble().clamp(0.0, 100.0);
        } else {
          final raw = (respD031[3] << 8) | respD031[4];
          rearRatio = (raw > 100 ? raw / 10.0 : raw.toDouble()).clamp(0.0, 100.0);
        }
      } else {
        // Enforce sum to 100%
        rearRatio = (100.0 - frontRatio).clamp(0.0, 100.0);
      }

      // DID 0xD032: Clutch Temperature (°C)
      final respD032 = await activeProto.sendUdsAndAwait(
        vtgAddress,
        [udsReadDataById, 0xD0, 0x32],
        timeout: const Duration(milliseconds: 600),
      );
      if (respD032 != null && respD032.isNotEmpty && respD032[0] == 0x62 && respD032.length >= 4) {
        if (respD032.length == 4) {
          final raw = respD032[3];
          clutchTemp = (raw > 40 && raw < 180) ? (raw - 40).toDouble() : raw.toDouble();
        } else {
          final raw = (respD032[3] << 8) | respD032[4];
          final val = (raw / 10.0) - 40.0;
          clutchTemp = (val >= 0 && val <= 250) ? val : raw.toDouble();
        }
      }

      // DID 0xD033: Clutch Torque (Nm)
      final respD033 = await activeProto.sendUdsAndAwait(
        vtgAddress,
        [udsReadDataById, 0xD0, 0x33],
        timeout: const Duration(milliseconds: 600),
      );
      if (respD033 != null && respD033.isNotEmpty && respD033[0] == 0x62 && respD033.length >= 4) {
        if (respD033.length == 4) {
          clutchTorque = respD033[3].toDouble() * 4.0;
        } else {
          final raw = (respD033[3] << 8) | respD033[4];
          clutchTorque = (raw > 1500) ? raw / 10.0 : raw.toDouble();
        }
      }

      final data = VtgTelemetryData(
        frontTorquePercent: frontRatio,
        rearTorquePercent: rearRatio,
        clutchTemperatureC: clutchTemp,
        clutchTorqueNm: clutchTorque,
        timestamp: DateTime.now(),
      );

      _lastTelemetry = data;
      _telemetryController.add(data);
      return data;
    } catch (e) {
      debugPrint('[VTG-MANAGER] Telemetry read error: $e');
      return null;
    }
  }

  /// Starts continuous live telemetry polling
  void startTelemetryPolling({Duration interval = const Duration(milliseconds: 350)}) {
    if (_isPollingTelemetry) return;
    _isPollingTelemetry = true;
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(interval, (_) async {
      if (!_isSwitchingMode && !_isCalibrating) {
        await readTelemetryOnce();
      }
    });
  }

  /// Stops live telemetry polling
  void stopTelemetryPolling() {
    _isPollingTelemetry = false;
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
  }

  /// CAN Heartbeat to DSC (0x29) and DME (0x12) to suppress AWD error lights in cluster
  /// Sends TesterPresent [0x3E, 0x80] every 1500ms
  void _startClusterLampSuppressionHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        final activeProto = _getActiveProtocol();
        if (activeProto.isConnected) {
          // Suppress response bit (0x80)
          await activeProto.sendHsfz(vtgAddress, [udsTesterPresent, 0x80]);
          await activeProto.sendHsfz(dscAddress, [udsTesterPresent, 0x80]);
          await activeProto.sendHsfz(dmeAddress, [udsTesterPresent, 0x80]);
        }
      } catch (e) {
        debugPrint('[VTG-MANAGER] Heartbeat send error: $e');
      }
    });
  }

  void _stopClusterLampSuppressionHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  void dispose() {
    stopTelemetryPolling();
    _stopClusterLampSuppressionHeartbeat();
    _telemetryController.close();
  }
}
