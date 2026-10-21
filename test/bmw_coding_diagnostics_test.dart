import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_coding_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_ecu_scanner.dart';

void main() {
  group('BMW Extended Freeze Frame Snapshot Parsing', () {
    test('Correctly parses standardized DID tagged freeze frame (ISO 14229)', () {
      // DID 0xF1A0 (Odometer: 125,000 km -> 0x01 0xE8 0x48)
      // DID 0x010C (Engine RPM: 2,400 RPM -> raw 9,600 = 0x25 0x80)
      // DID 0x0105 (Coolant Temp: 92°C -> raw 92 + 40 = 132 = 0x84)
      // DID 0x0123 (Rail Pressure: 150.0 bar -> raw 1500 = 0x05 0xDC)
      // DID 0xF111 (Battery: 13.80V -> 13800 mV = 0x35 0xE8)
      // DID 0xF000 (Counter: 3 times -> 0x03)
      final snapshotBytes = Uint8List.fromList([
        0xF1, 0xA0, 0x01, 0xE8, 0x48,
        0x01, 0x0C, 0x25, 0x80,
        0x01, 0x05, 0x84,
        0x01, 0x23, 0x05, 0xDC,
        0xF1, 0x11, 0x35, 0xE8,
        0xF0, 0x00, 0x03,
      ]);

      final ff = BmwEcuScanner.parseFreezeFramePayload(snapshotBytes);

      expect(ff.mileageKm, equals(125000));
      expect(ff.engineRpm, equals(2400));
      expect(ff.coolantTempC, equals(92.0));
      expect(ff.railPressureBar, equals(150.0));
      expect(ff.batteryVoltage, closeTo(13.8, 0.01));
      expect(ff.faultFrequency, equals(3));
      expect(ff.summary, contains('125000 km'));
      expect(ff.summary, contains('2400 RPM'));
      expect(ff.summary, contains('92.0°C'));
    });

    test('Correctly parses BMW DME sequential raw offset struct', () {
      // Offset 0..2: Mileage 110,500 km -> 0x01 0xAF 0xA4
      // Offset 3..4: RPM 1,800 RPM -> raw 7,200 = 0x1C 0x20
      // Offset 5: Coolant Temp: 85°C -> raw 85 + 40 = 125 = 0x7D
      // Offset 6..7: Rail Pressure: 120.0 bar -> raw 1200 = 0x04 0xB0
      // Offset 8..9: Voltage: 14.10V -> 14100 mV = 0x37 0x14
      // Offset 10: Fault counter: 1 -> 0x01
      final rawStruct = Uint8List.fromList([
        0x01, 0xAF, 0xA4,
        0x1C, 0x20,
        0x7D,
        0x04, 0xB0,
        0x37, 0x14,
        0x01,
      ]);

      final ff = BmwEcuScanner.parseFreezeFramePayload(rawStruct);

      expect(ff.mileageKm, equals(110500));
      expect(ff.engineRpm, equals(1800));
      expect(ff.coolantTempC, equals(85.0));
      expect(ff.railPressureBar, equals(120.0));
      expect(ff.batteryVoltage, closeTo(14.1, 0.01));
      expect(ff.faultFrequency, equals(1));
    });
  });

  group('NCD Raw Backup Serialization', () {
    test('Serializes and deserializes NCD backups with byte accuracy', () {
      final original = Uint8List.fromList([0x00, 0x01, 0xA5, 0xFF, 0x42, 0x10]);
      final backup = NcdBackup(
        id: 'ncd_test_01',
        timestamp: DateTime(2026, 10, 14, 12, 0, 0),
        vin: 'WBA3A5C50DF123456',
        ecuAddress: 0x40,
        ecuName: 'FEM/BDC (0x40)',
        did: 0x3023,
        cheatCodeId: 'TCM_MSA_MEMORY',
        cheatCodeName: 'Auto Start-Stop Memory',
        originalBytes: original,
        description: 'Test backup',
      );

      final json = backup.toJson();
      final restored = NcdBackup.fromJson(json);

      expect(restored.id, equals(backup.id));
      expect(restored.vin, equals('WBA3A5C50DF123456'));
      expect(restored.ecuAddress, equals(0x40));
      expect(restored.did, equals(0x3023));
      expect(restored.originalBytes, equals(original));
    });
  });

  group('BMW FDL Cheat Codes Catalog', () {
    test('Includes all required cheat codes with correct ECU and DIDs', () {
      final service = BmwCodingService();
      final codes = service.getAvailableCheatCodes();

      final msa = codes.firstWhere((c) => c.id == 'TCM_MSA_MEMORY');
      expect(msa.targetEcuAddress, equals(0x40));
      expect(msa.did, equals(0x3023));

      final mirrors = codes.firstWhere((c) => c.id == 'KOMFORTSCHLIESSUNG_FB');
      expect(mirrors.targetEcuAddress, equals(0x40));
      expect(mirrors.did, equals(0x3053));

      final speedo = codes.firstWhere((c) => c.id == 'BC_DIGITAL_V');
      expect(speedo.targetEcuAddress, equals(0x60));
      expect(speedo.did, equals(0x3000));

      final chime = codes.firstWhere((c) => c.id == 'GURTWARNUNG');
      expect(chime.targetEcuAddress, equals(0x01));
      expect(chime.did, equals(0x3000));

      final vim = codes.firstWhere((c) => c.id == 'SPEEDLOCK');
      expect(vim.targetEcuAddress, equals(0x63));
      expect(vim.did, equals(0x3000));
      expect(vim.activeValue, equals(0xFF));

      final sportAuto = codes.firstWhere((c) => c.id == 'SPORTSWITCH_2TB');
      expect(sportAuto.targetEcuAddress, equals(0x18));
      expect(sportAuto.secondaryEcuAddress, equals(0x40));
    });

    test('Includes all 12 key FDL Cheat Codes with exact parameters', () {
      final service = BmwCodingService();
      final codes = service.getAvailableCheatCodes();

      // 1. mirrors_fold_convenience
      final mirrors = codes.firstWhere((c) => c.id == 'mirrors_fold_convenience');
      expect(mirrors.targetEcuAddress, equals(0x40));
      expect(mirrors.did, equals(0x3101));
      expect(mirrors.byteOffset, equals(14));
      expect(mirrors.bitMask, equals(0x0F));
      expect(mirrors.activeValue, equals(0x00));
      expect(mirrors.inactiveValue, equals(0x0F));
      expect(mirrors.category, equals('Comfort & Convenience'));

      // 2. acoustic_lock_chirp
      final chirp = codes.firstWhere((c) => c.id == 'acoustic_lock_chirp');
      expect(chirp.targetEcuAddress, equals(0x63));
      expect(chirp.did, equals(0x3000));
      expect(chirp.byteOffset, equals(8));
      expect(chirp.bitMask, equals(0x01));
      expect(chirp.activeValue, equals(0x01));
      expect(chirp.inactiveValue, equals(0x00));
      expect(chirp.secondaryEcuAddress, equals(0x40));
      expect(chirp.secondaryDid, equals(0x3010));
      expect(chirp.secondaryByteOffset, equals(4));
      expect(chirp.secondaryBitMask, equals(0x01));
      expect(chirp.secondaryActiveValue, equals(0x01));
      expect(chirp.secondaryInactiveValue, equals(0x00));
      expect(chirp.category, equals('Safety & Chimes'));

      // 3. digital_speedo_kombi
      final speedoKombi = codes.firstWhere((c) => c.id == 'digital_speedo_kombi');
      expect(speedoKombi.targetEcuAddress, equals(0x60));
      expect(speedoKombi.did, equals(0x3000));
      expect(speedoKombi.byteOffset, equals(12));
      expect(speedoKombi.bitMask, equals(0x01));
      expect(speedoKombi.activeValue, equals(0x01));
      expect(speedoKombi.inactiveValue, equals(0x00));
      expect(speedoKombi.category, equals('Cockpit & Cluster'));

      // 4. tire_pressure_temp_idrive
      final tpms = codes.firstWhere((c) => c.id == 'tire_pressure_temp_idrive');
      expect(tpms.targetEcuAddress, equals(0x63));
      expect(tpms.did, equals(0x3001));
      expect(tpms.byteOffset, equals(22));
      expect(tpms.bitMask, equals(0x03));
      expect(tpms.activeValue, equals(0x02));
      expect(tpms.inactiveValue, equals(0x01));
      expect(tpms.category, equals('Infotainment & Media'));

      // 5. chimes_rolls_royce
      final rrChimes = codes.firstWhere((c) => c.id == 'chimes_rolls_royce');
      expect(rrChimes.targetEcuAddress, equals(0x63));
      expect(rrChimes.did, equals(0x3002));
      expect(rrChimes.byteOffset, equals(18));
      expect(rrChimes.bitMask, equals(0x07));
      expect(rrChimes.activeValue, equals(0x04));
      expect(rrChimes.inactiveValue, equals(0x00));
      expect(rrChimes.category, equals('Safety & Chimes'));

      // 6. video_in_motion_speedlock
      final vimSpeedlock = codes.firstWhere((c) => c.id == 'video_in_motion_speedlock');
      expect(vimSpeedlock.targetEcuAddress, equals(0x63));
      expect(vimSpeedlock.did, equals(0x3000));
      expect(vimSpeedlock.byteOffset, equals(35));
      expect(vimSpeedlock.bitMask, equals(0xFF));
      expect(vimSpeedlock.activeValue, equals(0xFF));
      expect(vimSpeedlock.inactiveValue, equals(0x03));
      expect(vimSpeedlock.category, equals('Infotainment & Media'));

      // 7. angel_eyes_100_percent
      final angelEyes = codes.firstWhere((c) => c.id == 'angel_eyes_100_percent');
      expect(angelEyes.targetEcuAddress, equals(0x40));
      expect(angelEyes.did, equals(0x3062));
      expect(angelEyes.byteOffset, equals(16));
      expect(angelEyes.bitMask, equals(0xFF));
      expect(angelEyes.activeValue, equals(0x64));
      expect(angelEyes.inactiveValue, equals(0x32));
      expect(angelEyes.category, equals('Lighting & Visibility'));

      // 8. ambient_lighting_dual_tone
      final ambient = codes.firstWhere((c) => c.id == 'ambient_lighting_dual_tone');
      expect(ambient.targetEcuAddress, equals(0x40));
      expect(ambient.did, equals(0x3070));
      expect(ambient.byteOffset, equals(9));
      expect(ambient.bitMask, equals(0x03));
      expect(ambient.activeValue, equals(0x02));
      expect(ambient.inactiveValue, equals(0x01));
      expect(ambient.category, equals('Lighting & Visibility'));

      // 9. brake_force_display_flash
      final bfd = codes.firstWhere((c) => c.id == 'brake_force_display_flash');
      expect(bfd.targetEcuAddress, equals(0x40));
      expect(bfd.did, equals(0x3060));
      expect(bfd.byteOffset, equals(27));
      expect(bfd.bitMask, equals(0x03));
      expect(bfd.activeValue, equals(0x02));
      expect(bfd.inactiveValue, equals(0x00));
      expect(bfd.category, equals('Lighting & Visibility'));

      // 10. door_handle_lights_reverse
      final doorLights = codes.firstWhere((c) => c.id == 'door_handle_lights_reverse');
      expect(doorLights.targetEcuAddress, equals(0x40));
      expect(doorLights.did, equals(0x3070));
      expect(doorLights.byteOffset, equals(31));
      expect(doorLights.bitMask, equals(0x01));
      expect(doorLights.activeValue, equals(0x01));
      expect(doorLights.inactiveValue, equals(0x00));
      expect(doorLights.category, equals('Lighting & Visibility'));

      // 11. seatbelt_chime_driver_disable
      final sbDriver = codes.firstWhere((c) => c.id == 'seatbelt_chime_driver_disable');
      expect(sbDriver.targetEcuAddress, equals(0x01));
      expect(sbDriver.did, equals(0x3000));
      expect(sbDriver.byteOffset, equals(2));
      expect(sbDriver.bitMask, equals(0x01));
      expect(sbDriver.activeValue, equals(0x00));
      expect(sbDriver.inactiveValue, equals(0x01));
      expect(sbDriver.category, equals('Safety & Chimes'));

      // 12. seatbelt_chime_passenger_disable
      final sbPass = codes.firstWhere((c) => c.id == 'seatbelt_chime_passenger_disable');
      expect(sbPass.targetEcuAddress, equals(0x01));
      expect(sbPass.did, equals(0x3000));
      expect(sbPass.byteOffset, equals(3));
      expect(sbPass.bitMask, equals(0x01));
      expect(sbPass.activeValue, equals(0x00));
      expect(sbPass.inactiveValue, equals(0x01));
      expect(sbPass.category, equals('Safety & Chimes'));
    });

    test('All required UI categories are populated with cheat codes', () {
      final service = BmwCodingService();
      final codes = service.getAvailableCheatCodes();

      final requiredCategories = [
        'Lighting & Visibility',
        'Cockpit & Cluster',
        'Safety & Chimes',
        'Comfort & Convenience',
        'Infotainment & Media',
        'Drivetrain & Performance',
      ];

      for (final cat in requiredCategories) {
        final matches = codes.where((c) => c.category == cat).toList();
        expect(matches.isNotEmpty, isTrue, reason: 'Category "$cat" should not be empty');
      }
    });
  });
}
