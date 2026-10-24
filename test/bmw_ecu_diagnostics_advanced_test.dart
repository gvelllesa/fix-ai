import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_ecu_scanner.dart';

void main() {
  group('1. BMW 32-Module ECU Topology Architecture', () {
    test('Contains exactly 32 factory modules with all required addresses and descriptions', () {
      final topology = BmwEcuScanner.getDefaultFSeriesTopology();
      expect(topology.length, equals(32));

      final expectedAddresses = <int, String>{
        0x12: 'DME',
        0x18: 'EGS',
        0x19: 'VTG',
        0x17: 'EKP',
        0x10: 'ZGW',
        0x40: 'FEM/BDC',
        0x29: 'DSC',
        0x30: 'EPS',
        0x60: 'KOMBI',
        0x63: 'HU_NBT',
        0x6D: 'SMFA',
        0x01: 'ACSM',
        0x56: 'FZD',
        0x78: 'IHKA',
        0x3F: 'VDC/EDC',
        0x6E: 'SMBF',
        0x5D: 'KAFAS',
        0x1C: 'ICM',
        0x2C: 'PMA',
        0x43: 'FLEL',
        0x44: 'FLER',
        0x67: 'ZBE',
        0x64: 'PDC',
        0x5E: 'TRSVC',
        0x20: 'RDC',
        0x38: 'TCB/ATM',
        0x58: 'SMFA_LEGACY',
        0x59: 'SMBF_LEGACY',
        0x62: 'CID',
        0x72: 'CAS',
        0x70: 'FRM',
        0x3B: 'JBBF',
      };

      for (final entry in expectedAddresses.entries) {
        final match = topology.where((e) => e.address == entry.key);
        expect(match.length, equals(1), reason: 'Module 0x${entry.key.toRadixString(16).toUpperCase()} (${entry.value}) must exist uniquely');
        final ecu = match.first;
        expect(ecu.name, equals(entry.value));
        expect(ecu.description.isNotEmpty, isTrue);
      }
    });

    test('EcuInfo model tracks responding state and fault counts properly', () {
      final ecu = EcuInfo(address: 0x12, name: 'DME', description: 'Engine ECU');
      expect(ecu.isResponding, isFalse);
      expect(ecu.totalFaultsCount, equals(0));

      ecu.isResponding = true;
      ecu.faultCodes.add('P0420 (180001) [Confirmed]');
      ecu.shadowFaultCodes.add(ShadowDtcRecord(
        ecuAddress: 0x12,
        ecuName: 'DME',
        hexCode: '138102',
        standardDtc: 'P1381',
        description: 'Exhaust flap open circuit',
        statusByte: 0x04,
        statusDescription: 'Infospeicher',
      ));

      expect(ecu.faultCodes.length, equals(1));
      expect(ecu.shadowFaultCodes.length, equals(1));
      expect(ecu.totalFaultsCount, equals(2));
    });
  });

  group('2. I/M Emissions Inspection Readiness Monitor Decoding', () {
    test('Decodes 100% passed / ready emissions payload (MIL OFF, all monitors complete)', () {
      // Byte A: 0x00 (MIL OFF, 0 DTCs)
      // Byte B: 0x07 (Misfire, Fuel, Comprehensive supported; bits 4..6 = 0: all complete)
      // Byte C: 0xED (Catalyst, EVAP, Secondary Air, O2 Sensor, O2 Heater, EGR supported = 1+4+8+32+64+128 = 237 = 0xED)
      // Byte D: 0x00 (Bits 0..7 = 0: all complete)
      final rawPayload = Uint8List.fromList([0x00, 0x07, 0xED, 0x00]);
      final result = BmwEcuScanner.parseEmissionsReadinessPayload(rawPayload);

      expect(result.milOn, isFalse);
      expect(result.dtcCount, equals(0));
      expect(result.isReady, isTrue);
      expect(result.passedCount, equals(9));
      expect(result.incompleteCount, equals(0));
      expect(result.unsupportedCount, equals(0));

      final misfire = result.getMonitor('MISFIRE');
      expect(misfire, isNotNull);
      expect(misfire!.status, equals(MonitorStatus.passed));

      final catalyst = result.getMonitor('CATALYST');
      expect(catalyst, isNotNull);
      expect(catalyst!.status, equals(MonitorStatus.passed));

      final o2Sensor = result.getMonitor('O2_SENSOR');
      expect(o2Sensor, isNotNull);
      expect(o2Sensor!.status, equals(MonitorStatus.passed));

      final egr = result.getMonitor('EGR_VVT');
      expect(egr, isNotNull);
      expect(egr!.status, equals(MonitorStatus.passed));
    });

    test('Decodes active MIL and incomplete monitor flags correctly as failed', () {
      // Byte A: 0x82 (Bit 7 = 1: MIL ON; Bits 6..0 = 2 DTCs)
      // Byte B: 0x07 (Supported = 7; bits 4..6 = 0: complete)
      // Byte C: 0xED (All 6 non-continuous supported)
      // Byte D: 0x05 (Catalyst bit 0 = 1 incomplete; EVAP bit 2 = 1 incomplete)
      final rawPayload = Uint8List.fromList([0x82, 0x07, 0xED, 0x05]);
      final result = BmwEcuScanner.parseEmissionsReadinessPayload(rawPayload);

      expect(result.milOn, isTrue);
      expect(result.dtcCount, equals(2));
      expect(result.isReady, isFalse);

      final catalyst = result.getMonitor('CATALYST')!;
      expect(catalyst.isSupported, isTrue);
      expect(catalyst.isComplete, isFalse);
      expect(catalyst.status, equals(MonitorStatus.failed)); // Failed because MIL is ON

      final evap = result.getMonitor('EVAP')!;
      expect(evap.isSupported, isTrue);
      expect(evap.isComplete, isFalse);
      expect(evap.status, equals(MonitorStatus.failed));

      final o2Heater = result.getMonitor('O2_HEATER')!;
      expect(o2Heater.isSupported, isTrue);
      expect(o2Heater.isComplete, isTrue);
      expect(o2Heater.status, equals(MonitorStatus.passed));
    });

    test('Decodes incomplete monitors with MIL OFF as MonitorStatus.incomplete', () {
      // Byte A: 0x00 (MIL OFF)
      // Byte B: 0x07 (bits 4..6 = 0)
      // Byte C: 0xED (All supported)
      // Byte D: 0x01 (Catalyst test incomplete after DTC reset)
      final rawPayload = Uint8List.fromList([0x00, 0x07, 0xED, 0x01]);
      final result = BmwEcuScanner.parseEmissionsReadinessPayload(rawPayload);

      expect(result.milOn, isFalse);
      expect(result.isReady, isFalse); // Not ready because 1 monitor is incomplete
      final catalyst = result.getMonitor('CATALYST')!;
      expect(catalyst.status, equals(MonitorStatus.incomplete));
    });

    test('Parses full OBD-II Mode 01 PID 01 response packet with 0x41 0x01 header', () {
      final obdPacket = Uint8List.fromList([0x41, 0x01, 0x00, 0x07, 0xED, 0x00]);
      final result = BmwEcuScanner.parseEmissionsReadinessPayload(obdPacket);
      expect(result.milOn, isFalse);
      expect(result.isReady, isTrue);
      expect(result.passedCount, equals(9));
    });

    test('Parses UDS DID 0xF401 response packet with 0x62 0xF4 0x01 header', () {
      final udsPacket = Uint8List.fromList([0x62, 0xF4, 0x01, 0x00, 0x07, 0xED, 0x00]);
      final result = BmwEcuScanner.parseEmissionsReadinessPayload(udsPacket);
      expect(result.milOn, isFalse);
      expect(result.isReady, isTrue);
      expect(result.passedCount, equals(9));
    });

    test('Identifies unsupported monitors correctly', () {
      // Byte C has secondary air bit 3 = 0 (unsupported)
      final rawPayload = Uint8List.fromList([0x00, 0x07, 0xE5, 0x00]);
      final result = BmwEcuScanner.parseEmissionsReadinessPayload(rawPayload);

      final secAir = result.getMonitor('SECONDARY_AIR')!;
      expect(secAir.isSupported, isFalse);
      expect(secAir.status, equals(MonitorStatus.unsupported));
    });
  });

  group('3. ECU Hardware / Software Identification (DIDs 0xF187..0xF190)', () {
    test('Parses BMW Sachnummer Part Number (DID 0xF187) in ASCII and binary', () {
      // 7-digit ASCII Sachnummer "8688192"
      final asciiBytes = Uint8List.fromList('8688192'.codeUnits);
      expect(BmwEcuScanner.parseSachnummer(asciiBytes), equals('8688192'));

      // 4-byte binary integer: 8688192 = 0x00849240
      final binary4 = Uint8List.fromList([0x00, 0x84, 0x92, 0x40]);
      expect(BmwEcuScanner.parseSachnummer(binary4), equals('8688192'));
    });

    test('Parses HWEL Hardware Electronics version (DID 0xF188)', () {
      // 7-byte binary SVK: ID = 0x00000EB4, Major = 1, Minor = 1, Patch = 1
      final hwelBytes = Uint8List.fromList([0x00, 0x00, 0x0E, 0xB4, 0x01, 0x01, 0x01]);
      final parsed = BmwEcuScanner.parseHwelVersion(hwelBytes);
      expect(parsed, equals('HWEL_00000EB4_001_001_001'));

      // ASCII string format
      final asciiHwel = Uint8List.fromList('HWEL_00000EB4_001.001.001'.codeUnits);
      expect(BmwEcuScanner.parseHwelVersion(asciiHwel), equals('HWEL_00000EB4_001.001.001'));
    });

    test('Parses SWFL Software Application version (DID 0xF189)', () {
      // 7-byte binary SVK: ID = 0x00001B05, Major = 4, Minor = 2, Patch = 0
      final swflBytes = Uint8List.fromList([0x00, 0x00, 0x1B, 0x05, 0x04, 0x02, 0x00]);
      final parsed = BmwEcuScanner.parseSwflVersion(swflBytes);
      expect(parsed, equals('SWFL_00001B05_004_002_000'));

      // ASCII string format
      final asciiSwfl = Uint8List.fromList('SWFL_00001B05_004.002.000'.codeUnits);
      expect(BmwEcuScanner.parseSwflVersion(asciiSwfl), equals('SWFL_00001B05_004.002.000'));
    });

    test('Parses Coding Index (DID 0xF18B)', () {
      // 1-byte Codierindex 0x15 (21)
      final idxBytes = Uint8List.fromList([0x15]);
      expect(BmwEcuScanner.parseCodingIndex(idxBytes), equals('0x15 (21)'));

      // 2-byte Codierindex
      final idx2Bytes = Uint8List.fromList([0x01, 0x02]);
      expect(BmwEcuScanner.parseCodingIndex(idx2Bytes), equals('0x0102 (258)'));
    });

    test('Parses Vehicle Identification Number VIN (DID 0xF190)', () {
      final vinBytes = Uint8List.fromList('WBA3A5C50DF123456'.codeUnits);
      expect(BmwEcuScanner.parseVin(vinBytes), equals('WBA3A5C50DF123456'));
    });

    test('EcuIdentification serializes to JSON with all factory fields', () {
      const id = EcuIdentification(
        ecuAddress: 0x12,
        ecuName: 'DME',
        partNumber: '8688192',
        hwelVersion: 'HWEL_00000EB4_001_001_001',
        swflVersion: 'SWFL_00001B05_004_002_000',
        codingIndex: '0x15 (21)',
        vin: 'WBA3A5C50DF123456',
      );

      final json = id.toJson();
      expect(json['ecuAddress'], equals('0x12'));
      expect(json['ecuName'], equals('DME'));
      expect(json['partNumber'], equals('8688192'));
      expect(json['hwelVersion'], equals('HWEL_00000EB4_001_001_001'));
      expect(json['swflVersion'], equals('SWFL_00001B05_004_002_000'));
      expect(json['codingIndex'], equals('0x15 (21)'));
      expect(json['vin'], equals('WBA3A5C50DF123456'));
    });
  });
}
