import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_custom_rom_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_options.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_vtg_manager.dart';

void main() {
  group('1. DME Engine Custom Options (Payload Builders & Options)', () {
    test('Builds correct Burble read payload', () {
      final payload = BmwCustomRomService.buildReadBurblePayload();
      expect(payload, equals([0x22, 0xD4, 0x08]));
    });

    test('Builds correct Burble write payload with RPM limits and clamping', () {
      final payload = BmwCustomRomService.buildWriteBurblePayload(
        aggressiveness: BurbleAggressiveness.hard,
        duration: 2.5,
        sportDuration: 3.5,
        minRpm: 1800,
        maxRpm: 6000,
      );

      // 0x2E, 0xD4, 0x08, aggressiveness(4), duration(25), sportDuration(35), minRpm(1800=0x0708), maxRpm(6000=0x1770)
      expect(payload, equals([
        0x2E, 0xD4, 0x08,
        0x04,
        25,
        35,
        0x07, 0x08,
        0x17, 0x70,
      ]));
    });

    test('Clamps Burble parameters to safe ranges', () {
      final payload = BmwCustomRomService.buildWriteBurblePayload(
        aggressiveness: BurbleAggressiveness.off,
        duration: 99.0, // should clamp to 5.0 -> 50
        sportDuration: -10.0, // should clamp to 0.0 -> 0
        minRpm: 500, // should clamp to 1000 -> 0x03E8
        maxRpm: 9000, // should clamp to 7500 -> 0x1D4C
      );

      expect(payload, equals([
        0x2E, 0xD4, 0x08,
        0x00,
        50,
        0,
        0x03, 0xE8,
        0x1D, 0x4C,
      ]));
    });

    test('Builds correct Cold Start Cat Heating read and write payloads', () {
      final readPayload = BmwCustomRomService.buildReadColdStartPayload();
      expect(readPayload, equals([0x22, 0xD4, 0x09]));

      final writeDisable = BmwCustomRomService.buildWriteColdStartPayload(true);
      expect(writeDisable, equals([0x2E, 0xD4, 0x09, 0x01]));

      final writeEnable = BmwCustomRomService.buildWriteColdStartPayload(false);
      expect(writeEnable, equals([0x2E, 0xD4, 0x09, 0x00]));
    });

    test('Builds correct VMAX Speed Limiter read and write payloads', () {
      final readPayload = BmwCustomRomService.buildReadVmaxLimiterPayload();
      expect(readPayload, equals([0x22, 0xD4, 0x0A]));

      final writeRemove = BmwCustomRomService.buildWriteVmaxLimiterPayload(true);
      expect(writeRemove, equals([0x2E, 0xD4, 0x0A, 0x01]));

      final writeKeep = BmwCustomRomService.buildWriteVmaxLimiterPayload(false);
      expect(writeKeep, equals([0x2E, 0xD4, 0x0A, 0x00]));
    });

    test('Builds correct Exhaust Flap read and write payloads', () {
      final readPayload = BmwCustomRomService.buildReadExhaustFlapPayload();
      expect(readPayload, equals([0x22, 0xD4, 0x0B]));

      final writeOem = BmwCustomRomService.buildWriteExhaustFlapPayload(0);
      expect(writeOem, equals([0x2E, 0xD4, 0x0B, 0x00]));

      final writeSport = BmwCustomRomService.buildWriteExhaustFlapPayload(1);
      expect(writeSport, equals([0x2E, 0xD4, 0x0B, 0x01]));

      final writeAlwaysOpen = BmwCustomRomService.buildWriteExhaustFlapPayload(2);
      expect(writeAlwaysOpen, equals([0x2E, 0xD4, 0x0B, 0x02]));
    });

    test('BmwFlashOptions includes burble RPM limits in JSON serialization and copyWith', () {
      final options = BmwFlashOptions(
        burbleAggressiveness: BurbleAggressiveness.hard,
        burbleDurationSeconds: 2.2,
        sportBurbleDurationSeconds: 3.8,
        burbleMinRpm: 1700,
        burbleMaxRpm: 5800,
        coldStartDisabled: true,
        vmaxDisabled: true,
        exhaustFlapOpenInSport: true,
      );

      final json = options.toJson();
      expect(json['burbleMinRpm'], equals(1700));
      expect(json['burbleMaxRpm'], equals(5800));
      expect(json['coldStartDisabled'], isTrue);
      expect(json['vmaxDisabled'], isTrue);

      final restored = BmwFlashOptions.fromJson(json);
      expect(restored.burbleMinRpm, equals(1700));
      expect(restored.burbleMaxRpm, equals(5800));
      expect(restored.coldStartDisabled, isTrue);
      expect(restored.vmaxDisabled, isTrue);
      expect(restored.exhaustFlapOpenInSport, isTrue);

      final copied = restored.copyWith(burbleMinRpm: 1900, burbleMaxRpm: 6200);
      expect(copied.burbleMinRpm, equals(1900));
      expect(copied.burbleMaxRpm, equals(6200));
    });

    test('Serializes 14-byte Engine Custom Options block into Master Table', () {
      final options = BmwFlashOptions(
        burbleAggressiveness: BurbleAggressiveness.hard, // 4
        burbleDurationSeconds: 2.0, // 20
        sportBurbleDurationSeconds: 3.5, // 35
        burbleMinRpm: 1600, // 0x0640
        burbleMaxRpm: 5600, // 0x15E0
        coldStartDisabled: true, // 1
        vmaxDisabled: true, // 1
        exhaustFlapOpenInSport: true, // 1
        linearThrottle: false, // 0
      );

      final masterTable = options.serializeCustomRomBinaryTable();
      expect(masterTable.length, greaterThan(70));

      // TCU block is last 16 bytes, Engine Custom Options is the 14 bytes right before it
      final engineOptionsOffset = masterTable.length - 16 - 14;
      final engineBytes = masterTable.sublist(engineOptionsOffset, engineOptionsOffset + 14);

      // Byte 0: burble aggressiveness (4)
      expect(engineBytes[0], equals(4));
      // Byte 1: burble duration tenths (20)
      expect(engineBytes[1], equals(20));
      // Byte 2: sport duration tenths (35)
      expect(engineBytes[2], equals(35));
      // Bytes 3-4: min RPM (1600 = 0x0640)
      expect(engineBytes[3], equals(0x06));
      expect(engineBytes[4], equals(0x40));
      // Bytes 5-6: max RPM (5600 = 0x15E0)
      expect(engineBytes[5], equals(0x15));
      expect(engineBytes[6], equals(0xE0));
      // Byte 7: cold start cat heating disabled (1)
      expect(engineBytes[7], equals(1));
      // Byte 8: vmax removed (1)
      expect(engineBytes[8], equals(1));
      // Byte 9: exhaust flap open in sport (1)
      expect(engineBytes[9], equals(1));
      // Byte 10: linear throttle (0)
      expect(engineBytes[10], equals(0));
    });
  });

  group('2. TCU Transmission Extended Calibration Parameters', () {
    test('BmwTcuOptions supports all factory and motorsport parameters', () {
      final tcu = BmwTcuOptions(
        linePressureBump: true,
        customLaunchControlEnabled: true,
        launchRpm: 3200,
        launchBoostPsi: 12.0,
        torquePunch: 4,
        maxShiftRpm: 7200,
        kickdownManualDisabled: true,
        takeOffIn2ndGear: true,
        trueManualMode: true,
        gearDisplayKombi: true,
        torqueLimitsPerGearRemoved: true,
        standstillDecouplingDisabled: true,
        transmissionWarmupDisabled: true,
        dragRaceMode: true,
        dragRaceActivationThreshold: 3500,
        brakeBoostProtection: true,
        brakeBoostProtectionValue: 18.5,
        coastingModeDisabled: true,
        disableObdAlarm: true,
        disableTempMonitoring: true,
        customCreepDisabled: true,
        valetModeEnabled: false,
        ignitionCutShifting: true,
      );

      final bytes = tcu.toBytes();
      expect(bytes.length, equals(16));

      // Test copyWith and JSON round-trip
      final json = tcu.toJson();
      final restored = BmwTcuOptions.fromJson(json);
      expect(restored.dragRaceMode, isTrue);
      expect(restored.dragRaceActivationThreshold, equals(3500));
      expect(restored.brakeBoostProtection, isTrue);
      expect(restored.brakeBoostProtectionValue, equals(18.5));
      expect(restored.coastingModeDisabled, isTrue);
      expect(restored.disableObdAlarm, isTrue);
      expect(restored.disableTempMonitoring, isTrue);
      expect(restored.customCreepDisabled, isTrue);
      expect(restored.ignitionCutShifting, isTrue);
    });
  });

  group('3. xDrive VTG Transfer Case Controller', () {
    test('XDriveMode enum returns accurate factory titles and descriptions', () {
      expect(XDriveMode.rwd.title, contains('100% RWD'));
      expect(XDriveMode.stockAwd.title, contains('Stock AWD'));
      expect(XDriveMode.sportAwd.title, contains('Sport AWD'));
      expect(XDriveMode.snowAwd.title, contains('50:50 Lock'));
      expect(XDriveMode.custom.title, contains('Custom AWD'));

      expect(XDriveMode.rwd.subtitle, contains('Clutch fully open'));
      expect(XDriveMode.stockAwd.subtitle, contains('Factory OEM'));
      expect(XDriveMode.sportAwd.subtitle, contains('30:70'));
      expect(XDriveMode.snowAwd.subtitle, contains('50:50'));
    });

    test('VtgTelemetryData handles initial values and copyWith properly', () {
      final initial = VtgTelemetryData.initial();
      expect(initial.frontTorquePercent, equals(40.0));
      expect(initial.rearTorquePercent, equals(60.0));
      expect(initial.clutchTemperatureC, equals(28.0));
      expect(initial.clutchTorqueNm, equals(0.0));

      final updated = initial.copyWith(
        frontTorquePercent: 20.0,
        rearTorquePercent: 80.0,
        clutchTemperatureC: 45.0,
        clutchTorqueNm: 350.0,
      );

      expect(updated.frontTorquePercent, equals(20.0));
      expect(updated.rearTorquePercent, equals(80.0));
      expect(updated.clutchTemperatureC, equals(45.0));
      expect(updated.clutchTorqueNm, equals(350.0));
    });

    test('BmwVtgManager has correct ECU addresses and UDS DIDs', () {
      expect(BmwVtgManager.vtgAddress, equals(0x19));
      expect(BmwVtgManager.dscAddress, equals(0x29));
      expect(BmwVtgManager.dmeAddress, equals(0x12));

      expect(BmwVtgManager.didClutchControl, equals(0x4100));
      expect(BmwVtgManager.routineWorkClutchWearReset, equals(0xA101));
      expect(BmwVtgManager.didTorqueFrontRatio, equals(0xD030));
      expect(BmwVtgManager.didTorqueRearRatio, equals(0xD031));
      expect(BmwVtgManager.didClutchTemperature, equals(0xD032));
      expect(BmwVtgManager.didClutchTorqueNm, equals(0xD033));
    });

    test('Custom clutch percent maps proportionally from 0-100% to 0-127 clamp bytes', () {
      // 0% -> 0
      int byte0 = ((0.0 / 100.0) * 127.0).round().clamp(0, 127);
      expect(byte0, equals(0x00));

      // 20% -> 25 (~0x19)
      int byte20 = ((20.0 / 100.0) * 127.0).round().clamp(0, 127);
      expect(byte20, equals(25));

      // 50% -> 64 (0x40)
      int byte50 = ((50.0 / 100.0) * 127.0).round().clamp(0, 127);
      expect(byte50, equals(64));

      // 100% -> 127 (0x7F)
      int byte100 = ((100.0 / 100.0) * 127.0).round().clamp(0, 127);
      expect(byte100, equals(0x7F));
    });
  });
}
