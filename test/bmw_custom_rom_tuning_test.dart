import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_custom_rom_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_options.dart';

void main() {
  group('Bootmod3 & MHD Multimap Slot Architecture', () {
    test('Map slot profiles have correct IDs, RPM indications, and octane ratings', () {
      expect(CustomRomSlot.slot1.id, equals(1));
      expect(CustomRomSlot.slot1.clusterTachRpm, equals(1000));
      expect(CustomRomSlot.slot1.octaneRating, contains('91'));

      expect(CustomRomSlot.slot2.id, equals(2));
      expect(CustomRomSlot.slot2.clusterTachRpm, equals(2000));
      expect(CustomRomSlot.slot2.octaneRating, contains('93'));

      expect(CustomRomSlot.slot3.id, equals(3));
      expect(CustomRomSlot.slot3.clusterTachRpm, equals(3000));
      expect(CustomRomSlot.slot3.octaneRating, contains('Flex'));

      expect(CustomRomSlot.slot4.id, equals(4));
      expect(CustomRomSlot.slot4.clusterTachRpm, equals(4000));
      expect(CustomRomSlot.slot4.description, contains('30 km/h'));

      // Fallback
      expect(CustomRomSlot.fromId(99), equals(CustomRomSlot.slot1));
    });

    test('Generates correct UDS payloads for Slot Read, Write, and Routine Activation', () {
      final readPayload = BmwCustomRomService.buildReadSlotPayload();
      expect(readPayload, equals([0x22, 0xD4, 0x00]));

      final writeSlot2 = BmwCustomRomService.buildWriteSlotPayload(2);
      expect(writeSlot2, equals([0x2E, 0xD4, 0x00, 0x02]));

      final writeSlot3 = BmwCustomRomService.buildWriteSlotPayload(3);
      expect(writeSlot3, equals([0x2E, 0xD4, 0x00, 0x03]));

      final routineSlot3 = BmwCustomRomService.buildRoutineSlotPayload(3);
      expect(routineSlot3, equals([0x31, 0x01, 0x30, 0x01, 0x03]));
    });

    test('Generates cruise RES button trigger and cluster tachometer indication payloads', () {
      final resPayload = BmwCustomRomService.buildCruiseResTriggerPayload(targetSlot: 2);
      expect(resPayload, equals([0x31, 0x01, 0xD4, 0x02, 0x02]));

      final tachPayload = BmwCustomRomService.buildTachIndicationPayload(3000);
      expect(tachPayload, equals([0x2F, 0xD4, 0x02, 0x03, 0x0B, 0xB8]));
    });
  });

  group('FlexFuel Real-Time Blending & CAN 0x4F0 Decoding', () {
    test('Calculates interpolated Boost Scalar and Timing Advance accurately', () {
      expect(FlexFuelData.calculateBoostScalar(10.0), equals(1.0));
      expect(FlexFuelData.calculateTimingAdvance(10.0), equals(0.0));
      expect(FlexFuelData.calculateBoostScalar(5.0), equals(1.0));
      expect(FlexFuelData.calculateTimingAdvance(0.0), equals(0.0));

      expect(FlexFuelData.calculateBoostScalar(85.0), equals(1.35));
      expect(FlexFuelData.calculateTimingAdvance(85.0), equals(5.5));
      expect(FlexFuelData.calculateBoostScalar(90.0), equals(1.35));

      expect(FlexFuelData.calculateBoostScalar(47.5), closeTo(1.175, 0.001));
      expect(FlexFuelData.calculateTimingAdvance(47.5), closeTo(2.75, 0.01));
    });

    test('Decodes DME RAM DID 0xD410 UDS response payload', () {
      final udsResponse = [0x62, 0xD4, 0x10, 0x28, 0x44];
      final data = FlexFuelData.fromUdsResponse(udsResponse);

      expect(data.ethanolPercent, equals(40.0));
      expect(data.fuelTempCelsius, equals(28.0));
      expect(data.isSensorValid, isTrue);
      expect(data.boostScalar, greaterThan(1.0));
      expect(data.timingAdvanceDeg, greaterThan(0.0));
    });

    test('Decodes Aftermarket CAN Broadcast message 0x4F0 frame', () {
      final canFrame = [0x3C, 0x3E, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00];
      final flexData = FlexFuelData.fromCanFrame(0x4F0, canFrame);

      expect(flexData.ethanolPercent, equals(60.0));
      expect(flexData.fuelTempCelsius, equals(22.0));
      expect(flexData.isSensorValid, isTrue);

      expect(
        () => FlexFuelData.fromCanFrame(0x123, canFrame),
        throwsArgumentError,
      );
    });
  });

  group('1. Rolling Anti-Lag (RAL) Binary Serialization & UDS', () {
    test('Encodes RollingAntiLagConfig into DID 0xD420 byte representation', () {
      final config = RollingAntiLagConfig(
        enabled: true,
        boostTargetPsi: 16.5,
        maxDurationSeconds: 3.5,
        ignitionRetardDeg: -15.0,
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(4));
      expect(bytes[0], equals(0x01)); // Enabled
      expect(bytes[1], equals(165)); // 16.5 PSI * 10
      expect(bytes[2], equals(35)); // 3.5s * 10
      expect(bytes[3], equals(150)); // |-15.0°| * 10

      final udsPayload = BmwCustomRomService.buildWriteAntiLagPayload(config);
      expect(udsPayload, equals([0x2E, 0xD4, 0x20, 0x01, 165, 35, 150]));
    });

    test('Builds UDS RoutineControl 0xD421 payload for Cruise Rocker trigger', () {
      final routinePayload = BmwCustomRomService.buildTriggerAntiLagRoutinePayload(
        activate: true,
        boostTargetPsi: 18.0,
        durationSeconds: 2.5,
        retardDeg: -18.0,
      );
      expect(routinePayload, equals([0x31, 0x01, 0xD4, 0x21, 0x01, 180, 25, 180]));
    });
  });

  group('2. Boost By Gear & Torque By Gear Calibration', () {
    test('Encodes BoostByGearConfig into 9 bytes for DID 0xD430', () {
      final config = BoostByGearConfig(
        enabled: true,
        gearLimitsPsi: [12.0, 15.0, 18.0, 21.0, 24.0, 24.0, 24.0, 24.0],
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(9));
      expect(bytes[0], equals(0x01)); // Enabled
      expect(bytes[1], equals(24)); // 12.0 * 2
      expect(bytes[2], equals(30)); // 15.0 * 2
      expect(bytes[3], equals(36)); // 18.0 * 2

      final uds = BmwCustomRomService.buildWriteBoostByGearPayload(config);
      expect(uds.sublist(0, 4), equals([0x2E, 0xD4, 0x30, 0x01]));
    });

    test('Encodes TorqueByGearConfig into 17 bytes (16-bit big-endian) for DID 0xD431', () {
      final config = TorqueByGearConfig(
        enabled: true,
        gearLimitsNm: [450, 520, 620, 750, 800, 850, 900, 950],
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(17));
      expect(bytes[0], equals(0x01)); // Enabled

      // Gear 1: 450 Nm -> 0x01C2
      expect(bytes[1], equals(0x01));
      expect(bytes[2], equals(0xC2));

      // Gear 2: 520 Nm -> 0x0208
      expect(bytes[3], equals(0x02));
      expect(bytes[4], equals(0x08));
    });
  });

  group('3. HPFP Flow Scaling Profiles', () {
    test('All HPFP profiles have valid flow scalars and rail pressure limits', () {
      for (final profile in HpfpProfile.values) {
        expect(profile.flowScalar, greaterThanOrEqualTo(1.0));
        expect(profile.maxPressureBar, inInclusiveRange(200, 250));

        final calibBytes = profile.toCalibrationBytes();
        expect(calibBytes.length, equals(5));
        expect(calibBytes[0], equals(profile.id));

        final scalarInt = (calibBytes[1] << 8) | calibBytes[2];
        expect(scalarInt, equals((profile.flowScalar * 1000).toInt()));

        final pressureInt = (calibBytes[3] << 8) | calibBytes[4];
        expect(pressureInt, equals(profile.maxPressureBar));
      }
    });

    test('Dorch Stage 2 has correct scalar and rail pressure', () {
      const dorch2 = HpfpProfile.dorchStage2;
      expect(dorch2.flowScalar, equals(1.68));
      expect(dorch2.maxPressureBar, equals(250));

      final bytes = dorch2.toCalibrationBytes();
      expect(bytes, equals([
        dorch2.id,
        0x06, 0x90, // 1680
        0x00, 0xFA, // 250
      ]));
    });
  });

  group('4. TMAP Sensor Calibration Maps', () {
    test('TMAP sensors have valid voltage curves and binary calibration', () {
      for (final tmap in TmapSensorType.values) {
        final bytes = tmap.toCalibrationBytes();
        expect(bytes.length, equals(5));
        expect(bytes[0], equals(tmap.id));
      }

      // N20 3.5 Bar: Gradient 82.5 kPa/V -> 825 (0x0339)
      const n20 = TmapSensorType.n20_3_5Bar;
      expect(n20.maxBar, equals(3.5));
      expect(n20.gradientKpaPerVolt, equals(82.5));

      final writeTmap = BmwCustomRomService.buildWriteTmapPayload(
        TmapSensorType.n20_3_5Bar,
        TmapSensorType.n20_3_5Bar,
      );
      expect(writeTmap.length, equals(13)); // 0x2E 0xD4 0x45 + 5 + 5
      expect(writeTmap.sublist(0, 3), equals([0x2E, 0xD4, 0x45]));
    });
  });

  group('5. GTS Startup Roar / Start Bark', () {
    test('Encodes GTS startup roar duration and flare RPM', () {
      final config = GtsStartupRoarConfig(
        enabled: true,
        durationMs: 800,
        flareRpmTarget: 1900,
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(5));
      expect(bytes[0], equals(0x01)); // Enabled

      // Duration: 800 -> 0x0320
      expect((bytes[1] << 8) | bytes[2], equals(800));

      // Flare RPM: 1900 -> 0x076C
      expect((bytes[3] << 8) | bytes[4], equals(1900));

      final uds = BmwCustomRomService.buildWriteGtsStartupRoarPayload(config);
      expect(uds.sublist(0, 3), equals([0x2E, 0xD4, 0x50]));
    });
  });

  group('6. Wastegate Rattle Fix (PWG Offset)', () {
    test('Builds UDS payload for PWG offset (-20% to +20%)', () {
      final payloadMinus10 = BmwCustomRomService.buildWriteWastegateRattlePayload(true, -10);
      expect(payloadMinus10.length, equals(5));
      expect(payloadMinus10[0], equals(0x2E));
      expect(payloadMinus10[1], equals(0xD4));
      expect(payloadMinus10[2], equals(0x55));
      expect(payloadMinus10[3], equals(0x01)); // Enabled
      expect(payloadMinus10[4], equals((-10) & 0xFF)); // Signed offset
    });
  });

  group('7. Transmission Upshift Shift Brap', () {
    test('Encodes Shift Brap aggressiveness and duration', () {
      final config = ShiftBrapConfig(
        enabled: true,
        aggressiveness: 3,
        durationMs: 150,
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(4));
      expect(bytes[0], equals(0x01));
      expect(bytes[1], equals(3));
      expect((bytes[2] << 8) | bytes[3], equals(150));

      final routine = BmwCustomRomService.buildTestShiftBrapRoutinePayload();
      expect(routine, equals([0x31, 0x01, 0xD4, 0x61, 0x01]));
    });
  });

  group('8. Knock CEL Alert Notification', () {
    test('Encodes knock retard threshold (>3.0°) and flash rate', () {
      final config = KnockCelConfig(
        enabled: true,
        timingThresholdDeg: 3.0,
        flashRateHz: 4,
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(4));
      expect(bytes[0], equals(0x01));
      expect((bytes[1] << 8) | bytes[2], equals(30)); // 3.0 * 10
      expect(bytes[3], equals(4));

      final testPulse = BmwCustomRomService.buildTestKnockCelRoutinePayload(flashCount: 4, rateHz: 4);
      expect(testPulse, equals([0x31, 0x01, 0xD4, 0x66, 0x04, 0x04]));
    });
  });

  group('9. Catless Downpipe CEL Suppression Mask', () {
    test('Encodes 32-bit CARB suppression mask for 180001, 12B104, P0420', () {
      final config = CatlessDtcSuppressionConfig(
        enabled: true,
        suppressedCodes: ['180001', '12B104', '180002', 'P0420', 'P0430'],
        suppressionMaskBitfield: 0x0000001F,
      );

      final bytes = config.toBytes();
      expect(bytes.length, equals(5));
      expect(bytes[0], equals(0x01));
      expect(bytes.sublist(1, 5), equals([0x00, 0x00, 0x00, 0x1F]));

      final uds = BmwCustomRomService.buildWriteCatlessSuppressionPayload(config);
      expect(uds.sublist(0, 3), equals([0x2E, 0xD4, 0x70]));
    });
  });

  group('10. Master Custom ROM Binary Table Serialization', () {
    test('Serializes full calibration vector with magic header BM3MHD', () {
      final options = BmwFlashOptions(
        stage: OtsMapStage.stage2_93,
        hpfp: HpfpProfile.dorchStage2,
        manifoldTMAP: TmapSensorType.n20_3_5Bar,
        preThrottleTMAPSensor: TmapSensorType.n20_3_5Bar,
        wastegateRattleFix: true,
        wastegateDutyCycleOffsetPercent: -10,
      );

      final binaryTable = options.serializeCustomRomBinaryTable();
      expect(binaryTable.length, greaterThan(60));

      // Verify Magic Header 'FXAI\x01\x00\x00\x00'
      expect(binaryTable.sublist(0, 8), equals([0x46, 0x58, 0x41, 0x49, 0x01, 0x00, 0x00, 0x00]));
    });
  });
}
