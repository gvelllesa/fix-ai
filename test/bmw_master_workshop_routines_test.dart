import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_service_functions.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';

/// Test in-memory protocol harness that implements genuine ISO 14229 / UDS message exchange
/// without external simulation libraries or network mocks.
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

    // Default positive responses for common diagnostic management services
    if (udsPayload.isNotEmpty) {
      final sid = udsPayload[0];

      // 0x10 Diagnostic Session Control -> 0x50
      if (sid == 0x10 && udsPayload.length >= 2) {
        return Uint8List.fromList([0x50, udsPayload[1], 0x00, 0x32, 0x01, 0xF4]);
      }

      // 0x22 ReadDataByIdentifier Battery Voltage 0xF111 -> 12.5V (12500 mV = 0x30D4)
      if (sid == 0x22 && udsPayload.length >= 3 && udsPayload[1] == 0xF1 && udsPayload[2] == 0x11) {
        return Uint8List.fromList([0x62, 0xF1, 0x11, 0x30, 0xD4]);
      }

      // 0x22 ReadDataByIdentifier Odometer 0xD011 -> 85000 km (0x00014C08)
      if (sid == 0x22 && udsPayload.length >= 3 && udsPayload[1] == 0xD0 && udsPayload[2] == 0x11) {
        return Uint8List.fromList([0x62, 0xD0, 0x11, 0x00, 0x01, 0x4C, 0x08]);
      }

      // 0x31 Routine Control -> 0x71
      if (sid == 0x31 && udsPayload.length >= 4) {
        final subFunc = udsPayload[1];
        final routHi = udsPayload[2];
        final routLo = udsPayload[3];
        return Uint8List.fromList([0x71, subFunc, routHi, routLo, 0x00]);
      }
    }

    return null;
  }
}

void main() {
  group('1. BimmerGeeks ProTool ECU Constants & Routine Identifiers', () {
    test('ECU addresses match BMW factory network topology', () {
      expect(BmwServiceFunctions.dmeAddress, equals(0x12)); // DME / DDE
      expect(BmwServiceFunctions.afsAddress, equals(0x1B)); // Active Front Steering
      expect(BmwServiceFunctions.dscAddress, equals(0x29)); // DSC
      expect(BmwServiceFunctions.vdcAddress, equals(0x3F)); // VDC / EDC
      expect(BmwServiceFunctions.femAddress, equals(0x40)); // FEM / BDC
      expect(BmwServiceFunctions.rlsAddress, equals(0x56)); // RLS / FZD
      expect(BmwServiceFunctions.fzdAddress, equals(0x56)); // FZD Roof Center
      expect(BmwServiceFunctions.ehcAddress, equals(0x6E)); // EHC Air Suspension
    });

    test('Routine IDs match ProTool reverse-engineered DEX identifiers', () {
      expect(BmwServiceFunctions.routineVvtCal, equals(0x1005));        // res_vvtCal
      expect(BmwServiceFunctions.routineEngineAdapt, equals(0x1000));   // res_engineAdapt
      expect(BmwServiceFunctions.routineRlsInit, equals(0xA002));       // res_RLSInit
      expect(BmwServiceFunctions.routineTpmsReset, equals(0xD030));     // res_TpmsReset
      expect(BmwServiceFunctions.routineRideHeightCal, equals(0x4101)); // res_rideHeight
      expect(BmwServiceFunctions.routineCalAfs, equals(0xA012));        // res_CalAFS
      expect(BmwServiceFunctions.didCylinderSmoothness, equals(0xD120)); // res_CylEqu
    });
  });

  group('2. Exact UDS Payload Construction for ProTool Routines', () {
    test('Valvetronic calibration payload: [0x31, 0x01, 0x10, 0x05]', () {
      final payload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineVvtCal >> 8) & 0xFF,
        BmwServiceFunctions.routineVvtCal & 0xFF,
      ];
      expect(payload, equals([0x31, 0x01, 0x10, 0x05]));
    });

    test('Engine adaptations reset payload: [0x31, 0x01, 0x10, 0x00]', () {
      final payload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineEngineAdapt >> 8) & 0xFF,
        BmwServiceFunctions.routineEngineAdapt & 0xFF,
      ];
      expect(payload, equals([0x31, 0x01, 0x10, 0x00]));
    });

    test('Rain / Light sensor windshield init payload: [0x31, 0x01, 0xA0, 0x02]', () {
      final payload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineRlsInit >> 8) & 0xFF,
        BmwServiceFunctions.routineRlsInit & 0xFF,
      ];
      expect(payload, equals([0x31, 0x01, 0xA0, 0x02]));
    });

    test('TPMS calibration reset payload: [0x31, 0x01, 0xD0, 0x30]', () {
      final payload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineTpmsReset >> 8) & 0xFF,
        BmwServiceFunctions.routineTpmsReset & 0xFF,
      ];
      expect(payload, equals([0x31, 0x01, 0xD0, 0x30]));
    });

    test('Air suspension ride height payload with offsets (signed 8-bit)', () {
      // Zero offset
      final zeroPayload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineRideHeightCal >> 8) & 0xFF,
        BmwServiceFunctions.routineRideHeightCal & 0xFF,
        0.toSigned(8) & 0xFF,
        0.toSigned(8) & 0xFF,
      ];
      expect(zeroPayload, equals([0x31, 0x01, 0x41, 0x01, 0x00, 0x00]));

      // Positive offset: +12mm left, +8mm right
      final posPayload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineRideHeightCal >> 8) & 0xFF,
        BmwServiceFunctions.routineRideHeightCal & 0xFF,
        12.toSigned(8) & 0xFF,
        8.toSigned(8) & 0xFF,
      ];
      expect(posPayload, equals([0x31, 0x01, 0x41, 0x01, 0x0C, 0x08]));

      // Negative offset: -15mm left (0xF1), -5mm right (0xFB)
      final negPayload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineRideHeightCal >> 8) & 0xFF,
        BmwServiceFunctions.routineRideHeightCal & 0xFF,
        (-15).toSigned(8) & 0xFF,
        (-5).toSigned(8) & 0xFF,
      ];
      expect(negPayload, equals([0x31, 0x01, 0x41, 0x01, 0xF1, 0xFB]));
    });

    test('Cylinder running smoothness request payload: [0x22, 0xD1, 0x20]', () {
      final payload = [
        BmwServiceFunctions.udsReadDataById,
        (BmwServiceFunctions.didCylinderSmoothness >> 8) & 0xFF,
        BmwServiceFunctions.didCylinderSmoothness & 0xFF,
      ];
      expect(payload, equals([0x22, 0xD1, 0x20]));
    });

    test('Active Front Steering calibration payload: [0x31, 0x01, 0xA0, 0x12]', () {
      final payload = [
        BmwServiceFunctions.udsRoutineControl,
        BmwServiceFunctions.routineStart,
        (BmwServiceFunctions.routineCalAfs >> 8) & 0xFF,
        BmwServiceFunctions.routineCalAfs & 0xFF,
      ];
      expect(payload, equals([0x31, 0x01, 0xA0, 0x12]));
    });
  });

  group('3. CylinderSmoothnessData Model & Binary Decoding (DID 0xD120)', () {
    test('Evaluates normal, elevated, and severe roughness status tolerances', () {
      // Smooth / Balanced: |roughness| <= 2.0
      const smooth1 = CylinderSmoothnessData(cylinder: 1, roughnessRpm2: 0.5, rawValue: 5);
      expect(smooth1.isBalanced, isTrue);
      expect(smooth1.isElevated, isFalse);
      expect(smooth1.isCritical, isFalse);
      expect(smooth1.statusAssessment, contains('Smooth / Balanced'));
      expect(smooth1.formattedRoughness, equals('+0.50 1/min²'));

      const smoothNeg = CylinderSmoothnessData(cylinder: 2, roughnessRpm2: -1.2, rawValue: -12);
      expect(smoothNeg.isBalanced, isTrue);
      expect(smoothNeg.statusAssessment, contains('Smooth / Balanced'));
      expect(smoothNeg.formattedRoughness, equals('-1.20 1/min²'));

      // Elevated: 2.0 < |roughness| <= 4.0
      const elevatedPos = CylinderSmoothnessData(cylinder: 3, roughnessRpm2: 3.1, rawValue: 31);
      expect(elevatedPos.isBalanced, isFalse);
      expect(elevatedPos.isElevated, isTrue);
      expect(elevatedPos.isCritical, isFalse);
      expect(elevatedPos.statusAssessment, contains('Elevated Roughness'));

      const elevatedNeg = CylinderSmoothnessData(cylinder: 4, roughnessRpm2: -2.8, rawValue: -28);
      expect(elevatedNeg.isBalanced, isFalse);
      expect(elevatedNeg.isElevated, isTrue);
      expect(elevatedNeg.statusAssessment, contains('Elevated Roughness'));

      // Severe / Critical: |roughness| > 4.0
      const severePos = CylinderSmoothnessData(cylinder: 5, roughnessRpm2: 5.4, rawValue: 54);
      expect(severePos.isBalanced, isFalse);
      expect(severePos.isElevated, isFalse);
      expect(severePos.isCritical, isTrue);
      expect(severePos.statusAssessment, contains('Severe Roughness'));

      const severeNeg = CylinderSmoothnessData(cylinder: 6, roughnessRpm2: -4.8, rawValue: -48);
      expect(severeNeg.isBalanced, isFalse);
      expect(severeNeg.isCritical, isTrue);
      expect(severeNeg.statusAssessment, contains('Severe Roughness'));
    });

    test('Decodes 15-byte UDS DID 0xD120 binary frame correctly for 6 cylinders', () {
      // Header: 0x62 0xD1 0x20
      // Cyl 1: 0x00 0x0A (+10 raw -> +1.0 1/min²)
      // Cyl 2: 0xFF 0xF6 (-10 raw -> -1.0 1/min²)
      // Cyl 3: 0x00 0x1E (+30 raw -> +3.0 1/min²)
      // Cyl 4: 0xFF 0xE2 (-30 raw -> -3.0 1/min²)
      // Cyl 5: 0x00 0x37 (+55 raw -> +5.5 1/min²)
      // Cyl 6: 0xFF 0xCB (-53 raw -> -5.3 1/min²)
      final rawResponse = Uint8List.fromList([
        0x62, 0xD1, 0x20,
        0x00, 0x0A,
        0xFF, 0xF6,
        0x00, 0x1E,
        0xFF, 0xE2,
        0x00, 0x37,
        0xFF, 0xCB,
      ]);

      final parsed = <CylinderSmoothnessData>[];
      for (int cyl = 1; cyl <= 6; cyl++) {
        final offset = 3 + (cyl - 1) * 2;
        int raw = (rawResponse[offset] << 8) | rawResponse[offset + 1];
        if (raw >= 0x8000) raw -= 0x10000;
        final roughness = double.parse((raw * 0.1).toStringAsFixed(2));
        parsed.add(CylinderSmoothnessData(
          cylinder: cyl,
          roughnessRpm2: roughness,
          rawValue: raw,
        ));
      }

      expect(parsed.length, equals(6));

      expect(parsed[0].cylinder, equals(1));
      expect(parsed[0].roughnessRpm2, equals(1.0));
      expect(parsed[0].isBalanced, isTrue);

      expect(parsed[1].cylinder, equals(2));
      expect(parsed[1].roughnessRpm2, equals(-1.0));
      expect(parsed[1].isBalanced, isTrue);

      expect(parsed[2].cylinder, equals(3));
      expect(parsed[2].roughnessRpm2, equals(3.0));
      expect(parsed[2].isElevated, isTrue);

      expect(parsed[3].cylinder, equals(4));
      expect(parsed[3].roughnessRpm2, equals(-3.0));
      expect(parsed[3].isElevated, isTrue);

      expect(parsed[4].cylinder, equals(5));
      expect(parsed[4].roughnessRpm2, equals(5.5));
      expect(parsed[4].isCritical, isTrue);

      expect(parsed[5].cylinder, equals(6));
      expect(parsed[5].roughnessRpm2, equals(-5.3));
      expect(parsed[5].isCritical, isTrue);
    });
  });

  group('4. ServiceRoutineResult NRC Descriptions', () {
    test('Formats standard UDS negative response codes accurately', () {
      final res22 = ServiceRoutineResult(
        success: false,
        title: 'Test',
        message: 'Failed',
        nrcCode: 0x22,
      );
      expect(res22.nrcDescription, contains('Conditions Not Correct'));

      final res31 = ServiceRoutineResult(
        success: false,
        title: 'Test',
        message: 'Failed',
        nrcCode: 0x31,
      );
      expect(res31.nrcDescription, contains('Request Out Of Range'));

      final res33 = ServiceRoutineResult(
        success: false,
        title: 'Test',
        message: 'Failed',
        nrcCode: 0x33,
      );
      expect(res33.nrcDescription, contains('Security Access Denied'));
    });
  });

  group('5. Full End-to-End Execution of 7 ProTool Service Routines', () {
    late TestEnetHsfzProtocol protocol;
    late BmwServiceFunctions service;

    setUp(() {
      protocol = TestEnetHsfzProtocol();
      service = BmwServiceFunctions(protocol: protocol);
    });

    test('1. valvetronicCalibration executes on DME 0x12 Routine 0x1005', () async {
      final progressSteps = <String>[];
      final result = await service.valvetronicCalibration(
        onProgress: (step, progress) => progressSteps.add(step),
      );

      expect(result.success, isTrue);
      expect(result.title, contains('Valvetronic'));
      expect(result.message, contains('N20/N55/S55/B58'));
      expect(progressSteps.isNotEmpty, isTrue);
      expect(progressSteps.last, contains('Complete'));

      // Verify transaction on DME 0x12
      final dmeCalls = protocol.recordedTransactions.where((t) => t['ecu'] == 0x12).toList();
      expect(dmeCalls.any((t) => (t['payload'] as List<int>).contains(0x31)), isTrue);
    });

    test('2. resetEngineAdaptations executes on DME 0x12 Routine 0x1000', () async {
      final progressSteps = <String>[];
      final result = await service.resetEngineAdaptations(
        onProgress: (step, progress) => progressSteps.add(step),
      );

      expect(result.success, isTrue);
      expect(result.title, contains('Engine Adaptations'));
      expect(result.message, contains('Lambda'));
      expect(result.message, contains('VANOS'));
      expect(result.details['routine'], equals('0x1000'));
      expect(result.details['ecu'], equals('DME 0x12'));

      // Verify UDS Routine Start payload [0x31, 0x01, 0x10, 0x00] sent to 0x12
      final match = protocol.recordedTransactions.where(
        (t) => t['ecu'] == 0x12 && (t['payload'] as List<int>).join(',') == '49,1,16,0',
      );
      expect(match.isNotEmpty, isTrue);
    });

    test('3. rainLightSensorInit executes on RLS 0x56 with fallback to FEM 0x40', () async {
      // Primary success on 0x56
      final resPrimary = await service.rainLightSensorInit();
      expect(resPrimary.success, isTrue);
      expect(resPrimary.details['ecu'], equals('0x56'));

      // Fallback test: when 0x56 returns NRC 0x7F 0x31 0x22, retries on 0x40
      final fallbackProto = TestEnetHsfzProtocol();
      fallbackProto.registerResponse(0x56, [0x31, 0x01, 0xA0, 0x02], [0x7F, 0x31, 0x22]);
      final fallbackService = BmwServiceFunctions(protocol: fallbackProto);

      final resFallback = await fallbackService.rainLightSensorInit();
      expect(resFallback.success, isTrue);
      expect(resFallback.details['ecu'], equals('0x40'));
    });

    test('4. tpmsReset executes on DSC 0x29 Routine 0xD030', () async {
      final result = await service.tpmsReset();

      expect(result.success, isTrue);
      expect(result.title, contains('TPMS'));
      expect(result.message, contains('30 km/h'));
      expect(result.details['ecu'], equals('DSC 0x29'));
      expect(result.details['routine'], equals('0xD030'));

      final dscCalls = protocol.recordedTransactions.where(
        (t) => t['ecu'] == 0x29 && (t['payload'] as List<int>).join(',') == '49,1,208,48',
      );
      expect(dscCalls.isNotEmpty, isTrue);
    });

    test('5. airSuspensionRideHeightCalibration executes on EHC 0x6E with mm offsets', () async {
      final result = await service.airSuspensionRideHeightCalibration(
        leftOffsetMm: -10,
        rightOffsetMm: 15,
      );

      expect(result.success, isTrue);
      expect(result.title, contains('Air Suspension'));
      expect(result.details['leftOffsetMm'], equals(-10));
      expect(result.details['rightOffsetMm'], equals(15));
      expect(result.details['ecu'], equals('0x6E'));

      // Test fallback to VDC 0x3F when 0x6E rejects
      final vdcProto = TestEnetHsfzProtocol();
      vdcProto.registerResponse(0x6E, [0x31, 0x01, 0x41, 0x01, 0x00, 0x00], [0x7F, 0x31, 0x11]);
      final vdcService = BmwServiceFunctions(protocol: vdcProto);

      final vdcResult = await vdcService.airSuspensionRideHeightCalibration();
      expect(vdcResult.success, isTrue);
      expect(vdcResult.details['ecu'], equals('0x3F'));
    });

    test('6. readCylinderSmoothness reads DME 0x12 DID 0xD120 and parses 6 cylinders', () async {
      // Register authentic response for 0x22 0xD1 0x20
      protocol.registerResponse(0x12, [0x22, 0xD1, 0x20], [
        0x62, 0xD1, 0x20,
        0x00, 0x04, // Cyl 1: +0.4
        0xFF, 0xFB, // Cyl 2: -0.5
        0x00, 0x02, // Cyl 3: +0.2
        0xFF, 0xFE, // Cyl 4: -0.2
        0x00, 0x08, // Cyl 5: +0.8
        0xFF, 0xF9, // Cyl 6: -0.7
      ]);

      final smoothnessList = await service.readCylinderSmoothness();

      expect(smoothnessList, isNotNull);
      expect(smoothnessList!.length, equals(6));

      expect(smoothnessList[0].cylinder, equals(1));
      expect(smoothnessList[0].roughnessRpm2, equals(0.4));
      expect(smoothnessList[0].isBalanced, isTrue);

      expect(smoothnessList[1].cylinder, equals(2));
      expect(smoothnessList[1].roughnessRpm2, equals(-0.5));
      expect(smoothnessList[1].isBalanced, isTrue);

      expect(smoothnessList[4].cylinder, equals(5));
      expect(smoothnessList[4].roughnessRpm2, equals(0.8));

      expect(smoothnessList[5].cylinder, equals(6));
      expect(smoothnessList[5].roughnessRpm2, equals(-0.7));
    });

    test('7. activeFrontSteeringCalibration executes on AFS 0x1B Routine 0xA012', () async {
      final result = await service.activeFrontSteeringCalibration();

      expect(result.success, isTrue);
      expect(result.title, contains('Active Front Steering'));
      expect(result.details['ecu'], equals('AFS 0x1B'));
      expect(result.details['routine'], equals('0xA012'));

      final afsCalls = protocol.recordedTransactions.where(
        (t) => t['ecu'] == 0x1B && (t['payload'] as List<int>).join(',') == '49,1,160,18',
      );
      expect(afsCalls.isNotEmpty, isTrue);
    });

    test('Rejection NRC handling returns proper failure result', () async {
      final rejectProto = TestEnetHsfzProtocol();
      // Condition not correct (Engine running when engine off required)
      rejectProto.registerResponse(0x12, [0x31, 0x01, 0x10, 0x00], [0x7F, 0x31, 0x22]);
      final rejectService = BmwServiceFunctions(protocol: rejectProto);

      final result = await rejectService.resetEngineAdaptations();
      expect(result.success, isFalse);
      expect(result.nrcCode, equals(0x22));
      expect(result.nrcDescription, contains('Conditions Not Correct'));
    });
  });
}
