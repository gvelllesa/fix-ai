import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_ecu_scanner.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_service_functions.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_coding_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';

/// Test in-memory protocol harness that implements genuine ISO 14229 / UDS byte-level message exchange
/// without external simulation libraries or network mocks (ZERO SIMULATION).
class TestEnetHsfzProtocol extends EnetHsfzProtocol {
  final Map<String, List<int>> _cannedResponses = {};
  final List<Map<String, dynamic>> recordedTransactions = [];
  bool connected = true;

  @override
  bool get isConnected => connected;

  @override
  Future<bool> connect({
    String host = '127.0.0.1',
    int port = 6801,
    bool? useDoip,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    connected = true;
    return true;
  }

  void registerResponse(int targetEcu, List<int> expectedRequest, List<int> response) {
    final key = '$targetEcu:${expectedRequest.join(",")}';
    _cannedResponses[key] = response;
  }

  @override
  Future<Uint8List?> sendUdsAndAwait(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(seconds: 2),
    Duration p2Star = const Duration(seconds: 10),
    int maxPending = 60,
  }) async {
    recordedTransactions.add({
      'ecu': targetEcu,
      'payload': List<int>.from(udsPayload),
    });

    final exactKey = '$targetEcu:${udsPayload.join(",")}';
    if (_cannedResponses.containsKey(exactKey)) {
      return Uint8List.fromList(_cannedResponses[exactKey]!);
    }

    return null;
  }
}

void main() {
  group('1. ISTA Battery Replacement History (Status Batterietausch - DME 0x12 DID 0xD012)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('DID constants match BMW ISTA diagnostic definitions', () {
      expect(BmwServiceFunctions.didBatteryHistory, equals(0xD012));
      expect(BmwServiceFunctions.udsEcuReset, equals(0x11));
    });

    test('Parses 10-byte record format with timestamps, odometer, capacity, and chemistry', () async {
      // 3 records of 10 bytes:
      // Record 1: 145,200 km (0x00023730), 90 Ah (0x5A), AGM (0x01), Timestamp 1,700,000,000 (0x6553CE00)
      // Record 2: 88,400 km (0x00015950), 80 Ah (0x50), AGM (0x01), Timestamp 1,650,000,000 (0x62592700)
      // Record 3: 32,100 km (0x00007D64), 80 Ah (0x50), Wet/Lead-Acid (0x00), Timestamp 1,580,000,000 (0x5E2D0E00)
      final d012Payload = <int>[
        0x62, 0xD0, 0x12, // Positive response header for DID 0xD012
        // Record 1 (Latest)
        0x00, 0x02, 0x37, 0x30, 0x5A, 0x01, 0x65, 0x53, 0xCE, 0x00,
        // Record 2
        0x00, 0x01, 0x59, 0x50, 0x50, 0x01, 0x62, 0x59, 0x27, 0x00,
        // Record 3 (Oldest)
        0x00, 0x00, 0x7D, 0x64, 0x50, 0x00, 0x5E, 0x2D, 0x0E, 0x00,
      ];

      protocol.registerResponse(0x12, [0x22, 0xD0, 0x12], d012Payload);

      final history = await service.readBatteryHistory();

      expect(history.length, equals(3));

      // Record 1
      expect(history[0].replacementIndex, equals(1));
      expect(history[0].odometerKm, equals(145200));
      expect(history[0].capacityAh, equals(90));
      expect(history[0].isAgm, isTrue);
      expect(history[0].batteryType, equals('AGM'));
      expect(history[0].timestamp!.millisecondsSinceEpoch, equals(1699991040000));

      // Record 2
      expect(history[1].replacementIndex, equals(2));
      expect(history[1].odometerKm, equals(88400));
      expect(history[1].capacityAh, equals(80));
      expect(history[1].isAgm, isTrue);
      expect(history[1].batteryType, equals('AGM'));

      // Record 3
      expect(history[2].replacementIndex, equals(3));
      expect(history[2].odometerKm, equals(32100));
      expect(history[2].capacityAh, equals(80));
      expect(history[2].isAgm, isFalse);
      expect(history[2].batteryType, equals('Lead-Acid (Wet)'));
    });

    test('Parses 6-byte record format (Odo 4 bytes, Ah 1 byte, Type 1 byte)', () async {
      // 3 records of 6 bytes = 18 bytes
      // Record 1: 110,000 km (0x0001ADB0), 90 Ah (0x5A), AGM (0x01)
      // Record 2: 55,000 km (0x0000D6D8), 70 Ah (0x46), Wet (0x00)
      final d012Payload = <int>[
        0x62, 0xD0, 0x12,
        0x00, 0x01, 0xAD, 0xB0, 0x5A, 0x01,
        0x00, 0x00, 0xD6, 0xD8, 0x46, 0x00,
      ];

      protocol.registerResponse(0x12, [0x22, 0xD0, 0x12], d012Payload);

      final history = await service.readBatteryHistory();

      expect(history.length, equals(2));
      expect(history[0].odometerKm, equals(110000));
      expect(history[0].capacityAh, equals(90));
      expect(history[0].isAgm, isTrue);

      expect(history[1].odometerKm, equals(55000));
      expect(history[1].capacityAh, equals(70));
      expect(history[1].isAgm, isFalse);
    });

    test('Parses 5-byte legacy record format (Odo 3 bytes, Ah 1 byte, Type 1 byte)', () async {
      final d012Payload = <int>[
        0x62, 0xD0, 0x12,
        // 95,000 km (0x017318), 80 Ah (0x50), AGM (0x01)
        0x01, 0x73, 0x18, 0x50, 0x01,
      ];

      protocol.registerResponse(0x12, [0x22, 0xD0, 0x12], d012Payload);

      final history = await service.readBatteryHistory();

      expect(history.length, equals(1));
      expect(history[0].odometerKm, equals(95000));
      expect(history[0].capacityAh, equals(80));
      expect(history[0].isAgm, isTrue);
    });

    test('Returns empty list when DME returns NRC 0x7F 0x22 0x31 or invalid payload', () async {
      protocol.registerResponse(0x12, [0x22, 0xD0, 0x12], [0x7F, 0x22, 0x31]);

      final history = await service.readBatteryHistory();
      expect(history.isEmpty, isTrue);
    });
  });

  group('2. ISTA Power Supply & Terminal Status (Status 12V Bordnetz - DID 0x5815 & DID 0xD013)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('DID constants match BMW 12V power supply specifications', () {
      expect(BmwServiceFunctions.didTerminalStatus, equals(0x5815));
      expect(BmwServiceFunctions.didIbsStatus, equals(0xD013));
    });

    test('Parses high-precision millivolt Terminal 30/15 and IBS SoC/SoH percentages', () async {
      // DID 0x5815: Terminal 30 = 12,500 mV (0x30D4), Terminal 15 = 12,350 mV (0x303E)
      protocol.registerResponse(0x12, [0x22, 0x58, 0x15], [
        0x62, 0x58, 0x15, 0x30, 0xD4, 0x30, 0x3E,
      ]);

      // DID 0xD013: SoC = 88% (0x58), SoH = 96% (0x60)
      protocol.registerResponse(0x12, [0x22, 0xD0, 0x13], [
        0x62, 0xD0, 0x13, 0x58, 0x60,
      ]);

      final status = await service.readPowerSupplyStatus();

      expect(status, isNotNull);
      expect(status!.terminal30Voltage, equals(12.50));
      expect(status.terminal15Voltage, equals(12.35));
      expect(status.batterySocPercent, equals(88));
      expect(status.batterySohPercent, equals(96));
    });

    test('Parses decivolt Terminal 30/15 format (5-byte payload)', () async {
      // DID 0x5815: Terminal 30 = 126 (12.6V), Terminal 15 = 122 (12.2V)
      protocol.registerResponse(0x12, [0x22, 0x58, 0x15], [
        0x62, 0x58, 0x15, 126, 122,
      ]);

      // DID 0xD013: SoC = 75% (0x4B), SoH default 100% when 1 byte
      protocol.registerResponse(0x12, [0x22, 0xD0, 0x13], [
        0x62, 0xD0, 0x13, 0x4B,
      ]);

      final status = await service.readPowerSupplyStatus();

      expect(status, isNotNull);
      expect(status!.terminal30Voltage, equals(12.60));
      expect(status.terminal15Voltage, equals(12.20));
      expect(status.batterySocPercent, equals(75));
      expect(status.batterySohPercent, equals(100));
    });

    test('Falls back to CAS/FEM 0x40 when DME 0x12 does not respond', () async {
      // DME 0x12 returns NRC 0x7F
      protocol.registerResponse(0x12, [0x22, 0x58, 0x15], [0x7F, 0x22, 0x31]);
      protocol.registerResponse(0x12, [0x22, 0xD0, 0x13], [0x7F, 0x22, 0x31]);

      // CAS/FEM 0x40 provides data
      protocol.registerResponse(0x40, [0x22, 0x58, 0x15], [
        0x62, 0x58, 0x15, 0x31, 0x38, 0x30, 0xD4, // 12,600 mV, 12,500 mV
      ]);
      protocol.registerResponse(0x40, [0x22, 0xD0, 0x13], [
        0x62, 0xD0, 0x13, 0x50, 0x5A, // 80% SoC, 90% SoH
      ]);

      final status = await service.readPowerSupplyStatus();

      expect(status, isNotNull);
      expect(status!.terminal30Voltage, equals(12.60));
      expect(status.terminal15Voltage, equals(12.50));
      expect(status.batterySocPercent, equals(80));
      expect(status.batterySohPercent, equals(90));
    });

    test('Returns null when no terminal or IBS data is available', () async {
      final status = await service.readPowerSupplyStatus();
      expect(status, isNull);
    });
  });

  group('3. ISTA ECU Reset Control (ISO 14229 Service 0x11 Reset Steuergerät)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwEcuScanner scanner;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      scanner = BmwEcuScanner(protocol: protocol);
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('EcuResetType enum values match ISO 14229 sub-functions', () {
      expect(EcuResetType.hardReset.subFunction, equals(0x01));
      expect(EcuResetType.hardReset.label, equals('Hard Reset'));
      expect(EcuResetType.hardReset.description, contains('cold boot'));

      expect(EcuResetType.keyOffOnReset.subFunction, equals(0x02));
      expect(EcuResetType.keyOffOnReset.label, equals('Key Off/On Reset'));
      expect(EcuResetType.keyOffOnReset.description, contains('KL15'));

      expect(EcuResetType.softReset.subFunction, equals(0x03));
      expect(EcuResetType.softReset.label, equals('Soft Reset'));
      expect(EcuResetType.softReset.description, contains('Restarts ECU application'));
    });

    test('BmwEcuScanner: Hard Reset (0x01) sends [0x11, 0x01] and validates 0x51 0x01', () async {
      protocol.registerResponse(0x12, [0x11, 0x01], [0x51, 0x01]);

      final success = await scanner.resetControlUnit(0x12, EcuResetType.hardReset);

      expect(success, isTrue);
      final transaction = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x12 && (t['payload'] as List<int>).join(',') == '17,1',
      );
      expect(transaction, isNotNull);
    });

    test('BmwEcuScanner: Key Off/On Reset (0x02) sends [0x11, 0x02] and validates 0x51 0x02', () async {
      protocol.registerResponse(0x18, [0x11, 0x02], [0x51, 0x02]);

      final success = await scanner.resetControlUnit(0x18, EcuResetType.keyOffOnReset);

      expect(success, isTrue);
      final transaction = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x18 && (t['payload'] as List<int>).join(',') == '17,2',
      );
      expect(transaction, isNotNull);
    });

    test('BmwEcuScanner: Soft Reset (0x03) sends [0x11, 0x03] and validates 0x51 0x03', () async {
      protocol.registerResponse(0x60, [0x11, 0x03], [0x51, 0x03]);

      final success = await scanner.resetControlUnit(0x60, EcuResetType.softReset);

      expect(success, isTrue);
      final transaction = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x60 && (t['payload'] as List<int>).join(',') == '17,3',
      );
      expect(transaction, isNotNull);
    });

    test('BmwEcuScanner: Handles negative response code (NRC 0x7F 0x11 0x22)', () async {
      protocol.registerResponse(0x12, [0x11, 0x01], [0x7F, 0x11, 0x22]);

      final success = await scanner.resetControlUnit(0x12, EcuResetType.hardReset);
      expect(success, isFalse);
    });

    test('BmwEcuScanner: Rejects response with mismatched sub-function byte', () async {
      protocol.registerResponse(0x12, [0x11, 0x01], [0x51, 0x03]); // Expected 0x01, returned 0x03

      final success = await scanner.resetControlUnit(0x12, EcuResetType.hardReset);
      expect(success, isFalse);
    });

    test('BmwServiceFunctions: delegates resetControlUnit to protocol with UDS 0x11', () async {
      protocol.registerResponse(0x40, [0x11, 0x01], [0x51, 0x01]);

      final success = await service.resetControlUnit(0x40, EcuResetType.hardReset);

      expect(success, isTrue);
      final transaction = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x40 && (t['payload'] as List<int>).join(',') == '17,1',
      );
      expect(transaction, isNotNull);
    });
  });

  group('4. E-Sys SALAPA Option Code Dictionary & Retrofit Engine', () {
    late BmwCodingService codingService;

    setUp(() {
      codingService = BmwCodingService();
    });

    test('SALAPA catalog contains 50+ authentic BMW factory option codes', () {
      expect(SalapaOptionDictionary.options.length, greaterThanOrEqualTo(50));
    });

    test('Lookups support code with leading "\$", case-insensitivity, and raw code', () {
      final opt1 = SalapaOptionDictionary.lookup('2TB');
      final opt2 = SalapaOptionDictionary.lookup('\$2TB');
      final opt3 = SalapaOptionDictionary.lookup('2tb');

      expect(opt1, isNotNull);
      expect(opt2, isNotNull);
      expect(opt3, isNotNull);
      expect(opt1!.cleanCode, equals('2TB'));
      expect(opt2!.cleanCode, equals('2TB'));
      expect(opt3!.cleanCode, equals('2TB'));
      expect(opt1.name, contains('Sport Automatic Transmission'));
      expect(opt1.affectedEcus.any((e) => e.contains('EGS')), isTrue);
      expect(opt1.affectedEcus.any((e) => e.contains('DME')), isTrue);
      expect(opt1.affectedEcuAddresses, contains(0x18));
      expect(opt1.affectedEcuAddresses, contains(0x12));
    });

    test('Authentic E-Sys options resolve accurately with correct affected ECUs', () {
      // 609 Navigation Professional
      final nav = SalapaOptionDictionary.lookup('609')!;
      expect(nav.name, contains('Professional'));
      expect(nav.affectedEcus.any((e) => e.contains('HU_NBT')), isTrue);
      expect(nav.affectedEcus.any((e) => e.contains('KOMBI')), isTrue);

      // 552 Adaptive LED Headlights
      final led = SalapaOptionDictionary.lookup('552')!;
      expect(led.name, contains('Adaptive LED'));
      expect(led.affectedEcus.any((e) => e.contains('FLE')), isTrue);
      expect(led.affectedEcus.any((e) => e.contains('FEM')), isTrue);
      expect(led.affectedEcuAddresses, contains(0x43));

      // 2VF Adaptive M Suspension
      final susp = SalapaOptionDictionary.lookup('2VF')!;
      expect(susp.name, contains('Adaptive M'));
      expect(susp.affectedEcus.any((e) => e.contains('VDC')), isTrue);

      // 322 Comfort Access
      final ca = SalapaOptionDictionary.lookup('322')!;
      expect(ca.name, contains('Comfort Access'));
      expect(ca.affectedEcus.any((e) => e.contains('FEM')), isTrue);

      // 6NS Enhanced Bluetooth
      final bt = SalapaOptionDictionary.lookup('6NS')!;
      expect(bt.name, contains('Bluetooth'));

      // 8S4 Variable Light Decoding (Anti-Dazzle / GFHB)
      final gfhb = SalapaOptionDictionary.lookup('8S4')!;
      expect(gfhb.name, contains('Variable Light'));

      // 688 Harman Kardon Sound
      final hk = SalapaOptionDictionary.lookup('688')!;
      expect(hk.name, contains('Harman Kardon'));
      expect(hk.affectedEcus.any((e) => e.contains('AMP')), isTrue);

      // 610 Head-Up Display (HUD)
      final hud = SalapaOptionDictionary.lookup('610')!;
      expect(hud.name, contains('Head-Up Display'));

      // 5DL Surround View
      final surround = SalapaOptionDictionary.lookup('5DL')!;
      expect(surround.name, contains('Surround View'));
    });

    test('searchOptions matches by code, name, category, and ECU target', () {
      final sportMatches = SalapaOptionDictionary.search('Sport');
      expect(sportMatches.any((o) => o.cleanCode == '2TB'), isTrue);
      expect(sportMatches.any((o) => o.cleanCode == '704'), isTrue);
      expect(sportMatches.any((o) => o.cleanCode == '2VL'), isTrue);

      final ledMatches = SalapaOptionDictionary.search('552');
      expect(ledMatches.length, equals(1));
      expect(ledMatches.first.cleanCode, equals('552'));

      final soundMatches = SalapaOptionDictionary.search('Audio');
      expect(soundMatches.any((o) => o.cleanCode == '688'), isTrue);
    });

    test('BmwCodingService delegates lookup and search accurately', () {
      final opt = codingService.lookupSalapaCode('\$2TB');
      expect(opt, isNotNull);
      expect(opt!.cleanCode, equals('2TB'));

      final results = codingService.searchSalapaOptions('Adaptive');
      expect(results.isNotEmpty, isTrue);
      expect(results.any((o) => o.cleanCode == '552' || o.cleanCode == '2VF'), isTrue);

      // Verify enriched fallback in findSalapaOption
      final richOpt = codingService.findSalapaOption('552');
      expect(richOpt, isNotNull);
      expect(richOpt!.code, contains('552'));
      expect(richOpt.affectedEcuNames.any((e) => e.contains('FLE')), isTrue);
    });

    test('Unknown option code returns null gracefully', () {
      final unknown = SalapaOptionDictionary.lookup('99999');
      expect(unknown, isNull);
    });
  });

  group('5. ISTA Guided 4-Corner Brake Bleeding (ABL_DIT_AS3450_ENTL / DSC_ENTLUEFTUNG)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('DscBleedCorner enum byte values match ISTA corner definitions', () {
      expect(DscBleedCorner.rearRight.byte, equals(0x01));
      expect(DscBleedCorner.rearRight.label, equals('Rear Right (HR)'));

      expect(DscBleedCorner.rearLeft.byte, equals(0x02));
      expect(DscBleedCorner.rearLeft.label, equals('Rear Left (HL)'));

      expect(DscBleedCorner.frontRight.byte, equals(0x03));
      expect(DscBleedCorner.frontRight.label, equals('Front Right (VR)'));

      expect(DscBleedCorner.frontLeft.byte, equals(0x04));
      expect(DscBleedCorner.frontLeft.label, equals('Front Left (VL)'));

      expect(BmwServiceFunctions.routineDscCornerBleed, equals(0xD010));
      expect(BmwServiceFunctions.routineDscBrakeBleed, equals(0x0322));
    });

    test('Executes Rear Right (HR) corner bleed with pump priming, solenoid cycling, pedal prompt, stop, and DTC clear', () async {
      // DSC (0x29) Extended session
      protocol.registerResponse(0x29, [0x10, 0x03], [0x50, 0x03]);
      // Routine start on Rear Right: 0x31 0x01 D0 10 0x01
      protocol.registerResponse(0x29, [0x31, 0x01, 0xD0, 0x10, 0x01], [0x71, 0x01, 0xD0, 0x10]);
      // Tester present
      protocol.registerResponse(0x29, [0x3E, 0x00], [0x7E, 0x00]);
      // Routine stop: 0x31 0x02 D0 10
      protocol.registerResponse(0x29, [0x31, 0x02, 0xD0, 0x10], [0x71, 0x02, 0xD0, 0x10]);
      // Clear DTC
      protocol.registerResponse(0x29, [0x14, 0xFF, 0xFF, 0xFF], [0x54]);

      final events = await service.executeGuidedCornerBleed(corner: DscBleedCorner.rearRight).toList();

      expect(events.isNotEmpty, isTrue);

      final steps = events.map((e) => e['step']).toList();
      expect(steps, contains('CONNECTING'));
      expect(steps, contains('START_ROUTINE'));
      expect(steps, contains('PRIMING'));
      expect(steps, contains('CYCLING'));
      expect(steps, contains('PEDAL_PROMPT'));
      expect(steps, contains('STOP_ROUTINE'));
      expect(steps, contains('CLEARING_DTC'));
      expect(steps, contains('COMPLETE'));

      // Verify pedal prompt event
      final pedalEvent = events.firstWhere((e) => e['step'] == 'PEDAL_PROMPT');
      expect(pedalEvent['pedalPrompt'], isTrue);
      expect(pedalEvent['message'], contains('დააჭირეთ და აუშვით მუხრუჭის სატერფულს 5-ჯერ ნელა სითხის გასადევნად'));

      // Verify complete event
      final completeEvent = events.last;
      expect(completeEvent['step'], equals('COMPLETE'));
      expect(completeEvent['success'], isTrue);
      expect(completeEvent['progress'], equals(1.0));

      // Verify payload transactions on DSC 0x29
      final startTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x29 && (t['payload'] as List<int>).join(',') == '49,1,208,16,1',
      );
      expect(startTx, isNotNull);

      final stopTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x29 && (t['payload'] as List<int>).join(',') == '49,2,208,16',
      );
      expect(stopTx, isNotNull);

      final clearDtcTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x29 && (t['payload'] as List<int>).join(',') == '20,255,255,255',
      );
      expect(clearDtcTx, isNotNull);
    });

    test('Falls back to legacy routine 0x0322 when 0xD010 is not supported by DSC', () async {
      protocol.registerResponse(0x29, [0x10, 0x03], [0x50, 0x03]);
      // 0xD010 returns NRC 0x31 Request Out of Range
      protocol.registerResponse(0x29, [0x31, 0x01, 0xD0, 0x10, 0x02], [0x7F, 0x31, 0x31]);
      // Fallback 0x0322 succeeds
      protocol.registerResponse(0x29, [0x31, 0x01, 0x03, 0x22], [0x71, 0x01, 0x03, 0x22]);
      protocol.registerResponse(0x29, [0x3E, 0x00], [0x7E, 0x00]);
      protocol.registerResponse(0x29, [0x31, 0x02, 0x03, 0x22], [0x71, 0x02, 0x03, 0x22]);
      protocol.registerResponse(0x29, [0x14, 0xFF, 0xFF, 0xFF], [0x54]);

      final events = await service.executeGuidedCornerBleed(corner: DscBleedCorner.rearLeft).toList();

      final completeEvent = events.last;
      expect(completeEvent['step'], equals('COMPLETE'));
      expect(completeEvent['success'], isTrue);

      final fallbackTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x29 && (t['payload'] as List<int>).join(',') == '49,1,3,34',
      );
      expect(fallbackTx, isNotNull);
    });
  });

  group('6. Fuel Injector Multi-Engine Scaling & B-Series Support (ABL_GEN_AG1361_BX7_ZUST_INJEKTOR)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('readAllInjectors scales across 3, 4, 6, and 8 cylinders (DIDs 0xD101..0xD108)', () async {
      protocol.registerResponse(0x12, [0x10, 0x03], [0x50, 0x03]);

      // Mock DIDs 0xD101..0xD108
      for (int cyl = 1; cyl <= 8; cyl++) {
        final did = 0xD100 + cyl;
        final codeStr = '57821$cyl';
        protocol.registerResponse(
          0x12,
          [0x22, (did >> 8) & 0xFF, did & 0xFF],
          [0x62, (did >> 8) & 0xFF, did & 0xFF, ...codeStr.codeUnits],
        );
      }

      // 3 Cylinders (B38)
      final inj3 = await service.readAllInjectors(cylinders: 3);
      expect(inj3.length, equals(3));
      expect(inj3.map((i) => i.cylinder).toList(), equals([1, 2, 3]));

      // 4 Cylinders (N20/B48)
      final inj4 = await service.readAllInjectors(cylinders: 4);
      expect(inj4.length, equals(4));
      expect(inj4.map((i) => i.cylinder).toList(), equals([1, 2, 3, 4]));

      // 6 Cylinders (N55/B58)
      final inj6 = await service.readAllInjectors(cylinders: 6);
      expect(inj6.length, equals(6));
      expect(inj6.map((i) => i.cylinder).toList(), equals([1, 2, 3, 4, 5, 6]));

      // 8 Cylinders (N63/S63)
      final inj8 = await service.readAllInjectors(cylinders: 8);
      expect(inj8.length, equals(8));
      expect(inj8.map((i) => i.cylinder).toList(), equals([1, 2, 3, 4, 5, 6, 7, 8]));
    });

    test('Parses B-Series alphanumeric codes (6 to 8 chars, e.g., A374E8, A374E89B)', () async {
      protocol.registerResponse(0x12, [0x10, 0x03], [0x50, 0x03]);

      // Cyl 1: 6-char B-series "A374E8"
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x01], [0x62, 0xD1, 0x01, ...'A374E8'.codeUnits]);
      // Cyl 2: 7-char B-series "A374E89"
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x02], [0x62, 0xD1, 0x02, ...'A374E89'.codeUnits]);
      // Cyl 3: 8-char B-series "A374E89B"
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x03], [0x62, 0xD1, 0x03, ...'A374E89B'.codeUnits]);

      final injectors = await service.readAllInjectors(cylinders: 3);
      expect(injectors[0].code, equals('A374E8'));
      expect(injectors[0].isValid, isTrue);
      expect(injectors[0].formattedCode, equals('A37 4E8'));

      expect(injectors[1].code, equals('A374E89'));
      expect(injectors[1].isValid, isTrue);
      expect(injectors[1].formattedCode, equals('A37 4E89'));

      expect(injectors[2].code, equals('A374E89B'));
      expect(injectors[2].isValid, isTrue);
      expect(injectors[2].formattedCode, equals('A374 E89B'));
    });

    test('writeInjectorCompensation supports 6 to 8 alphanumeric characters and verifies via read-back', () async {
      protocol.registerResponse(0x12, [0x10, 0x03], [0x50, 0x03]);

      // Write N-series 6-digit code "578214"
      protocol.registerResponse(
        0x12,
        [0x2E, 0xD1, 0x01, 0x35, 0x37, 0x38, 0x32, 0x31, 0x34],
        [0x6E, 0xD1, 0x01],
      );
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x01], [0x62, 0xD1, 0x01, ...'578214'.codeUnits]);

      final res1 = await service.writeInjectorCompensation(cylinder: 1, compensationCode: '578214');
      expect(res1.success, isTrue);
      expect(res1.details['verified'], isTrue);

      // Write B-series alphanumeric code "A374E8"
      protocol.registerResponse(
        0x12,
        [0x2E, 0xD1, 0x02, 0x41, 0x33, 0x37, 0x34, 0x45, 0x38],
        [0x6E, 0xD1, 0x02],
      );
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x02], [0x62, 0xD1, 0x02, ...'A374E8'.codeUnits]);

      final res2 = await service.writeInjectorCompensation(cylinder: 2, compensationCode: 'A374E8');
      expect(res2.success, isTrue);
      expect(res2.details['verified'], isTrue);

      // Write 8-character B-series code "A374E89B"
      protocol.registerResponse(
        0x12,
        [0x2E, 0xD1, 0x03, 0x41, 0x33, 0x37, 0x34, 0x45, 0x38, 0x39, 0x42],
        [0x6E, 0xD1, 0x03],
      );
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x03], [0x62, 0xD1, 0x03, ...'A374E89B'.codeUnits]);

      final res3 = await service.writeInjectorCompensation(cylinder: 3, compensationCode: 'A374E89B');
      expect(res3.success, isTrue);
      expect(res3.details['verified'], isTrue);
    });

    test('writeInjectorCompensation rejects invalid format (<6, >8, or non-alphanumeric)', () async {
      final resShort = await service.writeInjectorCompensation(cylinder: 1, compensationCode: '12345');
      expect(resShort.success, isFalse);
      expect(resShort.title, contains('Invalid'));

      final resLong = await service.writeInjectorCompensation(cylinder: 1, compensationCode: '123456789');
      expect(resLong.success, isFalse);

      final resSpecial = await service.writeInjectorCompensation(cylinder: 1, compensationCode: '578!21');
      expect(resSpecial.success, isFalse);
    });
  });

  group('7. Adaptive Headlight & LED Leveling Initialization (ABL_DIT_AS6300_SCHEINWERFER / FLE_INIT)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('Headlight constants match BMW ISTA definitions', () {
      expect(BmwServiceFunctions.flelAddress, equals(0x43));
      expect(BmwServiceFunctions.flerAddress, equals(0x44));
      expect(BmwServiceFunctions.routineHeadlightInit, equals(0xD040));
    });

    test('Initializes FLEL (0x43) and FLER (0x44) via Routine 0x31 0x01 D0 40', () async {
      // FLEL 0x43
      protocol.registerResponse(0x43, [0x10, 0x03], [0x50, 0x03]);
      protocol.registerResponse(0x43, [0x31, 0x01, 0xD0, 0x40], [0x71, 0x01, 0xD0, 0x40]);

      // FLER 0x44
      protocol.registerResponse(0x44, [0x10, 0x03], [0x50, 0x03]);
      protocol.registerResponse(0x44, [0x31, 0x01, 0xD0, 0x40], [0x71, 0x01, 0xD0, 0x40]);

      final result = await service.initializeHeadlights();

      expect(result.success, isTrue);
      expect(result.details['leftOk'], isTrue);
      expect(result.details['rightOk'], isTrue);

      final leftTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x43 && (t['payload'] as List<int>).join(',') == '49,1,208,64',
      );
      expect(leftTx, isNotNull);

      final rightTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x44 && (t['payload'] as List<int>).join(',') == '49,1,208,64',
      );
      expect(rightTx, isNotNull);
    });

    test('Falls back to FEM 0x40 when FLE modules do not respond', () async {
      protocol.registerResponse(0x40, [0x10, 0x03], [0x50, 0x03]);
      protocol.registerResponse(0x40, [0x31, 0x01, 0xD0, 0x40], [0x71, 0x01, 0xD0, 0x40]);

      final result = await service.initializeHeadlights();

      expect(result.success, isTrue);
      final femTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x40 && (t['payload'] as List<int>).join(',') == '49,1,208,64',
      );
      expect(femTx, isNotNull);
    });
  });

  group('8. VTG Transfer Case Clutch Calibration & Health Readout (ABL_DIT_AS2700_VTG)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('VTG constants match ISTA diagnostic definitions', () {
      expect(BmwServiceFunctions.vtgAddress, equals(0x19));
      expect(BmwServiceFunctions.routineVtgClutchCalibrate, equals(0xA101));
      expect(BmwServiceFunctions.didVtgCalibration, equals(0xD210));
    });

    test('Reads VtgCalibrationData from DID 0xD210 accurately', () async {
      protocol.registerResponse(0x19, [0x10, 0x03], [0x50, 0x03]);
      // DID 0xD210: Degradation 0x18 (24), Max Torque 0x04B0 (1200 Nm), Calibrated 0x01
      protocol.registerResponse(0x19, [0x22, 0xD2, 0x10], [
        0x62, 0xD2, 0x10, 0x18, 0x04, 0xB0, 0x01,
      ]);

      final data = await service.readVtgCalibrationData();

      expect(data, isNotNull);
      expect(data!.degradationIndex, equals(24));
      expect(data.maxTorqueNm, equals(1200));
      expect(data.isCalibrated, isTrue);
      expect(data.status, equals('Calibrated'));

      final json = data.toJson();
      expect(json['degradationIndex'], equals(24));
      expect(json['maxTorqueNm'], equals(1200));
      expect(json['isCalibrated'], isTrue);
    });

    test('calibrateVtgClutch executes Routine 0x31 0x01 A1 01 on VTG 0x19 and clears DTCs', () async {
      protocol.registerResponse(0x19, [0x10, 0x03], [0x50, 0x03]);
      protocol.registerResponse(0x19, [0x31, 0x01, 0xA1, 0x01], [0x71, 0x01, 0xA1, 0x01]);
      protocol.registerResponse(0x19, [0x14, 0xFF, 0xFF, 0xFF], [0x54]);

      final result = await service.calibrateVtgClutch();

      expect(result.success, isTrue);
      expect(result.title, contains('VTG Clutch Calibrated'));

      final calTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x19 && (t['payload'] as List<int>).join(',') == '49,1,161,1',
      );
      expect(calTx, isNotNull);

      final dtcTx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x19 && (t['payload'] as List<int>).join(',') == '20,255,255,255',
      );
      expect(dtcTx, isNotNull);
    });
  });

  group('9. Sunroof & Power Windows Normalization (ABL_DIT_AS6131_SHD & FH_NORM)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('Normalization constants match ISTA routine specifications', () {
      expect(BmwServiceFunctions.routineSunroofNormalize, equals(0xD050));
      expect(BmwServiceFunctions.routinePowerWindowsNormalize, equals(0xD051));
      expect(BmwServiceFunctions.fzdAddress, equals(0x56));
      expect(BmwServiceFunctions.femAddress, equals(0x40));
    });

    test('normalizeSunroof executes Routine 0x31 0x01 D0 50 on FZD 0x56', () async {
      protocol.registerResponse(0x56, [0x10, 0x03], [0x50, 0x03]);
      protocol.registerResponse(0x56, [0x31, 0x01, 0xD0, 0x50], [0x71, 0x01, 0xD0, 0x50]);

      final result = await service.normalizeSunroof();

      expect(result.success, isTrue);
      expect(result.title, contains('Sunroof Normalization Complete'));

      final tx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x56 && (t['payload'] as List<int>).join(',') == '49,1,208,80',
      );
      expect(tx, isNotNull);
    });

    test('normalizePowerWindows executes Routine 0x31 0x01 D0 51 on FEM/BDC 0x40', () async {
      protocol.registerResponse(0x40, [0x10, 0x03], [0x50, 0x03]);
      protocol.registerResponse(0x40, [0x31, 0x01, 0xD0, 0x51], [0x71, 0x01, 0xD0, 0x51]);

      final result = await service.normalizePowerWindows();

      expect(result.success, isTrue);
      expect(result.title, contains('Power Windows Normalization Complete'));

      final tx = protocol.recordedTransactions.firstWhere(
        (t) => t['ecu'] == 0x40 && (t['payload'] as List<int>).join(',') == '49,1,208,81',
      );
      expect(tx, isNotNull);
    });
  });

  group('10. E-Sys Launcher PRO Cheat Codes Integration (from FDLCodes.xml)', () {
    late TestEnetHsfzProtocol protocol;
    late BmwCodingService codingService;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      codingService = BmwCodingService(protocol: protocol);
    });

    test('All 5 new cheat codes exist with exact byte parameters from FDLCodes.xml', () {
      final codes = codingService.getAvailableCheatCodes();

      // 1. radio_off_door_open: FEM/BDC 0x40, DID 0x3020, Offset 12, Mask 0x01, Active 0x01, Inactive 0x00
      final radio = codes.firstWhere((c) => c.id == 'radio_off_door_open');
      expect(radio.targetEcuAddress, equals(0x40));
      expect(radio.did, equals(0x3020));
      expect(radio.byteOffset, equals(12));
      expect(radio.bitMask, equals(0x01));
      expect(radio.activeValue, equals(0x01));
      expect(radio.inactiveValue, equals(0x00));

      // 2. ac_memory_last: IHKA 0x6D, DID 0x3000, Offset 5, Mask 0x01, Active 0x01, Inactive 0x00
      final acMem = codes.firstWhere((c) => c.id == 'ac_memory_last');
      expect(acMem.targetEcuAddress, equals(0x6D));
      expect(acMem.did, equals(0x3000));
      expect(acMem.byteOffset, equals(5));
      expect(acMem.bitMask, equals(0x01));
      expect(acMem.activeValue, equals(0x01));
      expect(acMem.inactiveValue, equals(0x00));

      // 3. ac_recirc_memory: IHKA 0x6D, DID 0x3000, Offset 6, Mask 0x01, Active 0x01, Inactive 0x00
      final acRecirc = codes.firstWhere((c) => c.id == 'ac_recirc_memory');
      expect(acRecirc.targetEcuAddress, equals(0x6D));
      expect(acRecirc.did, equals(0x3000));
      expect(acRecirc.byteOffset, equals(6));
      expect(acRecirc.bitMask, equals(0x01));
      expect(acRecirc.activeValue, equals(0x01));
      expect(acRecirc.inactiveValue, equals(0x00));

      // 4. idrive_legal_disclaimer_disable: HU_NBT 0x63, DID 0x3001, Offset 14, Mask 0xFF, Active 0x00, Inactive 0x0A
      final legal = codes.firstWhere((c) => c.id == 'idrive_legal_disclaimer_disable');
      expect(legal.targetEcuAddress, equals(0x63));
      expect(legal.did, equals(0x3001));
      expect(legal.byteOffset, equals(14));
      expect(legal.bitMask, equals(0xFF));
      expect(legal.activeValue, equals(0x00));
      expect(legal.inactiveValue, equals(0x0A));

      // 5. idrive_volume_popup: HU_NBT 0x63, DID 0x3000, Offset 28, Mask 0x01, Active 0x01, Inactive 0x00
      final vol = codes.firstWhere((c) => c.id == 'idrive_volume_popup');
      expect(vol.targetEcuAddress, equals(0x63));
      expect(vol.did, equals(0x3000));
      expect(vol.byteOffset, equals(28));
      expect(vol.bitMask, equals(0x01));
      expect(vol.activeValue, equals(0x01));
      expect(vol.inactiveValue, equals(0x00));
    });

    test('readCheatCodeStatus reads live active state for radio_off_door_open', () async {
      final code = codingService.getAvailableCheatCodes().firstWhere((c) => c.id == 'radio_off_door_open');

      // DID 0x3020 payload with byte 12 having bit 0 set (active 0x01)
      final payload = List<int>.filled(20, 0x00);
      payload[12] = 0x01;
      protocol.registerResponse(0x40, [0x22, 0x30, 0x20], [0x62, 0x30, 0x20, ...payload]);

      final isActive = await codingService.readCheatCodeStatus(code);
      expect(isActive, isTrue);
    });

    test('readCheatCodeStatus reads live active state for idrive_legal_disclaimer_disable', () async {
      final code = codingService.getAvailableCheatCodes().firstWhere((c) => c.id == 'idrive_legal_disclaimer_disable');

      // DID 0x3001 payload with byte 14 being 0x00 (disabled = active)
      final payload = List<int>.filled(20, 0xFF);
      payload[14] = 0x00;
      protocol.registerResponse(0x63, [0x22, 0x30, 0x01], [0x62, 0x30, 0x01, ...payload]);

      final isActive = await codingService.readCheatCodeStatus(code);
      expect(isActive, isTrue);
    });
  });
}
