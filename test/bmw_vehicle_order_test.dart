import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_coding_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';

class MockCodingProtocol extends EnetHsfzProtocol {
  @override
  bool get isConnected => true;

  @override
  Future<Uint8List?> sendUdsAndAwait(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(seconds: 2),
    Duration p2Star = const Duration(seconds: 10),
    int maxPending = 60,
  }) async {
    if (udsPayload[0] == 0x27) {
      if (udsPayload[1] == 0x01) {
        // Return seed [0x11, 0x22, 0x33, 0x44]
        return Uint8List.fromList([0x67, 0x01, 0x11, 0x22, 0x33, 0x44]);
      } else if (udsPayload[1] == 0x02) {
        // Return key verified
        return Uint8List.fromList([0x67, 0x02]);
      }
    }
    return null;
  }
}

void main() {
  group('BMW Vehicle Order (FA - Fahrzeugauftrag) Model', () {
    test('Serializes and deserializes standard FA string representation', () {
      const rawFa =
          'E F030 -15-03-500 *3B93 #0315 L475 PLCSW %0000 &0000 \$1CA \$2TB \$5A1 \$609 \$6NS +MPE1';
      final vo = BmwVehicleOrder.fromFaString(rawFa, vin: 'WBA3B91050F123456');

      expect(vo.series, equals('F030'));
      expect(vo.typeKey, equals('3B93'));
      expect(vo.productionDate, equals('0315'));
      expect(vo.formattedDate, equals('03/2015'));
      expect(vo.paintCode, equals('475'));
      expect(vo.upholsteryCode, equals('LCSW'));
      expect(vo.options, contains(r'$2TB'));
      expect(vo.options, contains(r'$6NS'));
      expect(vo.hoWords, contains('+MPE1'));
      expect(vo.modelName, contains('F30 328i'));

      final generatedFa = vo.toFaString();
      expect(generatedFa, contains('*3B93'));
      expect(generatedFa, contains('#0315'));
      expect(generatedFa, contains(r'$2TB'));
      expect(generatedFa, contains(r'$6NS'));
      expect(generatedFa, contains('+MPE1'));
    });

    test('Encodes and decodes binary UDS DID 0xFA01 bytes', () {
      final vo = BmwVehicleOrder(
        vin: 'WBA3B91050F123456',
        series: 'F030',
        typeKey: '3B93',
        productionDate: '0315',
        paintCode: '475',
        upholsteryCode: 'LCSW',
        options: const [r'$2TB', r'$6NS', r'$5A1'],
        hoWords: const ['+MPE1'],
      );

      final binaryBytes = vo.toBinaryFa();
      expect(binaryBytes.length, greaterThanOrEqualTo(22));

      final decoded = BmwVehicleOrder.fromBinaryFa(binaryBytes, vin: vo.vin);
      expect(decoded.series, equals('F030'));
      expect(decoded.typeKey, equals('3B93'));
      expect(decoded.productionDate, equals('0315'));
      expect(decoded.paintCode, equals('475'));
      expect(decoded.upholsteryCode, equals('LCSW'));
      expect(decoded.options, contains(r'$2TB'));
      expect(decoded.options, contains(r'$6NS'));
      expect(decoded.options, contains(r'$5A1'));
      expect(decoded.hoWords, contains('+MPE1'));
    });
  });

  group('res_VoFix & Validation Engine', () {
    test('Resolves conflicting options, trims duplicates, and repairs Zeitkriterium', () {
      final service = BmwCodingService();
      final corruptedVo = BmwVehicleOrder(
        vin: 'WBA3B91050F123456',
        series: 'f030',
        typeKey: '*3b93',
        productionDate: '#1599', // Invalid month 99
        paintCode: 'L475',
        upholsteryCode: 'PLCSW',
        options: const [
          r'$205', // Standard automatic
          r'$2TB', // Sport automatic (conflicts with $205)
          r'$2TB', // Duplicate $2TB
          '6NS',   // Missing $ prefix
          r'$606', // Business nav
          r'$609', // Pro nav (conflicts with $606)
          r'$676', // HiFi
          r'$688', // Harman Kardon (conflicts with $676)
        ],
      );

      final fixResult = service.fixVehicleOrder(corruptedVo);

      expect(fixResult.wasModified, isTrue);
      final fixed = fixResult.fixedVo;

      expect(fixed.series, equals('F030'));
      expect(fixed.typeKey, equals('3B93'));
      expect(fixed.productionDate, equals('0399')); // Corrected month to 03
      expect(fixed.paintCode, equals('475'));
      expect(fixed.upholsteryCode, equals('LCSW'));

      // Conflict resolutions:
      expect(fixed.options, contains(r'$2TB'));
      expect(fixed.options.contains(r'$205'), isFalse); // $205 removed
      expect(fixed.options.where((o) => o == r'$2TB').length, equals(1)); // duplicate stripped
      expect(fixed.options, contains(r'$6NS')); // missing $ added
      expect(fixed.options, contains(r'$609'));
      expect(fixed.options.contains(r'$606'), isFalse); // $606 removed in favor of $609
      expect(fixed.options, contains(r'$688'));
      expect(fixed.options.contains(r'$676'), isFalse); // $676 removed in favor of $688
    });
  });

  group('res_addCusVO and res_saveVO', () {
    test('addCustomOption adds option and auto-resolves superseded equipment', () {
      final service = BmwCodingService();
      final initialVo = BmwVehicleOrder(
        vin: 'WBA3B91050F123456',
        typeKey: '3B93',
        productionDate: '0315',
        options: const [r'$1CA', r'$205', r'$520'],
      );

      // Add $2TB Sport Automatic
      final updated = service.addCustomOption(initialVo, '2TB');

      expect(updated.options, contains(r'$2TB'));
      expect(updated.options.contains(r'$205'), isFalse); // $205 auto-removed by res_VoFix
    });

    test('removeOption removes selected code', () {
      final service = BmwCodingService();
      final initialVo = BmwVehicleOrder(
        vin: 'WBA3B91050F123456',
        typeKey: '3B93',
        productionDate: '0315',
        options: const [r'$2TB', r'$6NS'],
      );

      final updated = service.removeOption(initialVo, r'$6NS');
      expect(updated.options.contains(r'$6NS'), isFalse);
      expect(updated.options.contains(r'$2TB'), isTrue);
    });
  });

  group('Factory Auto-Code / Default Coding Engine', () {
    test('calculateFactoryCodingPlan calculates exact affected ECUs for retrofits', () {
      final service = BmwCodingService();
      final vo = BmwVehicleOrder(
        vin: 'WBA3B91050F123456',
        typeKey: '3B93',
        productionDate: '0315',
        options: const [r'$2TB', r'$6NS', r'$5A1'],
      );

      final plan = service.calculateFactoryCodingPlan(vo, [r'$2TB', r'$6NS', r'$5A1']);

      final ecuAddresses = plan.map((p) => p.ecuAddress).toSet();
      // $2TB affects: EGS (0x18), FEM/BDC (0x40), KOMBI (0x60), DME (0x12), DSC (0x29)
      expect(ecuAddresses, contains(BmwCodingService.egsAddress));
      expect(ecuAddresses, contains(BmwCodingService.casAddress));
      expect(ecuAddresses, contains(BmwCodingService.kombiAddress));
      expect(ecuAddresses, contains(BmwCodingService.dmeAddress));
      expect(ecuAddresses, contains(BmwCodingService.dscAddress));

      // $6NS affects: HU_NBT (0x63)
      expect(ecuAddresses, contains(BmwCodingService.huNbtAddress));

      // Check primary DIDs
      final egsPlan = plan.firstWhere((p) => p.ecuAddress == BmwCodingService.egsAddress);
      expect(egsPlan.primaryDid, equals(0x3001));

      final casPlan = plan.firstWhere((p) => p.ecuAddress == BmwCodingService.casAddress);
      expect(casPlan.primaryDid, equals(0x3020));
    });
  });

  group('BMW UDS Security Access (0x27 Seed-Key)', () {
    test('Security Access without remoteKeyProvider returns false (fail-closed)', () async {
      final proto = MockCodingProtocol();
      final service = BmwCodingService(protocol: proto);
      final unlocked = await service.unlockSecurityAccess(BmwCodingService.casAddress);
      expect(unlocked, isFalse);
    });

    test('BmwCodingService delegates seed to remoteKeyProvider and completes unlock', () async {
      int? capturedEcu;
      int? capturedLevel;
      List<int>? capturedSeed;

      final proto = MockCodingProtocol();
      final service = BmwCodingService(
        protocol: proto,
        remoteKeyProvider: (ecu, level, seed) async {
          capturedEcu = ecu;
          capturedLevel = level;
          capturedSeed = seed;
          return [0xDE, 0xAD, 0xBE, 0xEF];
        },
      );

      final unlocked = await service.unlockSecurityAccess(BmwCodingService.casAddress);
      expect(unlocked, isTrue);
      expect(capturedEcu, equals(BmwCodingService.casAddress));
      expect(capturedLevel, equals(0x01));
      expect(capturedSeed, equals([0x11, 0x22, 0x33, 0x44]));
    });
  });

  group('res_backupVO / res_restoreVO Serialization', () {
    test('VehicleOrderBackup serializes and deserializes accurately', () {
      final backup = VehicleOrderBackup(
        id: 'vo_backup_123',
        timestamp: DateTime(2026, 10, 14, 12, 0, 0),
        vin: 'WBA3B91050F123456',
        series: 'F030',
        typeKey: '3B93',
        productionDate: '0315',
        rawFaString: 'E F030 -15-03-500 *3B93 #0315 \$2TB',
        options: const [r'$2TB'],
        description: 'Test backup',
      );

      final json = backup.toJson();
      final restored = VehicleOrderBackup.fromJson(json);

      expect(restored.id, equals(backup.id));
      expect(restored.vin, equals(backup.vin));
      expect(restored.typeKey, equals(backup.typeKey));
      expect(restored.rawFaString, equals(backup.rawFaString));
      expect(restored.options, equals(backup.options));
    });
  });
}
