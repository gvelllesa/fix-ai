import 'dart:async';
import 'package:flutter/foundation.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'bmw_flash_options.dart';

/// Bootmod3 & MHD Multimap Slot Profiles
enum CustomRomSlot {
  slot1(
    id: 1,
    title: 'Slot 1: ACN91 (91 Octane)',
    description: 'Stage 1 / Stage 2 ACN91 (91 Octane calibration)',
    clusterTachRpm: 1000,
    octaneRating: '91 ACN',
  ),
  slot2(
    id: 2,
    title: 'Slot 2: 93 Octane / 98 RON',
    description: 'Stage 1 / Stage 2 93 Octane / 98 RON performance calibration',
    clusterTachRpm: 2000,
    octaneRating: '93 Oct / 98 RON',
  ),
  slot3(
    id: 3,
    title: 'Slot 3: E30 / Full FlexFuel',
    description: 'E30 / Full FlexFuel (Adaptive ethanol blending with CAN 0x4F0)',
    clusterTachRpm: 3000,
    octaneRating: 'E30 - E85 Flex',
  ),
  slot4(
    id: 4,
    title: 'Slot 4: Anti-Theft / Valet Mode',
    description: 'Speed limited to 30 km/h, rev limit 2500 RPM, valet mode',
    clusterTachRpm: 4000,
    octaneRating: 'Valet / Safe',
  );

  final int id;
  final String title;
  final String description;
  final int clusterTachRpm;
  final String octaneRating;

  const CustomRomSlot({
    required this.id,
    required this.title,
    required this.description,
    required this.clusterTachRpm,
    required this.octaneRating,
  });

  static CustomRomSlot fromId(int id) {
    return CustomRomSlot.values.firstWhere(
      (slot) => slot.id == id,
      orElse: () => CustomRomSlot.slot1,
    );
  }
}

/// Decoded real-time FlexFuel sensor data
class FlexFuelData {
  final double ethanolPercent;
  final double fuelTempCelsius;
  final double boostScalar;
  final double timingAdvanceDeg;
  final bool isSensorValid;

  const FlexFuelData({
    required this.ethanolPercent,
    required this.fuelTempCelsius,
    required this.boostScalar,
    required this.timingAdvanceDeg,
    this.isSensorValid = true,
  });

  /// Mathematical interpolation for boost scalar:
  /// 1.0x at <= 10% ethanol up to 1.35x at >= 85% ethanol
  static double calculateBoostScalar(double ethanol) {
    if (ethanol <= 10.0) return 1.0;
    if (ethanol >= 85.0) return 1.35;
    final fraction = (ethanol - 10.0) / (85.0 - 10.0);
    return double.parse((1.0 + (fraction * 0.35)).toStringAsFixed(3));
  }

  /// Mathematical interpolation for timing advance:
  /// 0.0° at <= 10% ethanol up to +5.5° at >= 85% ethanol
  static double calculateTimingAdvance(double ethanol) {
    if (ethanol <= 10.0) return 0.0;
    if (ethanol >= 85.0) return 5.5;
    final fraction = (ethanol - 10.0) / (85.0 - 10.0);
    return double.parse((fraction * 5.5).toStringAsFixed(2));
  }

  /// Parses DME RAM DID 0xD410 UDS response:
  /// [0x62, 0xD4, 0x10, ethanolPercent, tempByte, ...]
  factory FlexFuelData.fromUdsResponse(List<int> response) {
    if (response.length < 4 || response[0] != 0x62 || response[1] != 0xD4 || response[2] != 0x10) {
      throw ArgumentError('Invalid UDS response for FlexFuel DID 0xD410: $response');
    }

    final rawEthanol = response[3];
    final ethanol = rawEthanol.toDouble().clamp(0.0, 100.0);

    double fuelTemp = 20.0;
    if (response.length >= 5) {
      fuelTemp = (response[4] - 40).toDouble();
    }

    return FlexFuelData(
      ethanolPercent: ethanol,
      fuelTempCelsius: fuelTemp,
      boostScalar: calculateBoostScalar(ethanol),
      timingAdvanceDeg: calculateTimingAdvance(ethanol),
      isSensorValid: true,
    );
  }

  /// Decodes CAN Bus Broadcast message 0x4F0 from aftermarket FlexFuel kit (Zeitronix / BM3 / Motiv Reflex)
  factory FlexFuelData.fromCanFrame(int canId, List<int> frameData) {
    if (canId != 0x4F0) {
      throw ArgumentError('Invalid CAN ID for FlexFuel. Expected 0x4F0, received 0x${canId.toRadixString(16)}');
    }
    if (frameData.length < 2) {
      throw ArgumentError('CAN 0x4F0 frame must contain at least 2 data bytes: $frameData');
    }

    final ethanol = frameData[0].toDouble().clamp(0.0, 100.0);
    final fuelTemp = (frameData[1] - 40).toDouble();
    final isValid = frameData.length < 3 || frameData[2] == 0x00;

    return FlexFuelData(
      ethanolPercent: ethanol,
      fuelTempCelsius: fuelTemp,
      boostScalar: calculateBoostScalar(ethanol),
      timingAdvanceDeg: calculateTimingAdvance(ethanol),
      isSensorValid: isValid,
    );
  }
}

/// Service providing Bootmod3 & MHD Custom ROM Advanced Tuning features:
/// 1. Multimap Slot Switching on-the-fly (UDS 0x22 / 0x2E / 0x31)
/// 2. Cruise Control "RES" button emulation & cluster tachometer slot indication
/// 3. FlexFuel Real-Time sensor decoding (RAM DID 0xD410 & CAN 0x4F0)
/// 4. Anti-Theft Kill Switch with steering wheel PIN routine control (0x2F / 0x31)
/// 5. Rolling Anti-Lag (RAL) on Cruise Rocker / RES (DID 0xD420 & Routine 0xD421)
/// 6. Boost By Gear & Torque By Gear (DID 0xD430 & DID 0xD431)
/// 7. HPFP Flow Scaling Profiles (DID 0xD440)
/// 8. TMAP Sensor Voltage-Pressure Curves (DID 0xD445)
/// 9. GTS Startup Roar / Start Bark (DID 0xD450)
/// 10. N55 Wastegate Rattle Fix (DID 0xD455)
/// 11. Transmission Shift Brap Spark Cut (DID 0xD460 & Routine 0xD461)
/// 12. Knock CEL Alert Real-Time Flashing (DID 0xD465 & Routine 0xD466)
/// 13. Catless Downpipe DTC Suppression Mask (DID 0xD470)
class BmwCustomRomService {
  final EnetHsfzProtocol? protocol;
  static const int dmeAddress = 0x12; // Engine ECU
  static const int egsAddress = 0x18; // Electronic Transmission Control (EGS / TCU)
  static const int femAddress = 0x40; // Front Electronic Module / BDC
  static const int kombiAddress = 0x60; // Instrument Cluster

  // UDS DIDs (Data Identifiers for Custom ROM RAM Tables)
  static const int didMultimapSlot = 0xD400;
  static const int didTachIndication = 0xD402;
  static const int didAntiTheftStatus = 0xD405;
  static const int didFlexFuel = 0xD410;
  static const int didRollingAntiLag = 0xD420;
  static const int didBoostByGear = 0xD430;
  static const int didTorqueByGear = 0xD431;
  static const int didHpfpConfig = 0xD440;
  static const int didTcuOptions = 0xD440; // EGS (0x18) xHP Transmission Tuning Configuration
  static const int didTmapCalibration = 0xD445;
  static const int didGtsStartupRoar = 0xD450;
  static const int didWastegateRattle = 0xD455;
  static const int didShiftBrap = 0xD460;
  static const int didKnockCelAlert = 0xD465;
  static const int didDtcSuppressionMask = 0xD470;
  static const int didCustomRomMasterTable = 0xD4FE;

  // UDS Routines (0x31 RoutineControl)
  static const int routineActivateMapSlot = 0x3001;
  static const int routineTachIndication = 0xD402;
  static const int routineAntiTheftPin = 0xD406;
  static const int routineTriggerAntiLag = 0xD421;
  static const int routineTestStartupRoar = 0xD451;
  static const int routineTestShiftBrap = 0xD461;
  static const int routineTestKnockCel = 0xD466;

  BmwCustomRomService({this.protocol});

  // ==========================================
  // Deterministic Payload Builders
  // ==========================================

  static List<int> buildCheckCustomRomPayload() => const [0x22, 0xD4, 0x00];

  static List<int> buildReadSlotPayload() => const [0x22, 0xD4, 0x00];

  static List<int> buildWriteSlotPayload(int targetSlot) => [0x2E, 0xD4, 0x00, targetSlot & 0xFF];

  static List<int> buildRoutineSlotPayload(int targetSlot) => [0x31, 0x01, 0x30, 0x01, targetSlot & 0xFF];

  static List<int> buildCruiseResTriggerPayload({int targetSlot = 1}) => [0x31, 0x01, 0xD4, 0x02, targetSlot & 0xFF];

  static List<int> buildTachIndicationPayload(int rpm) => [
    0x2F, 0xD4, 0x02, 0x03, (rpm >> 8) & 0xFF, rpm & 0xFF,
  ];

  static List<int> buildFlexFuelReadPayload() => const [0x22, 0xD4, 0x10];

  static List<int> buildAntiTheftStatusPayload() => const [0x22, 0xD4, 0x05];

  static List<int> buildArmAntiTheftPayload() => const [0x2F, 0xD4, 0x05, 0x03, 0x01];

  static List<int> buildDisarmAntiTheftPayload() => const [0x2F, 0xD4, 0x05, 0x03, 0x00];

  static List<int> buildDisarmWithPinPayload(List<int> pin) {
    if (pin.length != 4) {
      throw ArgumentError('Anti-Theft PIN must be exactly 4 digits/bytes');
    }
    return [0x31, 0x01, 0xD4, 0x06, pin[0], pin[1], pin[2], pin[3]];
  }

  // 1. Rolling Anti-Lag Payloads
  static List<int> buildReadAntiLagPayload() => const [0x22, 0xD4, 0x20];

  static List<int> buildWriteAntiLagPayload(RollingAntiLagConfig config) {
    return [0x2E, 0xD4, 0x20, ...config.toBytes()];
  }

  static List<int> buildTriggerAntiLagRoutinePayload({
    bool activate = true,
    double boostTargetPsi = 15.0,
    double durationSeconds = 3.0,
    double retardDeg = -15.0,
  }) {
    final boostInt = (boostTargetPsi.clamp(10.0, 20.0) * 10).toInt();
    final durInt = (durationSeconds.clamp(1.0, 5.0) * 10).toInt();
    final retardInt = (retardDeg.abs().clamp(10.0, 20.0) * 10).toInt();
    return [
      0x31,
      0x01,
      0xD4,
      0x21,
      activate ? 0x01 : 0x00,
      boostInt & 0xFF,
      durInt & 0xFF,
      retardInt & 0xFF,
    ];
  }

  // 2. Boost By Gear & Torque By Gear Payloads
  static List<int> buildReadBoostByGearPayload() => const [0x22, 0xD4, 0x30];

  static List<int> buildWriteBoostByGearPayload(BoostByGearConfig config) {
    return [0x2E, 0xD4, 0x30, ...config.toBytes()];
  }

  static List<int> buildReadTorqueByGearPayload() => const [0x22, 0xD4, 0x31];

  static List<int> buildWriteTorqueByGearPayload(TorqueByGearConfig config) {
    return [0x2E, 0xD4, 0x31, ...config.toBytes()];
  }

  // 3. HPFP Flow Scaling Payloads
  static List<int> buildReadHpfpPayload() => const [0x22, 0xD4, 0x40];

  static List<int> buildWriteHpfpPayload(HpfpProfile profile) {
    return [0x2E, 0xD4, 0x40, ...profile.toCalibrationBytes()];
  }

  // 4. TMAP Sensor Calibration Payloads
  static List<int> buildReadTmapPayload() => const [0x22, 0xD4, 0x45];

  static List<int> buildWriteTmapPayload(TmapSensorType manifold, TmapSensorType preThrottle) {
    return [
      0x2E,
      0xD4,
      0x45,
      ...manifold.toCalibrationBytes(),
      ...preThrottle.toCalibrationBytes(),
    ];
  }

  // 5. GTS Startup Roar Payloads
  static List<int> buildReadGtsStartupRoarPayload() => const [0x22, 0xD4, 0x50];

  static List<int> buildWriteGtsStartupRoarPayload(GtsStartupRoarConfig config) {
    return [0x2E, 0xD4, 0x50, ...config.toBytes()];
  }

  // 6. Wastegate Rattle Fix Payloads
  static List<int> buildReadWastegateRattlePayload() => const [0x22, 0xD4, 0x55];

  static List<int> buildWriteWastegateRattlePayload(bool enabled, int offsetPercent) {
    return [
      0x2E,
      0xD4,
      0x55,
      enabled ? 0x01 : 0x00,
      offsetPercent.clamp(-20, 20) & 0xFF,
    ];
  }

  // 7. Transmission Shift Brap Payloads
  static List<int> buildReadShiftBrapPayload() => const [0x22, 0xD4, 0x60];

  static List<int> buildWriteShiftBrapPayload(ShiftBrapConfig config) {
    return [0x2E, 0xD4, 0x60, ...config.toBytes()];
  }

  static List<int> buildTestShiftBrapRoutinePayload() => const [0x31, 0x01, 0xD4, 0x61, 0x01];

  // 8. Knock CEL Alert Payloads
  static List<int> buildReadKnockCelPayload() => const [0x22, 0xD4, 0x65];

  static List<int> buildWriteKnockCelPayload(KnockCelConfig config) {
    return [0x2E, 0xD4, 0x65, ...config.toBytes()];
  }

  static List<int> buildTestKnockCelRoutinePayload({int flashCount = 4, int rateHz = 4}) => [
    0x31,
    0x01,
    0xD4,
    0x66,
    flashCount.clamp(1, 10),
    rateHz.clamp(1, 8),
  ];

  // 9. Catless Downpipe DTC Suppression Payloads
  static List<int> buildReadCatlessSuppressionPayload() => const [0x22, 0xD4, 0x70];

  static List<int> buildWriteCatlessSuppressionPayload(CatlessDtcSuppressionConfig config) {
    return [0x2E, 0xD4, 0x70, ...config.toBytes()];
  }

  // 10. xHP ZF 8HP / 6HP Transmission Tuning Payloads (EGS 0x18 / DID 0xD440)
  static List<int> buildReadTcuOptionsPayload() => const [0x22, 0xD4, 0x40];

  static List<int> buildWriteTcuOptionsPayload(XhpTcuOptions options) {
    return [0x2E, 0xD4, 0x40, ...options.toBytes()];
  }

  // ==========================================
  // Custom ROM Live Operations & UDS Handlers
  // ==========================================

  /// Check whether DME has Bootmod3 / MHD Custom ROM patched bootloader
  Future<bool> isCustomRomInstalled() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildCheckCustomRomPayload());
      return resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x00;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error checking custom ROM: $e');
      return false;
    }
  }

  /// Read currently active multimap slot from DME RAM DID 0xD400
  Future<CustomRomSlot?> readActiveSlot() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadSlotPayload());
      if (resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x00) {
        final slotId = resp[3];
        return CustomRomSlot.fromId(slotId);
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading active slot: $e');
      return null;
    }
  }

  /// Switch active multimap slot on-the-fly via UDS Write 0x2E and Routine 0x31
  Future<bool> switchMapSlot(int targetSlot) async {
    if (targetSlot < 1 || targetSlot > 4) {
      throw ArgumentError('Invalid map slot: $targetSlot (Must be 1 to 4)');
    }

    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final writeResp = await activeProto.sendUdsRequest(dmeAddress, buildWriteSlotPayload(targetSlot));
      final writeOk = writeResp.isNotEmpty && writeResp[0] == 0x6E;

      final routineResp = await activeProto.sendUdsRequest(dmeAddress, buildRoutineSlotPayload(targetSlot));
      final routineOk = routineResp.isNotEmpty && routineResp[0] == 0x71;

      if (writeOk || routineOk) {
        await triggerCruiseResButton(targetSlot: targetSlot);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error switching map slot: $e');
      return false;
    }
  }

  /// Triggers Cruise Control RES button command to activate cluster tachometer needle indication
  Future<bool> triggerCruiseResButton({int targetSlot = 1}) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final dmeResp = await activeProto.sendUdsRequest(
        dmeAddress,
        buildCruiseResTriggerPayload(targetSlot: targetSlot),
      );

      await activeProto.sendUdsRequest(femAddress, [0x2F, 0x4F, 0x00, 0x03, 0x01]);
      return dmeResp.isNotEmpty && (dmeResp[0] == 0x71 || dmeResp[0] == 0x6F);
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error triggering cruise RES button: $e');
      return false;
    }
  }

  /// Sends Tachometer Needle Sweep command to Instrument Cluster
  Future<bool> setTachometerIndication(int rpm) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildTachIndicationPayload(rpm));
      return resp.isNotEmpty && resp[0] == 0x6F;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error setting tachometer indication: $e');
      return false;
    }
  }

  /// Reads real-time Ethanol % and Fuel Temp from DME RAM DID 0xD410
  Future<FlexFuelData?> readFlexFuelData() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildFlexFuelReadPayload());
      if (resp.length >= 4 && resp[0] == 0x62) {
        return FlexFuelData.fromUdsResponse(resp);
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading FlexFuel DID: $e');
      return null;
    }
  }

  /// Reads Anti-Theft armed status
  Future<bool?> isAntiTheftArmed() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildAntiTheftStatusPayload());
      if (resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x05) {
        return resp[3] == 0x01;
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading anti-theft status: $e');
      return null;
    }
  }

  /// Arms Anti-Theft kill switch: 0% injector pulse width & starter cut
  Future<bool> armAntiTheft() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildArmAntiTheftPayload());
      return resp.isNotEmpty && resp[0] == 0x6F;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error arming anti-theft: $e');
      return false;
    }
  }

  /// Disarms Anti-Theft kill switch
  Future<bool> disarmAntiTheft({List<int>? pin}) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      if (pin != null && pin.isNotEmpty) {
        final payload = buildDisarmWithPinPayload(pin);
        final resp = await activeProto.sendUdsRequest(dmeAddress, payload);
        return resp.isNotEmpty && (resp[0] == 0x71 || resp[0] == 0x6F);
      } else {
        final resp = await activeProto.sendUdsRequest(dmeAddress, buildDisarmAntiTheftPayload());
        return resp.isNotEmpty && resp[0] == 0x6F;
      }
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error disarming anti-theft: $e');
      return false;
    }
  }

  // ==========================================
  // 1. Rolling Anti-Lag (RAL) Service Methods
  // ==========================================

  /// Writes Rolling Anti-Lag calibration to DME RAM DID 0xD420
  Future<bool> writeRollingAntiLag(RollingAntiLagConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteAntiLagPayload(config));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Rolling Anti-Lag: $e');
      return false;
    }
  }

  /// Reads Rolling Anti-Lag calibration from DME RAM DID 0xD420
  Future<RollingAntiLagConfig?> readRollingAntiLag() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadAntiLagPayload());
      if (resp.length >= 7 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x20) {
        final enabled = resp[3] == 0x01;
        final boostTarget = resp[4] / 10.0;
        final duration = resp[5] / 10.0;
        final retard = -(resp[6] / 10.0);
        return RollingAntiLagConfig(
          enabled: enabled,
          boostTargetPsi: boostTarget,
          maxDurationSeconds: duration,
          ignitionRetardDeg: retard,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading Rolling Anti-Lag: $e');
      return null;
    }
  }

  /// Triggers Rolling Anti-Lag Routine 0xD421 (Cruise Rocker emulation)
  Future<bool> triggerRollingAntiLag({
    bool activate = true,
    double boostTargetPsi = 15.0,
    double durationSeconds = 3.0,
    double retardDeg = -15.0,
  }) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final payload = buildTriggerAntiLagRoutinePayload(
        activate: activate,
        boostTargetPsi: boostTargetPsi,
        durationSeconds: durationSeconds,
        retardDeg: retardDeg,
      );
      final resp = await activeProto.sendUdsRequest(dmeAddress, payload);
      return resp.isNotEmpty && (resp[0] == 0x71 || resp[0] == 0x6F);
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error triggering Rolling Anti-Lag: $e');
      return false;
    }
  }

  // ==========================================
  // 2. Boost By Gear & Torque By Gear
  // ==========================================

  Future<bool> writeBoostByGear(BoostByGearConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteBoostByGearPayload(config));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Boost By Gear: $e');
      return false;
    }
  }

  Future<BoostByGearConfig?> readBoostByGear() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return null;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadBoostByGearPayload());
      if (resp.length >= 12 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x30) {
        final enabled = resp[3] == 0x01;
        final limits = <double>[];
        for (int i = 0; i < 8; i++) {
          limits.add(resp[4 + i] / 2.0);
        }
        return BoostByGearConfig(enabled: enabled, gearLimitsPsi: limits);
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading Boost By Gear: $e');
      return null;
    }
  }

  Future<bool> writeTorqueByGear(TorqueByGearConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteTorqueByGearPayload(config));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Torque By Gear: $e');
      return false;
    }
  }

  Future<TorqueByGearConfig?> readTorqueByGear() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return null;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadTorqueByGearPayload());
      if (resp.length >= 20 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x31) {
        final enabled = resp[3] == 0x01;
        final limits = <int>[];
        for (int i = 0; i < 8; i++) {
          final high = resp[4 + (i * 2)];
          final low = resp[5 + (i * 2)];
          limits.add((high << 8) | low);
        }
        return TorqueByGearConfig(enabled: enabled, gearLimitsNm: limits);
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading Torque By Gear: $e');
      return null;
    }
  }

  // ==========================================
  // 3. HPFP Flow Scaling
  // ==========================================

  Future<bool> writeHpfpProfile(HpfpProfile profile) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteHpfpPayload(profile));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing HPFP profile: $e');
      return false;
    }
  }

  Future<HpfpProfile?> readHpfpProfile() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return null;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadHpfpPayload());
      if (resp.length >= 8 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x40) {
        final profileId = resp[3];
        return HpfpProfile.values.firstWhere(
          (p) => p.id == profileId,
          orElse: () => HpfpProfile.oem,
        );
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading HPFP profile: $e');
      return null;
    }
  }

  // ==========================================
  // 4. TMAP Sensor Calibration
  // ==========================================

  Future<bool> writeTmapCalibration(TmapSensorType manifold, TmapSensorType preThrottle) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(
        dmeAddress,
        buildWriteTmapPayload(manifold, preThrottle),
      );
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing TMAP calibration: $e');
      return false;
    }
  }

  Future<Map<String, TmapSensorType>?> readTmapCalibration() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return null;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadTmapPayload());
      if (resp.length >= 13 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x45) {
        final manifoldId = resp[3];
        final preThrottleId = resp[8];
        return {
          'manifold': TmapSensorType.values.firstWhere((s) => s.id == manifoldId, orElse: () => TmapSensorType.oem2_5Bar),
          'preThrottle': TmapSensorType.values.firstWhere((s) => s.id == preThrottleId, orElse: () => TmapSensorType.oem2_5Bar),
        };
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading TMAP calibration: $e');
      return null;
    }
  }

  // ==========================================
  // 5. GTS Startup Roar
  // ==========================================

  Future<bool> writeGtsStartupRoar(GtsStartupRoarConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteGtsStartupRoarPayload(config));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing GTS Startup Roar: $e');
      return false;
    }
  }

  // ==========================================
  // 6. Wastegate Rattle Fix (PWG Offset)
  // ==========================================

  Future<bool> writeWastegateRattle(bool enabled, int offsetPercent) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(
        dmeAddress,
        buildWriteWastegateRattlePayload(enabled, offsetPercent),
      );
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Wastegate Rattle: $e');
      return false;
    }
  }

  // ==========================================
  // 7. Transmission Upshift Shift Brap
  // ==========================================

  Future<bool> writeShiftBrap(ShiftBrapConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteShiftBrapPayload(config));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Shift Brap: $e');
      return false;
    }
  }

  Future<bool> testShiftBrap() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildTestShiftBrapRoutinePayload());
      return resp.isNotEmpty && (resp[0] == 0x71 || resp[0] == 0x6F);
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error testing Shift Brap: $e');
      return false;
    }
  }

  // ==========================================
  // 8. Knock CEL Alert Notification
  // ==========================================

  Future<bool> writeKnockCel(KnockCelConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteKnockCelPayload(config));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Knock CEL: $e');
      return false;
    }
  }

  Future<bool> testKnockCelFlash({int flashCount = 4, int rateHz = 4}) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(
        kombiAddress,
        buildTestKnockCelRoutinePayload(flashCount: flashCount, rateHz: rateHz),
      );
      return resp.isNotEmpty && (resp[0] == 0x71 || resp[0] == 0x6F);
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error testing Knock CEL flash: $e');
      return false;
    }
  }

  // ==========================================
  // 9. Catless Downpipe DTC Suppression Mask
  // ==========================================

  Future<bool> writeCatlessSuppression(CatlessDtcSuppressionConfig config) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) return false;

    try {
      final resp = await activeProto.sendUdsRequest(
        dmeAddress,
        buildWriteCatlessSuppressionPayload(config),
      );
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Catless Suppression: $e');
      return false;
    }
  }

  // ==========================================
  // 10. Master Custom ROM Table Flash Upload
  // ==========================================

  /// Writes all active BM3/MHD Custom ROM options into DME RAM DID 0xD4FE in one atomic UDS transaction
  Future<bool> syncCustomRomMasterTable(BmwFlashOptions options) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final tableBytes = options.serializeCustomRomBinaryTable();
      final payload = [0x2E, 0xD4, 0xFE, ...tableBytes];
      final resp = await activeProto.sendUdsRequest(dmeAddress, payload);
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error syncing Master Custom ROM table: $e');
      return false;
    }
  }

  // ==========================================
  // 11. xHP ZF 8HP / 6HP Transmission Tuning (EGS ECU 0x18)
  // ==========================================

  /// Writes xHP TCU configuration to EGS ECU (0x18) UDS DID 0xD440
  Future<bool> writeTcuOptions(XhpTcuOptions options) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(egsAddress, buildWriteTcuOptionsPayload(options));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing TCU options to EGS 0x18: $e');
      return false;
    }
  }

  /// Reads xHP TCU configuration from EGS ECU (0x18) UDS DID 0xD440
  Future<XhpTcuOptions?> readTcuOptions() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(egsAddress, buildReadTcuOptionsPayload());
      if (resp.length >= 19 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x40) {
        return XhpTcuOptions.fromBytes(resp.sublist(3, 19));
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading TCU options from EGS 0x18: $e');
      return null;
    }
  }
}
