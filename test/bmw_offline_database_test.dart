import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BMW 100% Offline Database Audit & Verification', () {
    late Map<String, dynamic> fdlData;
    late Map<String, dynamic> kisData;
    late Map<String, dynamic> istaData;

    setUpAll(() {
      // Load raw json files from disk for offline unit test verification
      final fdlFile = File('assets/offline_db/fdl_cheat_codes.json');
      expect(fdlFile.existsSync(), isTrue, reason: 'fdl_cheat_codes.json must exist in assets/offline_db');
      fdlData = json.decode(fdlFile.readAsStringSync()) as Map<String, dynamic>;

      final kisFile = File('assets/offline_db/kis_compatibility.json');
      expect(kisFile.existsSync(), isTrue, reason: 'kis_compatibility.json must exist in assets/offline_db');
      kisData = json.decode(kisFile.readAsStringSync()) as Map<String, dynamic>;

      final istaFile = File('assets/offline_db/ista_service_functions.json');
      expect(istaFile.existsSync(), isTrue, reason: 'ista_service_functions.json must exist in assets/offline_db');
      istaData = json.decode(istaFile.readAsStringSync()) as Map<String, dynamic>;
    });

    test('1. FDL Cheat Codes Database integrity (2,561 codes from E-Sys LauncherPRO)', () {
      final meta = fdlData['metadata'] as Map<String, dynamic>;
      expect(meta['total_codes'], equals(2561));
      expect(meta['unique_cafds'], greaterThanOrEqualTo(60));
      expect(meta['total_functions'], greaterThanOrEqualTo(4000));

      final codes = fdlData['codes'] as List<dynamic>;
      expect(codes.length, equals(2561));

      // Verify BDC_01 (000017BE) codes exist (used in F15, F16, F25, F26)
      final bdcCodes = codes.where((c) => c['cafd_id'] == '000017BE').toList();
      expect(bdcCodes.isNotEmpty, isTrue);

      // Verify specific parameter attributes
      final firstBdc = bdcCodes.first as Map<String, dynamic>;
      expect(firstBdc['groups'], isNotEmpty);
      final firstGroup = (firstBdc['groups'] as List<dynamic>).first as Map<String, dynamic>;
      final firstFn = (firstGroup['functions'] as List<dynamic>).first as Map<String, dynamic>;
      expect(firstFn.containsKey('start'), isTrue);
      expect(firstFn.containsKey('end'), isTrue);
      expect(firstFn.containsKey('mask'), isTrue);
      expect(firstFn.containsKey('target_value'), isTrue);
    });

    test('2. KIS Compatibility Database integrity (Chassis, ECUs, I-Steps, SGBM)', () {
      final meta = kisData['metadata'] as Map<String, dynamic>;
      expect(meta['total_series'], greaterThanOrEqualTo(18));
      expect(meta['total_ecus'], greaterThanOrEqualTo(1000));
      expect(meta['total_i_levels'], greaterThanOrEqualTo(2000));

      final seriesMap = kisData['series'] as Map<String, dynamic>;
      // Verify F025 series (covering BMW X4 F26 and X3 F25)
      expect(seriesMap.containsKey('F025'), isTrue);
      final f025 = seriesMap['F025'] as Map<String, dynamic>;

      // Check chassis list
      final chassisList = (f025['chassis'] as List<dynamic>)
          .map((c) => c['name'] as String)
          .toList();
      expect(chassisList, containsAll(['F26', 'F25', 'F15', 'F16', 'F85', 'F86']));

      // Check ECUs list
      final ecus = f025['ecus'] as List<dynamic>;
      expect(ecus.length, equals(128));

      // Check specific ECU addresses
      final dme = ecus.firstWhere((e) => e['name'].toString().contains('DME'));
      expect(dme['diag_addr_hex'], equals('0x12'));

      final cas = ecus.firstWhere((e) => e['name'].toString().contains('CAS'));
      expect(cas['diag_addr_hex'], equals('0x40'));

      final zgw = ecus.firstWhere((e) => e['name'].toString().contains('ZGW'));
      expect(zgw['diag_addr_hex'], equals('0x10'));

      // Check I-Steps
      final iLevels = f025['i_levels'] as List<dynamic>;
      expect(iLevels.isNotEmpty, isTrue);
      final latestILevel = iLevels.first as Map<String, dynamic>;
      expect(latestILevel['name'].toString().startsWith('F025-'), isTrue);

      // Check ZB mappings
      final zbMappings = kisData['zb_mappings'] as Map<String, dynamic>;
      expect(zbMappings.isNotEmpty, isTrue);
    });

    test('3. ISTA Factory Service Routines & EcuFunctions integrity', () {
      final meta = istaData['metadata'] as Map<String, dynamic>;
      expect(meta['total_service_routines'], greaterThanOrEqualTo(10));
      expect(meta['total_ecu_jobs'], greaterThanOrEqualTo(10));

      final routines = istaData['service_routines'] as List<dynamic>;
      final routineIds = routines.map((r) => r['id'] as String).toList();

      expect(routineIds, containsAll([
        'cbs_reset',
        'battery_register',
        'dpf_regeneration',
        'egs_adaptations_reset',
        'vtg_oil_reset_calibration',
        'valvetronic_learn',
        'epb_workshop_mode',
        'steering_angle_calibration',
        'brake_bleed_routine',
        'injector_coding',
      ]));

      // Verify battery registration metadata
      final batteryRoutine = routines.firstWhere((r) => r['id'] == 'battery_register');
      expect(batteryRoutine['ecu_target'], contains('DME'));
      expect(batteryRoutine['supported_types'], containsAll(['90Ah AGM', '105Ah AGM']));

      // Verify EcuFunctions diagnostic jobs
      final jobs = istaData['ecu_diagnostic_jobs'] as Map<String, dynamic>;
      expect(jobs.isNotEmpty, isTrue);
    });
  });
}
