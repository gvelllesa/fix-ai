import 'dart:async';
import 'package:flutter/foundation.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'actuation_guard.dart';

/// BMW DME & KOMBI Real-Time Diagnostic Actuator Engine
///
/// Implements ISTA / ProTool / BM3 Live Diagnostic Actuations:
/// - Electric Coolant Pump Bleeding Routine (UDS 0x31)
/// - Multi-speed Radiator Fan Stepped Actuation (UDS 0x2F)
/// - Fuel Tank Breather / Purge Valve (TEV) (UDS 0x2F)
/// - DISA Variable Intake Runner Actuation (UDS 0x2F)
/// - Intake & Exhaust VANOS Solenoid Testing (UDS 0x2F)
/// - Individual Cylinder Selective Cutoff 1-6 (UDS 0x2F)
/// - KOMBI Instrument Cluster Gauge Needle Sweep (UDS 0x2F)
/// - Exhaust Sound Flap Control (UDS 0x2F)
/// - Pneumatic / Electronic Wastegate Duty Cycle (UDS 0x2F)
///
/// ZERO SIMULATION: Direct ISO 14229 / HSFZ framing to vehicle ECUs.
class BmwLiveActuator {
  final EnetHsfzProtocol? protocol;
  static const int dmeAddress = 0x12;   // BMW DME UDS Address
  static const int kombiAddress = 0x60; // BMW KOMBI (Instrument Cluster) Address

  Timer? _autoReleaseTimer;

  // Actuator States
  bool _isMaxCoolingActive = false;
  bool _isExhaustFlapOpen = false;
  bool _isCoolantBleedingActive = false;
  int _radiatorFanSpeed = 0;
  bool _isFuelTankVentValveActive = false;
  final Map<int, bool> _disaValvesState = {1: false, 2: false};
  bool _isIntakeVanosActive = false;
  bool _isExhaustVanosActive = false;
  final Map<int, bool> _cylinderCutoffState = {};
  bool _isNeedleSweepRunning = false;

  // Getters
  bool get isMaxCoolingActive => _isMaxCoolingActive;
  bool get isExhaustFlapOpen => _isExhaustFlapOpen;
  bool get isCoolantBleedingActive => _isCoolantBleedingActive;
  int get radiatorFanSpeed => _radiatorFanSpeed;
  bool get isFuelTankVentValveActive => _isFuelTankVentValveActive;
  Map<int, bool> get disaValvesState => Map.unmodifiable(_disaValvesState);
  bool get isIntakeVanosActive => _isIntakeVanosActive;
  bool get isExhaustVanosActive => _isExhaustVanosActive;
  Map<int, bool> get cylinderCutoffState => Map.unmodifiable(_cylinderCutoffState);
  bool get isNeedleSweepRunning => _isNeedleSweepRunning;

  int get activeCutCylindersCount =>
      _cylinderCutoffState.values.where((active) => active).length;

  BmwLiveActuator({this.protocol});

  void _armAutoReleaseTimer() {
    _autoReleaseTimer?.cancel();
    _autoReleaseTimer = Timer(
      ActuationGuard.maxShortTermActuationDuration,
      () {
        debugPrint('[BmwLiveActuator] 30s safety timeout reached — releasing all 0x2F actuations');
        releaseAllActuations();
      },
    );
  }

  Future<EnetHsfzProtocol?> _ensureConnected() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final connected = await activeProto.connect();
      if (!connected) return null;
    }
    return activeProto;
  }

  /// Trigger Coolant Bleeding Procedure
  /// 12-minute automatic electric coolant pump purge cycle (Entlüftungsroutine)
  /// UDS RoutineControl: 0x31 0x01 0x10 0x03
  Future<bool> triggerCoolantBleedingProcedure() async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final command = [0x31, 0x01, 0x10, 0x03];
      final response = await proto.sendUdsRequest(dmeAddress, command);

      // Positive response for RoutineControl (0x31 + 0x40 = 0x71)
      if (response.isNotEmpty && response[0] == 0x71) {
        _isCoolantBleedingActive = true;
        debugPrint('[BmwLiveActuator] Coolant Bleeding Procedure ACTIVATED (12-min routine)');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in triggerCoolantBleedingProcedure: $e');
      return false;
    }
  }

  /// Stop Coolant Bleeding Procedure
  /// UDS RoutineControl Stop: 0x31 0x02 0x10 0x03
  Future<bool> stopCoolantBleedingProcedure() async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final command = [0x31, 0x02, 0x10, 0x03];
      final response = await proto.sendUdsRequest(dmeAddress, command);

      if (response.isNotEmpty && response[0] == 0x71) {
        _isCoolantBleedingActive = false;
        debugPrint('[BmwLiveActuator] Coolant Bleeding Procedure STOPPED');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in stopCoolantBleedingProcedure: $e');
      return false;
    }
  }

  /// Stepped Radiator Fan Actuation (0%, 20%, 50%, 100%)
  /// UDS: 0x2F 0xD0 0x12 0x03 [speedPercent]
  Future<bool> testRadiatorFanStep(int speedPercent) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final pct = speedPercent.clamp(0, 100);
      final List<int> command;
      if (pct == 0) {
        // Return control to ECU: 0x2F 0xD0 0x12 0x00
        command = [0x2F, 0xD0, 0x12, 0x00];
      } else {
        // ShortTermAdjustment: 0x2F 0xD0 0x12 0x03 [pct]
        command = [0x2F, 0xD0, 0x12, 0x03, pct];
      }

      final response = await proto.sendUdsRequest(dmeAddress, command);
      if (response.isNotEmpty && response[0] == 0x6F) {
        _radiatorFanSpeed = pct;
        if (pct > 0) _armAutoReleaseTimer();
        debugPrint('[BmwLiveActuator] Radiator Fan set to $pct%');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in testRadiatorFanStep: $e');
      return false;
    }
  }

  /// Fuel Tank Vent Valve (Tankentlüftungsventil / TEV Purge Valve)
  /// UDS: 0x2F 0xD0 0x14 [0x03/0x00] [0x64]
  Future<bool> testFuelTankVentValve(bool activate) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final List<int> command = activate
          ? [0x2F, 0xD0, 0x14, 0x03, 0x64]
          : [0x2F, 0xD0, 0x14, 0x00];

      final response = await proto.sendUdsRequest(dmeAddress, command);
      if (response.isNotEmpty && response[0] == 0x6F) {
        _isFuelTankVentValveActive = activate;
        if (activate) _armAutoReleaseTimer();
        debugPrint('[BmwLiveActuator] TEV Purge Valve ${activate ? "ACTIVATED" : "RETURNED TO ECU"}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in testFuelTankVentValve: $e');
      return false;
    }
  }

  /// DISA Variable Intake Runner Valves (Stage 1 or Stage 2)
  /// UDS: 0x2F 0xD0 0x16 [stage] [0x01/0x00]
  Future<bool> testDisaValves(int stage, bool open) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final st = stage.clamp(1, 2);
      final stateByte = open ? 0x01 : 0x00;
      final command = [0x2F, 0xD0, 0x16, st, stateByte];

      final response = await proto.sendUdsRequest(dmeAddress, command);
      if (response.isNotEmpty && response[0] == 0x6F) {
        _disaValvesState[st] = open;
        if (open) _armAutoReleaseTimer();
        debugPrint('[BmwLiveActuator] DISA Valve Stage $st set to ${open ? "OPEN" : "CLOSED"}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in testDisaValves: $e');
      return false;
    }
  }

  /// VANOS Camshaft Timing Solenoid Test (Intake or Exhaust)
  /// UDS: 0x2F 0xD0 0x18 [0x01/0x02] [0x64]
  Future<bool> testVanosSolenoid(bool isExhaust, bool activate) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final subId = isExhaust ? 0x02 : 0x01;
      final List<int> command = activate
          ? [0x2F, 0xD0, 0x18, subId, 0x64]
          : [0x2F, 0xD0, 0x18, subId, 0x00];

      final response = await proto.sendUdsRequest(dmeAddress, command);
      if (response.isNotEmpty && response[0] == 0x6F) {
        if (isExhaust) {
          _isExhaustVanosActive = activate;
        } else {
          _isIntakeVanosActive = activate;
        }
        if (activate) _armAutoReleaseTimer();
        debugPrint('[BmwLiveActuator] VANOS (${isExhaust ? "Exhaust" : "Intake"}) ${activate ? "TRIGGERED (100%)" : "OFF"}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in testVanosSolenoid: $e');
      return false;
    }
  }

  /// Individual Cylinder Selective Cutoff Diagnostic (Cylinders 1-6)
  /// Disables injection & ignition per cylinder to diagnose misfires
  /// UDS: 0x2F [0xD0, 0x20 + cylinderNumber] [0x03] [cutoff ? 0x01 : 0x00]
  Future<bool> testCylinderCutoff(int cylinderNumber, bool cutoff) async {
    final cyl = cylinderNumber.clamp(1, 8);
    if (cutoff && activeCutCylindersCount >= 1 && !(_cylinderCutoffState[cyl] ?? false)) {
      debugPrint('[BmwLiveActuator] Blocked cylinder $cyl cutoff: another cylinder is already cut off');
      return false;
    }

    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final List<int> command = cutoff
          ? [0x2F, 0xD0, 0x20 + cyl, 0x03, 0x01]
          : [0x2F, 0xD0, 0x20 + cyl, 0x00];

      final response = await proto.sendUdsRequest(dmeAddress, command);
      if (response.isNotEmpty && response[0] == 0x6F) {
        _cylinderCutoffState[cyl] = cutoff;
        if (cutoff) _armAutoReleaseTimer();
        debugPrint('[BmwLiveActuator] Cylinder $cyl Cutoff set to $cutoff');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in testCylinderCutoff: $e');
      return false;
    }
  }

  /// KOMBI Instrument Cluster Gauge Needle Sweep (Zeigerwischen)
  /// Sweeps speedometer, tachometer, and fuel gauge needles to 100% and resets
  /// KOMBI Address 0x60, UDS: 0x2F 0xD0 0x01 0x03 0x64
  Future<bool> triggerKombiGaugeNeedleSweep() async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      _isNeedleSweepRunning = true;
      // Step 1: Actuate needles to 100%
      final sweepCommand = [0x2F, 0xD0, 0x01, 0x03, 0x64];
      final response = await proto.sendUdsRequest(kombiAddress, sweepCommand);

      if (response.isNotEmpty && response[0] == 0x6F) {
        debugPrint('[BmwLiveActuator] KOMBI Needle Sweep triggered to 100%');
        // Let needles travel to max and hold momentarily
        await Future.delayed(const Duration(milliseconds: 1400));

        // Step 2: Return needle control back to normal KOMBI autonomous control
        final returnCommand = [0x2F, 0xD0, 0x01, 0x00];
        await proto.sendUdsRequest(kombiAddress, returnCommand);
        debugPrint('[BmwLiveActuator] KOMBI Needle Sweep returned to normal');
        _isNeedleSweepRunning = false;
        return true;
      }
      _isNeedleSweepRunning = false;
      return false;
    } catch (e) {
      _isNeedleSweepRunning = false;
      debugPrint('[BmwLiveActuator] Error in triggerKombiGaugeNeedleSweep: $e');
      return false;
    }
  }

  /// Trigger Max Cooling (Electric Water Pump & Radiator Fan to 100% duty cycle)
  /// UDS Service 0x2F 0xD0 0x15
  Future<bool> setMaxCooling(bool enable) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      if (enable) {
        final command = [0x2F, 0xD0, 0x15, 0x03, 0x64];
        final response = await proto.sendUdsRequest(dmeAddress, command);
        if (response.isNotEmpty && response[0] == 0x6F) {
          _isMaxCoolingActive = true;
          _armAutoReleaseTimer();
          debugPrint('[BmwLiveActuator] Max Cooling ACTIVATED (100% Pump & Fan)');
          return true;
        }
      } else {
        final command = [0x2F, 0xD0, 0x15, 0x00];
        final response = await proto.sendUdsRequest(dmeAddress, command);
        if (response.isNotEmpty && response[0] == 0x6F) {
          _isMaxCoolingActive = false;
          debugPrint('[BmwLiveActuator] Max Cooling RETURNED TO DME CONTROL');
          return true;
        }
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in setMaxCooling: $e');
      return false;
    }
  }

  /// Actuate Exhaust Flap (Abgasklappe) Open / Close on demand
  Future<bool> setExhaustFlap(bool open) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final stateByte = open ? 0x01 : 0x00;
      final command = [0x2F, 0x31, 0x0A, 0x03, stateByte];
      final response = await proto.sendUdsRequest(dmeAddress, command);

      if (response.isNotEmpty && response[0] == 0x6F) {
        _isExhaustFlapOpen = open;
        if (open) _armAutoReleaseTimer();
        debugPrint('[BmwLiveActuator] Exhaust Flap set to ${open ? "OPEN" : "CLOSED"}');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in setExhaustFlap: $e');
      return false;
    }
  }

  /// Actuate Pneumatic Wastegate (PWG) PWM Duty Cycle (0% to 100%)
  Future<bool> setWastegateDutyCycle(int dutyCyclePercent) async {
    final proto = await _ensureConnected();
    if (proto == null) return false;

    try {
      final dcByte = dutyCyclePercent.clamp(0, 100);
      final command = [0x2F, 0xD0, 0x22, 0x03, dcByte];
      final response = await proto.sendUdsRequest(dmeAddress, command);
      if (response.isNotEmpty && response[0] == 0x6F) {
        _armAutoReleaseTimer();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error in setWastegateDutyCycle: $e');
      return false;
    }
  }

  /// Reset all actuations back to standard ECU autonomous control
  Future<void> releaseAllActuations() async {
    _autoReleaseTimer?.cancel();
    _autoReleaseTimer = null;
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return;

    try {
      // 1. Return Cooling / Fan / Water Pump
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x15, 0x00]);
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x12, 0x00]);
      if (_isCoolantBleedingActive) {
        await activeProto.sendUdsRequest(dmeAddress, [0x31, 0x02, 0x10, 0x03]);
      }

      // 2. Return Exhaust Flap
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0x31, 0x0A, 0x00]);

      // 3. Return Fuel Tank Vent Valve (TEV)
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x14, 0x00]);

      // 4. Return DISA Valves
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x16, 0x01, 0x00]);
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x16, 0x02, 0x00]);

      // 5. Return VANOS Solenoids
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x18, 0x01, 0x00]);
      await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x18, 0x02, 0x00]);

      // 6. Return All Cutoff Cylinders (1-8)
      for (int c = 1; c <= 8; c++) {
        await activeProto.sendUdsRequest(dmeAddress, [0x2F, 0xD0, 0x20 + c, 0x00]);
      }

      // 7. Return KOMBI Needle Control
      await activeProto.sendUdsRequest(kombiAddress, [0x2F, 0xD0, 0x01, 0x00]);

      // Clear local states
      _isMaxCoolingActive = false;
      _isExhaustFlapOpen = false;
      _isCoolantBleedingActive = false;
      _radiatorFanSpeed = 0;
      _isFuelTankVentValveActive = false;
      _disaValvesState[1] = false;
      _disaValvesState[2] = false;
      _isIntakeVanosActive = false;
      _isExhaustVanosActive = false;
      _cylinderCutoffState.clear();
      _isNeedleSweepRunning = false;

      debugPrint('[BmwLiveActuator] All actuations successfully released back to ECU');
    } catch (e) {
      debugPrint('[BmwLiveActuator] Error releasing actuations: $e');
    }
  }
}
