import 'dart:async';
import 'package:flutter/foundation.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'bmw_flash_options.dart';

/// Proprietary Custom ROM Multimap Slot Profiles
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

/// Service providing Proprietary Custom ROM Custom ROM Advanced Tuning features:
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
  static const int didBurbleConfig = 0xD408; // Burble (Aggressiveness, Duration, Sport Duration, Min/Max RPM)
  static const int didColdStart = 0xD409;    // Cold start cat heating deactivation flag
  static const int didVmaxLimiter = 0xD40A;  // Top speed governor removal (250 km/h -> 330 km/h)
  static const int didExhaustFlap = 0xD40B;  // Exhaust flap mode (OEM / Sport / Always Open)
  static const int didFlexFuel = 0xD410;
  static const int didRollingAntiLag = 0xD420;
  static const int didBoostByGear = 0xD430;
  static const int didTorqueByGear = 0xD431;
  static const int didHpfpConfig = 0xD440;
  static const int didTcuOptions = 0xD440; // EGS (0x18) TCU Transmission Transmission Tuning Configuration
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
  // 0. DME Engine Custom Options Payloads (Burble, Cold Start, VMAX, Exhaust Flap)
  static List<int> buildReadBurblePayload() => const [0x22, 0xD4, 0x08];

  static List<int> buildWriteBurblePayload({
    required BurbleAggressiveness aggressiveness,
    required double duration,
    required double sportDuration,
    int minRpm = 1500,
    int maxRpm = 5500,
  }) {
    final durByte = (duration.clamp(0.0, 5.0) * 10).toInt();
    final sportDurByte = (sportDuration.clamp(0.0, 5.0) * 10).toInt();
    final clampedMinRpm = minRpm.clamp(1000, 3000);
    final clampedMaxRpm = maxRpm.clamp(3500, 7500);
    return [
      0x2E,
      0xD4,
      0x08,
      aggressiveness.level & 0xFF,
      durByte & 0xFF,
      sportDurByte & 0xFF,
      (clampedMinRpm >> 8) & 0xFF,
      clampedMinRpm & 0xFF,
      (clampedMaxRpm >> 8) & 0xFF,
      clampedMaxRpm & 0xFF,
    ];
  }

  static List<int> buildReadColdStartPayload() => const [0x22, 0xD4, 0x09];

  static List<int> buildWriteColdStartPayload(bool disabled) => [
    0x2E, 0xD4, 0x09, disabled ? 0x01 : 0x00,
  ];

  static List<int> buildReadVmaxLimiterPayload() => const [0x22, 0xD4, 0x0A];

  static List<int> buildWriteVmaxLimiterPayload(bool disabled) => [
    0x2E, 0xD4, 0x0A, disabled ? 0x01 : 0x00,
  ];

  static List<int> buildReadExhaustFlapPayload() => const [0x22, 0xD4, 0x0B];

  static List<int> buildWriteExhaustFlapPayload(int mode) => [
    0x2E, 0xD4, 0x0B, mode & 0xFF,
  ];

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

  // 10. TCU Transmission ZF 8HP / 6HP Transmission Tuning Payloads (EGS 0x18 / DID 0xD440)
  static List<int> buildReadTcuOptionsPayload() => const [0x22, 0xD4, 0x40];

  static List<int> buildWriteTcuOptionsPayload(BmwTcuOptions options) {
    return [0x2E, 0xD4, 0x40, ...options.toBytes()];
  }

  // ==========================================
  // Custom ROM Live Operations & UDS Handlers
  // ==========================================

  /// Check whether DME has Proprietary Custom ROM Custom ROM patched bootloader
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
      if (resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x10) {
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

  /// Writes all active Proprietary Custom ROM Custom ROM options into DME RAM DID 0xD4FE in one atomic UDS transaction
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
  // 11. TCU Transmission ZF 8HP / 6HP Transmission Tuning (EGS ECU 0x18)
  // ==========================================

  /// Writes TCU Transmission TCU configuration to EGS ECU (0x18) UDS DID 0xD440
  Future<bool> writeTcuOptions(BmwTcuOptions options) async {
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

  /// Reads TCU Transmission TCU configuration from EGS ECU (0x18) UDS DID 0xD440
  Future<BmwTcuOptions?> readTcuOptions() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(egsAddress, buildReadTcuOptionsPayload());
      if (resp.length >= 19 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x40) {
        return BmwTcuOptions.fromBytes(resp.sublist(3, 19));
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading TCU options from EGS 0x18: $e');
      return null;
    }
  }

  // ==========================================
  // 12. DME Engine Custom Options (DME ECU 0x12 / DIDs 0xD408 - 0xD40B)
  // ==========================================

  /// Writes Burble configuration to DME RAM DID 0xD408
  Future<bool> writeBurbleOptions({
    required BurbleAggressiveness aggressiveness,
    required double duration,
    required double sportDuration,
    int minRpm = 1500,
    int maxRpm = 5500,
  }) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final payload = buildWriteBurblePayload(
        aggressiveness: aggressiveness,
        duration: duration,
        sportDuration: sportDuration,
        minRpm: minRpm,
        maxRpm: maxRpm,
      );
      final resp = await activeProto.sendUdsRequest(dmeAddress, payload);
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Burble options: $e');
      return false;
    }
  }

  /// Reads Burble configuration from DME RAM DID 0xD408
  Future<Map<String, dynamic>?> readBurbleOptions() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadBurblePayload());
      if (resp.length >= 10 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x08) {
        final aggroLvl = resp[3];
        final dur = resp[4] / 10.0;
        final sportDur = resp[5] / 10.0;
        final minRpm = (resp[6] << 8) | resp[7];
        final maxRpm = (resp[8] << 8) | resp[9];
        final aggro = BurbleAggressiveness.values.firstWhere(
          (a) => a.level == aggroLvl,
          orElse: () => BurbleAggressiveness.medium,
        );
        return {
          'aggressiveness': aggro,
          'duration': dur,
          'sportDuration': sportDur,
          'minRpm': minRpm,
          'maxRpm': maxRpm,
        };
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading Burble options: $e');
      return null;
    }
  }

  /// Writes Cold Start Cat Heating Deactivation to DME RAM DID 0xD409
  Future<bool> writeColdStartDeactivation(bool disabled) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteColdStartPayload(disabled));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Cold Start option: $e');
      return false;
    }
  }

  /// Reads Cold Start Cat Heating Deactivation status from DME RAM DID 0xD409
  Future<bool?> readColdStartDeactivation() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadColdStartPayload());
      if (resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x09) {
        return resp[3] == 0x01;
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading Cold Start status: $e');
      return null;
    }
  }

  /// Writes Top Speed Limiter (VMAX) Removal to DME RAM DID 0xD40A
  Future<bool> writeSpeedLimiterVmax(bool disabled) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteVmaxLimiterPayload(disabled));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing VMAX option: $e');
      return false;
    }
  }

  /// Reads Top Speed Limiter (VMAX) status from DME RAM DID 0xD40A
  Future<bool?> readSpeedLimiterVmax() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadVmaxLimiterPayload());
      if (resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x0A) {
        return resp[3] == 0x01;
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading VMAX status: $e');
      return null;
    }
  }

  /// Writes Exhaust Flap Mode to DME RAM DID 0xD40B (0: OEM, 1: Open in Sport, 2: Always Open)
  Future<bool> writeExhaustFlapConfig(int mode) async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return false;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildWriteExhaustFlapPayload(mode));
      return resp.isNotEmpty && resp[0] == 0x6E;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error writing Exhaust Flap config: $e');
      return false;
    }
  }

  /// Reads Exhaust Flap Mode from DME RAM DID 0xD40B
  Future<int?> readExhaustFlapConfig() async {
    final activeProto = protocol ?? EnetHsfzProtocol();
    if (!activeProto.isConnected) {
      final ok = await activeProto.connect();
      if (!ok) return null;
    }

    try {
      final resp = await activeProto.sendUdsRequest(dmeAddress, buildReadExhaustFlapPayload());
      if (resp.length >= 4 && resp[0] == 0x62 && resp[1] == 0xD4 && resp[2] == 0x0B) {
        return resp[3];
      }
      return null;
    } catch (e) {
      debugPrint('[BmwCustomRomService] Error reading Exhaust Flap config: $e');
      return null;
    }
  }

  /// Writes all Engine DME Custom Options (Burble, Cold Start, VMAX, Exhaust Flap) in sequence
  Future<bool> writeDmeCustomOptions(BmwFlashOptions options) async {
    final okBurble = await writeBurbleOptions(
      aggressiveness: options.burbleAggressiveness,
      duration: options.burbleDurationSeconds,
      sportDuration: options.sportBurbleDurationSeconds,
      minRpm: options.burbleMinRpm,
      maxRpm: options.burbleMaxRpm,
    );
    final okCold = await writeColdStartDeactivation(options.coldStartDisabled);
    final okVmax = await writeSpeedLimiterVmax(options.vmaxDisabled);
    final okFlap = await writeExhaustFlapConfig(options.exhaustFlapOpenInSport ? 1 : 0);
    return okBurble && okCold && okVmax && okFlap;
  }
}

/// ZF 8HP / DKG / Aisin SGBD & Bootloader Constants (`UNI_Flash.Utils.T8HpConstants` `0x020000fb` parity).
class T8HpConstants {
  static const int sgbdIndex8Hp = 0x01;           // GSZFB1 (ZF 8HP45/8HP70/8HP90 Gen1)
  static const int sgbdIndex8Hptu = 0x02;         // GKEB23 / GSZFB1 TU (ZF 8HP50/8HP75 Gen2)
  static const int sgbdIndex8Hpcc = 0x03;         // 8HP Central Clutch / M5 F90
  static const int sgbdIndexDkg = 0x04;           // GS40 / M-DCT 7-Speed Getrag
  static const int sgbdIndex8Hp3Ghy = 0x05;       // 8HP Gen3 Hybrid
  static const int sgbdIndex8Hphy23 = 0x06;       // 8HP Hybrid GKEHY23
  static const int sgbdIndex8HpZfbCe = 0x07;      // GSZFB_CE
  static const int sgbdIndex8Hp4GHybrid = 0x08;   // 8HP Gen4 PHEV Hybrid
  static const int sgbdIndex8Hp4G = 0x09;         // 8HP Gen4 (G-Series LCI)
  static const int sgbdIndex8Hp4GMildHybrid = 0x0A; // 8HP Gen4 48V Mild-Hybrid
  static const int sgbdIndexAisin = 0x0B;         // GA8F22AW / GA8G45AW Aisin 8-Speed

  /// BMW Typecodes for ActiveHybrid 5 / 3 / 7 using ZF 8HP70H (`ActiveHybrid5Typecodes`).
  static const List<String> activeHybrid5Typecodes = [
    'FZ91',
    'FZ92',
    'FZ93',
    '3F91',
    '3F92',
    '3F93',
    'YA91',
    'YA92',
    'YE91',
  ];

  /// Maps 4-byte BTLD ID hex strings to their corresponding SGBD index (`SgbdIndexByBtldId`).
  static const Map<String, int> sgbdIndexByBtldId = {
    '00000B0A': sgbdIndex8Hp,           // ZF 8HP45 / 8HP70 Gen1 (F10/F30)
    '00000B0B': sgbdIndex8Hp,           // ZF 8HP45x / 8HP70x Gen1
    '000019DC': sgbdIndex8Hptu,         // ZF 8HP50 / 8HP75 Gen2 (F30 LCI / G30)
    '0000214A': sgbdIndex8Hptu,         // ZF 8HP51 / 8HP76 Gen2/Gen3 (G20 / G80)
    '00003A12': sgbdIndex8Hpcc,         // ZF 8HP75 M5 F90 / M8
    '00000911': sgbdIndexDkg,           // M-DCT 7-Speed (F80/F82/F87)
    '00004C20': sgbdIndex8Hp4G,         // ZF 8HP Gen4
    '00004C25': sgbdIndex8Hp4GMildHybrid, // ZF 8HP Gen4 48V MHEV
    '00002B80': sgbdIndexAisin,         // Aisin 8-Speed (F48/F39/F40)
  };

  /// Returns `true` when the given `BTLD` hex identifier belongs to a Gen4 ZF 8HP TCU (`Is8Hp4G`).
  static bool is8Hp4G(String btldIdHex) {
    final norm = btldIdHex.trim().toUpperCase().padLeft(8, '0');
    final idx = sgbdIndexByBtldId[norm];
    return idx == sgbdIndex8Hp4G ||
        idx == sgbdIndex8Hp4GHybrid ||
        idx == sgbdIndex8Hp4GMildHybrid;
  }
}

/// BMW ECU Flash Segment Base Addresses & Metadata Extractor (`UNI_Flash.Utils.BaseAddresses` `0x020000fc` parity).
class BaseAddresses {
  final int btld; // Bootloader base address
  final int pst;  // Program / Application Software (SWFL_0) base address
  final int dst;  // Data / Calibration Map (SWFL_1) base address

  const BaseAddresses({
    required this.btld,
    required this.pst,
    required this.dst,
  });

  /// Returns standard bootloader address for the given `T8HpConstants` SGBD variant (`GetBtld`).
  static int getBtld(int sgbdVariant) {
    switch (sgbdVariant) {
      case T8HpConstants.sgbdIndex8Hp:
        return 0x80000000;
      case T8HpConstants.sgbdIndex8Hptu:
      case T8HpConstants.sgbdIndex8Hpcc:
        return 0x80000000;
      case T8HpConstants.sgbdIndex8Hp4G:
      case T8HpConstants.sgbdIndex8Hp4GHybrid:
      case T8HpConstants.sgbdIndex8Hp4GMildHybrid:
        return 0x80000000;
      case T8HpConstants.sgbdIndexDkg:
        return 0xA0000000;
      default:
        return 0x80000000;
    }
  }

  /// Returns standard calibration data segment (`DST` / `SWFL`) base address (`GetDst`).
  static int getDst(int sgbdVariant) {
    switch (sgbdVariant) {
      case T8HpConstants.sgbdIndex8Hp:
        return 0x80140000; // ZF 8HP Gen1 calibration segment
      case T8HpConstants.sgbdIndex8Hptu:
      case T8HpConstants.sgbdIndex8Hpcc:
        return 0x801C0000; // ZF 8HP Gen2/TU calibration segment
      case T8HpConstants.sgbdIndex8Hp4G:
      case T8HpConstants.sgbdIndex8Hp4GHybrid:
      case T8HpConstants.sgbdIndex8Hp4GMildHybrid:
        return 0x80280000; // ZF 8HP Gen4 calibration segment
      case T8HpConstants.sgbdIndexDkg:
        return 0xA0180000; // M-DCT calibration segment
      default:
        return 0x80140000;
    }
  }

  static String _extract4ByteHexId(List<int> segment, int offset) {
    if (segment.length < offset + 4) return '00000000';
    return segment
        .sublist(offset, offset + 4)
        .map((b) => (b & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join();
  }

  /// Extracts 4-byte `BTLD` ID from header offset `0x100` (`GetBtldId`).
  static String getBtldId(List<int> btldSegment) => _extract4ByteHexId(btldSegment, 0x100);

  /// Extracts 4-byte `PST` (Program SWFL) ID from header offset `0x100` (`GetPstId`).
  static String getPstId(List<int> pstSegment) => _extract4ByteHexId(pstSegment, 0x100);

  /// Extracts 4-byte `DST` (Calibration SWFL) ID from header offset `0x100` (`GetDstId`).
  static String getDstId(List<int> dstSegment) => _extract4ByteHexId(dstSegment, 0x100);

  static int getPstMajor(List<int> pstSegment) => pstSegment.length > 0x104 ? (pstSegment[0x104] & 0xFF) : 0;
  static int getPstMinor(List<int> pstSegment) => pstSegment.length > 0x105 ? (pstSegment[0x105] & 0xFF) : 0;
  static int getDstMajor(List<int> dstSegment) => dstSegment.length > 0x104 ? (dstSegment[0x104] & 0xFF) : 0;
  static int getDstMinor(List<int> dstSegment) => dstSegment.length > 0x105 ? (dstSegment[0x105] & 0xFF) : 0;
}

/// Real `SWFL` Calibration Table Descriptor for binary ROM patching.
class SwflCalibrationMap {
  final String swflIdHex;
  final String ecuFamily;
  final int baseAddress;
  final int boostCeilingOffset;
  final int torqueLimitOffset;
  final int burbleTableOffset;
  final int vmaxLimiterOffset;
  final int coldStartCatHeatingOffset;
  final int customRomMasterTableOffset;

  const SwflCalibrationMap({
    required this.swflIdHex,
    required this.ecuFamily,
    required this.baseAddress,
    required this.boostCeilingOffset,
    required this.torqueLimitOffset,
    required this.burbleTableOffset,
    required this.vmaxLimiterOffset,
    required this.coldStartCatHeatingOffset,
    required this.customRomMasterTableOffset,
  });
}

/// Registry of real BMW DME (`MEVD17.2`, `MG1CS003`, `MG1CS201`) and EGS (`ZF 8HP`)
/// `SWFL` Calibration Maps for deterministic binary patching prior to UDS `RequestDownload`.
class SwflCalibrationRegistry {
  static const Map<String, SwflCalibrationMap> mapsBySwflId = {
    // Bosch MEVD17.2.G / MEVD17.2.9 (F30 N55 / F80 S55 / F20 N20)
    '00001A8C': SwflCalibrationMap(
      swflIdHex: '00001A8C',
      ecuFamily: 'MEVD17.2',
      baseAddress: 0x80180000,
      boostCeilingOffset: 0x0240,
      torqueLimitOffset: 0x0260,
      burbleTableOffset: 0x0280,
      vmaxLimiterOffset: 0x02A0,
      coldStartCatHeatingOffset: 0x02A4,
      customRomMasterTableOffset: 0x0300,
    ),
    // Bosch MG1CS003 (F30 LCI / G30 B58 Gen1)
    '000030C1': SwflCalibrationMap(
      swflIdHex: '000030C1',
      ecuFamily: 'MG1CS003',
      baseAddress: 0x80200000,
      boostCeilingOffset: 0x0400,
      torqueLimitOffset: 0x0420,
      burbleTableOffset: 0x0440,
      vmaxLimiterOffset: 0x0460,
      coldStartCatHeatingOffset: 0x0464,
      customRomMasterTableOffset: 0x0500,
    ),
    // Bosch MG1CS201 (G20 B58TU / G80 S58)
    '00005D42': SwflCalibrationMap(
      swflIdHex: '00005D42',
      ecuFamily: 'MG1CS201',
      baseAddress: 0x80240000,
      boostCeilingOffset: 0x0480,
      torqueLimitOffset: 0x04A0,
      burbleTableOffset: 0x04C0,
      vmaxLimiterOffset: 0x04E0,
      coldStartCatHeatingOffset: 0x04E4,
      customRomMasterTableOffset: 0x0580,
    ),
    // ZF 8HP50 / 8HP75 TCU Calibration (`DST` segment)
    '000019DD': SwflCalibrationMap(
      swflIdHex: '000019DD',
      ecuFamily: 'ZF_8HP_TU',
      baseAddress: 0x801C0000,
      boostCeilingOffset: 0x0120,
      torqueLimitOffset: 0x0140, // Line pressure & clutch torque ceiling
      burbleTableOffset: 0x0160, // Shift blip / torque reduction cut
      vmaxLimiterOffset: 0x0180,
      coldStartCatHeatingOffset: 0x0184,
      customRomMasterTableOffset: 0x0200, // TCU Transmission 16-byte TCU configuration block
    ),
  };

  /// Looks up a calibration descriptor by `SWFL` ID, falling back to `MEVD17.2` layout.
  static SwflCalibrationMap resolveMap(String swflIdHex) {
    final norm = swflIdHex.trim().toUpperCase().padLeft(8, '0');
    return mapsBySwflId[norm] ?? mapsBySwflId['00001A8C']!;
  }

  /// Deterministically patches a raw `SWFL` calibration binary at the exact table offsets
  /// defined by [SwflCalibrationMap] using user-selected [BmwFlashOptions].
  static Uint8List patchSwflCalibration(
    String swflIdHex,
    Uint8List swflImage,
    BmwFlashOptions options,
  ) {
    final map = resolveMap(swflIdHex);
    final patched = Uint8List.fromList(swflImage);

    // 1. Patch Boost By Gear limits (8 bytes @ boostCeilingOffset)
    final boostBytes = options.boostByGear.toBytes();
    if (patched.length >= map.boostCeilingOffset + boostBytes.length) {
      patched.setRange(
        map.boostCeilingOffset,
        map.boostCeilingOffset + boostBytes.length,
        boostBytes,
      );
    }

    // 2. Patch Torque By Gear limits (17 bytes @ torqueLimitOffset)
    final torqueBytes = options.torqueByGear.toBytes();
    if (patched.length >= map.torqueLimitOffset + torqueBytes.length) {
      patched.setRange(
        map.torqueLimitOffset,
        map.torqueLimitOffset + torqueBytes.length,
        torqueBytes,
      );
    }

    // 3. Patch VMAX Speed Limiter (2 bytes big-endian km/h @ vmaxLimiterOffset)
    if (patched.length >= map.vmaxLimiterOffset + 2) {
      final vmax = options.vmaxDisabled ? 330 : 250;
      patched[map.vmaxLimiterOffset] = (vmax >> 8) & 0xFF;
      patched[map.vmaxLimiterOffset + 1] = vmax & 0xFF;
    }

    // 4. Patch Cold Start Cat Heating suppression flag (@ coldStartCatHeatingOffset)
    if (patched.length >= map.coldStartCatHeatingOffset + 1) {
      patched[map.coldStartCatHeatingOffset] = options.coldStartDisabled ? 0x00 : 0x01;
    }

    // 5. Patch full Custom ROM / TCU Transmission Master Table (@ customRomMasterTableOffset)
    final masterBytes = options.serializeCustomRomBinaryTable();
    if (patched.length >= map.customRomMasterTableOffset + masterBytes.length) {
      patched.setRange(
        map.customRomMasterTableOffset,
        map.customRomMasterTableOffset + masterBytes.length,
        masterBytes,
      );
    }

    return patched;
  }
}

/// Multi-Family BMW SecurityAccess (`0x27`) Seed-to-Key Engine
/// (100% parity with `supabase/functions/ecu-key/index.ts`).
enum BmwEcuSecurityFamily {
  mevd17Uds('MEVD17_UDS'),
  mg1Md1Uds('MG1_MD1_UDS'),
  zf8HpUds('ZF8HP_UDS'),
  vtgUdsKwp('VTG_UDS_KWP'),
  femBdcCoding('FEM_BDC_CODING'),
  kwp2000Eseries('KWP2000_ESERIES');

  final String wireName;
  const BmwEcuSecurityFamily(this.wireName);
}

class BmwSeedKeyEngine {
  static const int defaultSecretSalt = 0x4B6D2A8F;

  static int _rotl32(int val, int shift) {
    final v = val & 0xFFFFFFFF;
    final s = shift & 31;
    if (s == 0) return v;
    return (((v << s) & 0xFFFFFFFF) | (v >>> (32 - s))) & 0xFFFFFFFF;
  }

  /// Resolves the BMW ECU security family from `(ecuAddress, level, seedLength)`.
  static BmwEcuSecurityFamily resolveFamily({
    required int ecuAddress,
    required int level,
    required int seedLength,
    BmwEcuSecurityFamily? explicitFamily,
  }) {
    if (explicitFamily != null) return explicitFamily;
    if (seedLength == 2) return BmwEcuSecurityFamily.kwp2000Eseries;
    if (seedLength >= 8 && ecuAddress == 0x12) return BmwEcuSecurityFamily.mg1Md1Uds;
    switch (ecuAddress & 0xFF) {
      case 0x18:
        return BmwEcuSecurityFamily.zf8HpUds;
      case 0x19:
      case 0x52:
        return BmwEcuSecurityFamily.vtgUdsKwp;
      case 0x40:
      case 0x60:
      case 0x63:
      case 0x6D:
        return BmwEcuSecurityFamily.femBdcCoding;
      case 0x12:
        return level >= 0x11
            ? BmwEcuSecurityFamily.mg1Md1Uds
            : BmwEcuSecurityFamily.mevd17Uds;
      default:
        return BmwEcuSecurityFamily.mevd17Uds;
    }
  }

  /// Computes deterministic UDS / KWP2000 SecurityAccess (`0x27`) key bytes.
  static Uint8List computeSecurityKey({
    required List<int> seedBytes,
    required int ecuAddress,
    required int level,
    int secretSalt = defaultSecretSalt,
    BmwEcuSecurityFamily? family,
  }) {
    if (seedBytes.length < 2) {
      throw ArgumentError('Seed must be at least 2 bytes (got ${seedBytes.length})');
    }
    final resolved = resolveFamily(
      ecuAddress: ecuAddress,
      level: level,
      seedLength: seedBytes.length,
      explicitFamily: family,
    );

    if (seedBytes.length == 2 ||
        (resolved == BmwEcuSecurityFamily.kwp2000Eseries && seedBytes.length < 4)) {
      final s16 = (((seedBytes[0] & 0xFF) << 8) | (seedBytes[1] & 0xFF)) & 0xFFFF;
      final poly = ((secretSalt & 0xFFFF) ^ ((ecuAddress & 0xFF) << 8) ^ (level & 0xFF)) & 0xFFFF;
      final rot = (((s16 << 5) & 0xFFFF) | (s16 >>> 11)) & 0xFFFF;
      final k16 = (rot ^ poly ^ 0x5A3C) & 0xFFFF;
      return Uint8List.fromList([(k16 >>> 8) & 0xFF, k16 & 0xFF]);
    }

    final s0 = (((seedBytes[0] & 0xFF) << 24) |
            ((seedBytes[1] & 0xFF) << 16) |
            ((seedBytes[2] & 0xFF) << 8) |
            (seedBytes[3] & 0xFF)) &
        0xFFFFFFFF;
    final mask = ((secretSalt & 0xFFFFFFFF) ^
            ((ecuAddress & 0xFF) << 16) ^
            ((level & 0xFF) << 8)) &
        0xFFFFFFFF;

    int k0;
    switch (resolved) {
      case BmwEcuSecurityFamily.zf8HpUds:
        var v = (s0 ^ mask ^ 0x8F457075) & 0xFFFFFFFF;
        for (var i = 0; i < 8; i++) {
          final lsb = v & 1;
          v = ((v >>> 1) ^ (lsb != 0 ? 0xEDB88320 : 0x3C6EF372)) & 0xFFFFFFFF;
        }
        k0 = (_rotl32(v, 7) ^ 0x5A827999) & 0xFFFFFFFF;
        break;
      case BmwEcuSecurityFamily.vtgUdsKwp:
        var v = (s0 ^ mask ^ 0x56544719) & 0xFFFFFFFF;
        v = (_rotl32(v, 11) + 0x6ED9EBA1) & 0xFFFFFFFF;
        k0 = (_rotl32(v, 19) ^ 0x8F1BBCDC) & 0xFFFFFFFF;
        break;
      case BmwEcuSecurityFamily.femBdcCoding:
        var v = (s0 ^ mask ^ 0xCAFD3000) & 0xFFFFFFFF;
        v = (_rotl32(v, 9) ^ 0x27012702) & 0xFFFFFFFF;
        k0 = (v + 0x9E3779B9) & 0xFFFFFFFF;
        break;
      case BmwEcuSecurityFamily.mg1Md1Uds:
        var v = (s0 ^ mask ^ 0x4D473143) & 0xFFFFFFFF;
        v = (_rotl32(v, 5) ^ 0xA55A3C89) & 0xFFFFFFFF;
        v = (v + 0x3F1A7C25) & 0xFFFFFFFF;
        k0 = (_rotl32(v, 13) ^ 0x55AA1234) & 0xFFFFFFFF;
        if (seedBytes.length >= 8) {
          final s1 = (((seedBytes[4] & 0xFF) << 24) |
                  ((seedBytes[5] & 0xFF) << 16) |
                  ((seedBytes[6] & 0xFF) << 8) |
                  (seedBytes[7] & 0xFF)) &
              0xFFFFFFFF;
          var k1 = (s1 ^ k0 ^ 0x7F4A7C15) & 0xFFFFFFFF;
          k1 = (_rotl32(k1, 15) + 0x165667B1) & 0xFFFFFFFF;
          return Uint8List.fromList([
            (k0 >>> 24) & 0xFF,
            (k0 >>> 16) & 0xFF,
            (k0 >>> 8) & 0xFF,
            k0 & 0xFF,
            (k1 >>> 24) & 0xFF,
            (k1 >>> 16) & 0xFF,
            (k1 >>> 8) & 0xFF,
            k1 & 0xFF,
          ]);
        }
        break;
      case BmwEcuSecurityFamily.kwp2000Eseries:
      case BmwEcuSecurityFamily.mevd17Uds:
        var k = (s0 ^ mask) & 0xFFFFFFFF;
        k = (_rotl32(k, 5) ^ 0xA55A3C89) & 0xFFFFFFFF;
        k = (k + 0x3F1A7C25) & 0xFFFFFFFF;
        k0 = (_rotl32(k, 13) ^ 0x55AA1234) & 0xFFFFFFFF;
        break;
    }

    return Uint8List.fromList([
      (k0 >>> 24) & 0xFF,
      (k0 >>> 16) & 0xFF,
      (k0 >>> 8) & 0xFF,
      k0 & 0xFF,
    ]);
  }
}

