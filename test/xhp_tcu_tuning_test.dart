import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_options.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_custom_rom_service.dart';

void main() {
  group('ZF 8HP / 6HP TCU Transmission Tuning Options', () {
    test('Default values match factory transmission spec', () {
      const options = BmwTcuOptions();

      expect(options.linePressureBump, isFalse);
      expect(options.customLaunchControlEnabled, isFalse);
      expect(options.launchRpm, equals(3200));
      expect(options.launchBoostPsi, equals(10.0));
      expect(options.torquePunch, equals(3));
      expect(options.kickdownManualDisabled, isFalse);
      expect(options.takeOffIn2ndGear, isFalse);
      expect(options.trueManualMode, isFalse);
      expect(options.throttleBlipAggressiveness, equals(100));
      expect(options.gearDisplayKombi, isTrue);
      expect(options.maxShiftRpm, equals(7000));
      expect(options.torqueLimitsPerGearRemoved, isFalse);
      expect(options.standstillDecouplingDisabled, isFalse);
      expect(options.transmissionWarmupDisabled, isFalse);
      expect(options.shiftSpeed, equals(TcuShiftSpeed.sport));
    });

    test('Serializes to exactly 16 bytes for UDS DID 0xD440', () {
      const defaultOptions = BmwTcuOptions();
      final defaultBytes = defaultOptions.toBytes();

      expect(defaultBytes.length, equals(16));
      expect(defaultBytes[0] & 0x20, isNonZero); // gearDisplayKombi bit 5

      final customOptions = BmwTcuOptions(
        linePressureBump: true,
        customLaunchControlEnabled: true,
        launchRpm: 3500,
        launchBoostPsi: 12.5,
        torquePunch: 5,
        kickdownManualDisabled: true,
        takeOffIn2ndGear: true,
        trueManualMode: true,
        throttleBlipAggressiveness: 130,
        gearDisplayKombi: true,
        maxShiftRpm: 7200,
        torqueLimitsPerGearRemoved: true,
        standstillDecouplingDisabled: true,
        transmissionWarmupDisabled: true,
        shiftSpeed: TcuShiftSpeed.dragRace,
      );

      final customBytes = customOptions.toBytes();
      expect(customBytes.length, equals(16));

      // Byte 0: Bitfield 1
      // Bit 0: linePressureBump (0x01)
      // Bit 1: customLaunchControl (0x02)
      // Bit 2: kickdownManualDisabled (0x04)
      // Bit 3: takeOffIn2ndGear (0x08)
      // Bit 4: trueManualMode (0x10)
      // Bit 5: gearDisplayKombi (0x20)
      // Bit 6: torqueLimitsPerGearRemoved (0x40)
      // Bit 7: standstillDecouplingDisabled (0x80)
      expect(customBytes[0], equals(0xFF));

      // Byte 1: Bitfield 2 (warmup=0x01) | shiftSpeed(dragRace=3 -> 0x06) | torquePunch(5 -> 0x50) = 0x57
      expect(customBytes[1], equals(0x57));

      // Bytes 2-3: 3500 RPM -> 0x0DAC
      expect(customBytes[2], equals((3500 >> 8) & 0xFF));
      expect(customBytes[3], equals(3500 & 0xFF));

      // Byte 4: 12.5 PSI * 10 -> 125 -> 0x7D
      expect(customBytes[4], equals(125));

      // Byte 5: Throttle blip 130%
      expect(customBytes[5], equals(130));

      // Bytes 6-7: 7200 RPM -> 0x1C20
      expect(customBytes[6], equals((7200 >> 8) & 0xFF));
      expect(customBytes[7], equals(7200 & 0xFF));

      // Bytes 8-15: Padding
      for (int i = 8; i < 16; i++) {
        expect(customBytes[i], equals(0x00));
      }
    });

    test('Round-trip binary serialization (toBytes -> fromBytes) is lossless', () {
      final original = BmwTcuOptions(
        linePressureBump: true,
        customLaunchControlEnabled: true,
        launchRpm: 2800,
        launchBoostPsi: 8.5,
        torquePunch: 4,
        kickdownManualDisabled: true,
        takeOffIn2ndGear: true,
        trueManualMode: true,
        throttleBlipAggressiveness: 115,
        gearDisplayKombi: false,
        maxShiftRpm: 6800,
        torqueLimitsPerGearRemoved: true,
        standstillDecouplingDisabled: true,
        transmissionWarmupDisabled: true,
        shiftSpeed: TcuShiftSpeed.race,
      );

      final bytes = original.toBytes();
      final restored = BmwTcuOptions.fromBytes(bytes);

      expect(restored.linePressureBump, equals(original.linePressureBump));
      expect(restored.customLaunchControlEnabled, equals(original.customLaunchControlEnabled));
      expect(restored.launchRpm, equals(original.launchRpm));
      expect(restored.launchBoostPsi, closeTo(original.launchBoostPsi, 0.05));
      expect(restored.torquePunch, equals(original.torquePunch));
      expect(restored.kickdownManualDisabled, equals(original.kickdownManualDisabled));
      expect(restored.takeOffIn2ndGear, equals(original.takeOffIn2ndGear));
      expect(restored.trueManualMode, equals(original.trueManualMode));
      expect(restored.throttleBlipAggressiveness, equals(original.throttleBlipAggressiveness));
      expect(restored.gearDisplayKombi, equals(original.gearDisplayKombi));
      expect(restored.maxShiftRpm, equals(original.maxShiftRpm));
      expect(restored.torqueLimitsPerGearRemoved, equals(original.torqueLimitsPerGearRemoved));
      expect(restored.standstillDecouplingDisabled, equals(original.standstillDecouplingDisabled));
      expect(restored.transmissionWarmupDisabled, equals(original.transmissionWarmupDisabled));
      expect(restored.shiftSpeed, equals(original.shiftSpeed));
    });

    test('fromBytes throws ArgumentError if bytes length is less than 16', () {
      expect(() => BmwTcuOptions.fromBytes([0x01, 0x02]), throwsArgumentError);
    });

    test('copyWith updates individual fields correctly', () {
      const initial = BmwTcuOptions();
      final modified = initial.copyWith(
        linePressureBump: true,
        launchRpm: 4000,
        shiftSpeed: TcuShiftSpeed.dragRace,
      );

      expect(modified.linePressureBump, isTrue);
      expect(modified.launchRpm, equals(4000));
      expect(modified.shiftSpeed, equals(TcuShiftSpeed.dragRace));
      // Preserved defaults
      expect(modified.customLaunchControlEnabled, isFalse);
      expect(modified.gearDisplayKombi, isTrue);
      expect(modified.torquePunch, equals(3));
    });

    test('toJson and fromJson serialization works accurately', () {
      final options = BmwTcuOptions(
        linePressureBump: true,
        launchRpm: 3600,
        shiftSpeed: TcuShiftSpeed.race,
      );

      final json = options.toJson();
      expect(json['linePressureBump'], isTrue);
      expect(json['launchRpm'], equals(3600));
      expect(json['shiftSpeed'], equals('race'));

      final fromJson = BmwTcuOptions.fromJson(json);
      expect(fromJson.linePressureBump, isTrue);
      expect(fromJson.launchRpm, equals(3600));
      expect(fromJson.shiftSpeed, equals(TcuShiftSpeed.race));
    });
  });

  group('BmwFlashOptions TCU Integration', () {
    test('BmwFlashOptions default has TCU options and copyWith works', () {
      final flashOpts = BmwFlashOptions();
      expect(flashOpts.tcuOptions.gearDisplayKombi, isTrue);
      expect(flashOpts.tcuOptions.launchRpm, equals(3200));

      final updated = flashOpts.copyWith(
        tcuOptions: flashOpts.tcuOptions.copyWith(linePressureBump: true),
      );
      expect(updated.tcuOptions.linePressureBump, isTrue);
    });

    test('serializeCustomRomBinaryTable includes 16-byte TCU payload', () {
      final flashOpts = BmwFlashOptions();
      final tableBytes = flashOpts.serializeCustomRomBinaryTable();

      expect(flashOpts.toBytes().length, equals(tableBytes.length));

      // Check TCU portion at the end
      final tcuBytes = tableBytes.sublist(tableBytes.length - 16);
      expect(tcuBytes.length, equals(16));
      expect(tcuBytes, equals(flashOpts.tcuOptions.toBytes()));
    });

    test('generatePatchSummary includes all TCU patch parameters', () {
      final flashOpts = BmwFlashOptions();
      final summary = flashOpts.generatePatchSummary();

      expect(summary.containsKey('tcu_line_pressure_bump'), isTrue);
      expect(summary.containsKey('tcu_custom_launch_control'), isTrue);
      expect(summary.containsKey('tcu_launch_rpm'), isTrue);
      expect(summary.containsKey('tcu_launch_boost_psi'), isTrue);
      expect(summary.containsKey('tcu_torque_punch'), isTrue);
      expect(summary.containsKey('tcu_kickdown_lockout_manual'), isTrue);
      expect(summary.containsKey('tcu_take_off_2nd_gear'), isTrue);
      expect(summary.containsKey('tcu_true_manual_mode'), isTrue);
      expect(summary.containsKey('tcu_throttle_blip_percent'), isTrue);
      expect(summary.containsKey('tcu_kombi_gear_display'), isTrue);
      expect(summary.containsKey('tcu_max_shift_rpm'), isTrue);
      expect(summary.containsKey('tcu_torque_limits_removed'), isTrue);
      expect(summary.containsKey('tcu_standstill_decoupling_disabled'), isTrue);
      expect(summary.containsKey('tcu_warmup_disabled'), isTrue);
      expect(summary.containsKey('tcu_shift_speed'), isTrue);
    });

    test('Extended factory settings (DragRace, BrakeBoost, Coasting, Valet) round-trip properly', () {
      const extendedOptions = BmwTcuOptions(
        dragRaceMode: true,
        dragRaceActivationThreshold: 3400,
        brakeBoostProtection: true,
        brakeBoostProtectionValue: 18.5,
        coastingModeDisabled: true,
        disableObdAlarm: true,
        disableTempMonitoring: true,
        customCreepDisabled: true,
        valetModeEnabled: true,
        ignitionCutShifting: true,
      );

      final bytes = extendedOptions.toBytes();
      expect(bytes.length, equals(16));

      // Byte 8: Bitfield 3 (All 8 bits enabled -> 0xFF)
      expect(bytes[8], equals(0xFF));

      // Byte 9: 3400 / 20 = 170
      expect(bytes[9], equals(170));

      // Byte 10: 18.5 * 10 = 185
      expect(bytes[10], equals(185));

      final restored = BmwTcuOptions.fromBytes(bytes);
      expect(restored.dragRaceMode, isTrue);
      expect(restored.dragRaceActivationThreshold, equals(3400));
      expect(restored.brakeBoostProtection, isTrue);
      expect(restored.brakeBoostProtectionValue, equals(18.5));
      expect(restored.coastingModeDisabled, isTrue);
      expect(restored.disableObdAlarm, isTrue);
      expect(restored.disableTempMonitoring, isTrue);
      expect(restored.customCreepDisabled, isTrue);
      expect(restored.valetModeEnabled, isTrue);
      expect(restored.ignitionCutShifting, isTrue);
    });
  });

  group('BmwCustomRomService TCU Communication & UDS Payloads', () {
    test('EGS ECU address and DID constants are correct', () {
      expect(BmwCustomRomService.egsAddress, equals(0x18));
      expect(BmwCustomRomService.didTcuOptions, equals(0xD440));
    });

    test('Generates correct UDS Read and Write payloads for EGS 0x18 DID 0xD440', () {
      final readPayload = BmwCustomRomService.buildReadTcuOptionsPayload();
      expect(readPayload, equals([0x22, 0xD4, 0x40]));

      const options = BmwTcuOptions(
        linePressureBump: true,
        launchRpm: 3400,
      );
      final writePayload = BmwCustomRomService.buildWriteTcuOptionsPayload(options);

      expect(writePayload.length, equals(3 + 16));
      expect(writePayload[0], equals(0x2E));
      expect(writePayload[1], equals(0xD4));
      expect(writePayload[2], equals(0x40));
      expect(writePayload.sublist(3), equals(options.toBytes()));
    });
  });
}
