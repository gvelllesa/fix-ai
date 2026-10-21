import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/models/verified_flash_image.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_coding_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_manager.dart'
    show EcuIdentity;
import 'package:ai_car_diagnostics/modules/obd/services/protocols/bluetooth_strategy.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';
import 'package:ai_car_diagnostics/modules/obd/services/uds_flash_session.dart';

class FakeBleIsoTpStrategy extends BluetoothStrategy {
  final List<String> sentCommands = [];
  final Map<String, String> commandResponses = {};

  @override
  bool get isConnected => true;

  FakeBleIsoTpStrategy() {
    commandRunnerOverride = (String cmd, {Duration timeout = const Duration(milliseconds: 1500)}) async {
      sentCommands.add(cmd);
      if (commandResponses.containsKey(cmd)) {
        return commandResponses[cmd]!;
      }
      return 'OK';
    };
  }
}

class FakeUniFlashProtocol extends EnetHsfzProtocol {
  final Map<int, List<int> Function(int targetEcu, List<int> req)> handlers = {};
  final List<({int targetEcu, List<int> payload})> recordedCalls = [];

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
    recordedCalls.add((
      targetEcu: targetEcu,
      payload: List<int>.from(udsPayload),
    ));
    final sid = udsPayload[0];
    if (handlers.containsKey(sid)) {
      final rsp = handlers[sid]!(targetEcu, udsPayload);
      return Uint8List.fromList(rsp);
    }
    return null;
  }

  @override
  Future<void> sendFunctional(List<int> udsPayload) async {
    recordedCalls.add((
      targetEcu: 0xDF,
      payload: List<int>.from(udsPayload),
    ));
  }

  @override
  Future<void> sendFireAndForget(int targetEcu, List<int> udsPayload) async {
    recordedCalls.add((
      targetEcu: targetEcu,
      payload: List<int>.from(udsPayload),
    ));
  }
}

void main() {
  group('Stage 1 - ENET UDP Discovery (Port 6811), Clamp Check & BLE ISO-TP', () {
    test('Builds and parses HSFZ UDP Vehicle Identification (type 0x0011)', () {
      final req = EnetHsfzProtocol.buildUdpIdentRequest();
      expect(req, equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x11]));

      final asciiBody = ascii.encode('DIAGADR10BMWMAC001122334455VINWBA3B91050F123456');
      final packet = Uint8List.fromList([
        0x00,
        0x00,
        0x00,
        asciiBody.length,
        0x00,
        0x11,
        ...asciiBody,
      ]);

      final parsed = EnetHsfzProtocol.parseUdpIdentResponse(
        '169.254.42.10',
        packet,
      );
      expect(parsed, isNotNull);
      expect(parsed!.ipAddress, equals('169.254.42.10'));
      expect(parsed.vin, equals('WBA3B91050F123456'));
      expect(parsed.macAddress, equals('00:11:22:33:44:55'));
    });

    test('Builds and parses TCP Control Port 6811 Clamp/Ignition State (type 0x0010)', () {
      final req = EnetHsfzProtocol.buildControlIgnitRequest();
      expect(req, equals([0x00, 0x00, 0x00, 0x00, 0x00, 0x10]));

      // Response with length=1, type=0x0010, state=0x05 (KL15 + KL30 active)
      final resp = Uint8List.fromList([0x00, 0x00, 0x00, 0x01, 0x00, 0x10, 0x05]);
      final state = EnetHsfzProtocol.parseControlIgnitResponse(resp);
      expect(state, isTrue);
    });

    test('BluetoothStrategy configures BMW ISO 15765-2 Extended CAN Addressing and parses SF/MF ISO-TP', () async {
      final ble = FakeBleIsoTpStrategy();
      final initOk = await ble.initializeBmwIsoTpCan();
      expect(initOk, isTrue);
      expect(ble.sentCommands, contains('AT SP 6'));
      expect(ble.sentCommands, contains('AT H1'));
      expect(ble.sentCommands, contains('AT CAF1'));
      expect(ble.sentCommands, contains('AT CFC1'));
      expect(ble.sentCommands, contains('AT SH 6F1'));

      // Select DME (0x12)
      await ble.selectTargetEcu(0x12);
      expect(ble.sentCommands, contains('AT CEA 12'));
      expect(ble.sentCommands, contains('AT CRA 612'));

      // Single-Frame parsing with CAN header (612 F1 04 62 F1 90 41)
      final sf = BluetoothStrategy.parseIsoTpResponse('612 F1 04 62 F1 90 41');
      expect(sf, equals([0x62, 0xF1, 0x90, 0x41]));

      // Multi-Frame parsing (First Frame + Consecutive Frames for 17-byte VIN + 3-byte UDS header = 20 bytes = 0x014)
      const mfRaw = '''
612 F1 10 14 62 F1 90 57 42
612 F1 21 41 33 42 39 31 30
612 F1 22 35 30 46 31 32 33
612 F1 23 34 35 36 00 00 00
''';
      final mf = BluetoothStrategy.parseIsoTpResponse(mfRaw);
      expect(mf, isNotNull);
      expect(mf!.length, equals(20));
      expect(mf.sublist(0, 3), equals([0x62, 0xF1, 0x90]));
      expect(ascii.decode(mf.sublist(3)), equals('WBA3B91050F123456'));
    });

    test('EnetHsfzProtocol delegates UDS requests to attached BluetoothStrategy in BLE ISO-TP mode', () async {
      final ble = FakeBleIsoTpStrategy();
      ble.commandResponses['22F190'] = '612 F1 06 62 F1 90 42 4D 57';

      final proto = EnetHsfzProtocol();
      proto.attachBleStrategy(ble);
      expect(proto.isBleIsoTpMode, isTrue);
      expect(proto.isConnected, isTrue);

      final resp = await proto.sendUdsAndAwait(0x12, [0x22, 0xF1, 0x90]);
      expect(resp, equals([0x62, 0xF1, 0x90, 0x42, 0x4D, 0x57]));
      expect(ble.sentCommands, contains('AT CEA 12'));
      expect(ble.sentCommands, contains('22F190'));
    });
  });

  group('Stage 2 - UNI_Flash.Program_UDS Lifecycle Parity (xHP / xDelete)', () {
    test('BCD date/time conversion and Programming Date Fingerprint (0x2E 0xF199)', () {
      expect(UdsFlashSession.convertToBcd(26), equals(0x26));
      expect(UdsFlashSession.convertToBcd(10), equals(0x10));
      expect(UdsFlashSession.convertToBcd(20), equals(0x20));

      final dt = DateTime(2026, 10, 20, 15, 42, 09);
      expect(UdsFlashSession.getLocalDateInBcd(dt), equals([0x26, 0x10, 0x20]));
      expect(UdsFlashSession.getLocalTimeInBcd(dt), equals([0x15, 0x42, 0x09]));
      expect(
        UdsFlashSession.getProgrammingPreConditionDescription(0x01),
        contains('Engine speed'),
      );
    });

    test('Full UNI_Flash lifecycle executes 0x0203 precondition, 0x0F0C energy mode, 0x3000 coding save/restore, 0xF199 date, and 0x0202 per-segment check', () async {
      final proto = FakeUniFlashProtocol();

      // Configure handlers
      proto.handlers[0x10] = (ecu, req) => [0x50, req[1]];
      proto.handlers[0x22] = (ecu, req) {
        // Coding record read 0x22 0x30 0x00 -> return 4 bytes
        if (req.length >= 3 && req[1] == 0x30 && req[2] == 0x00) {
          return [0x62, 0x30, 0x00, 0xDE, 0xAD, 0xBE, 0xEF];
        }
        return [0x7F, 0x22, 0x31]; // Out of range ends coding loop
      };
      proto.handlers[0x27] = (ecu, req) {
        if (req[1].isOdd) {
          return [0x67, req[1], 0x11, 0x22, 0x33, 0x44];
        }
        return [0x67, req[1]];
      };
      proto.handlers[0x2E] = (ecu, req) => [0x6E, req[1], req[2]];
      proto.handlers[0x31] = (ecu, req) => [0x71, req[1], req[2], req[3], 0x00];
      proto.handlers[0x34] = (ecu, req) => [0x74, 0x20, 0x00, 0x42];
      proto.handlers[0x36] = (ecu, req) => [0x76, req[1]];
      proto.handlers[0x37] = (ecu, req) => [0x77];
      proto.handlers[0x11] = (ecu, req) => [0x51, 0x01];

      final segData = Uint8List.fromList(List.generate(32, (i) => i));
      final image = VerifiedFlashImage(
        manifest: const FlashManifest(
          licensedVin: 'WBA3B91050F123456',
          engineCode: 'B58',
          stage: 'Stage 1',
          payloadSha256: 'hash',
          segments: [{'address': 0x80020000, 'length': 32}],
          createdAtEpoch: 0,
        ),
        segments: [FlashSegment(0x80020000, segData)],
        rawPayload: segData,
      );

      final session = UdsFlashSession(
        proto: proto,
        remoteKeyProvider: (_) async => [0xAA, 0xBB, 0xCC, 0xDD],
      );

      final stages = await session
          .run(
            image,
            allowExecutionInTest: true,
            enableUniFlashLifecycle: true,
            dataFormatIdentifier: 0x10,
          )
          .toList();
      expect(stages.last.stage, equals('COMPLETE'));

      final payloads = proto.recordedCalls.map((c) => c.payload).toList();

      // 1. CheckProgrammingPreCondition (0x31 0x01 0x02 0x03)
      expect(
        payloads.any((p) => p.length >= 4 && p[0] == 0x31 && p[2] == 0x02 && p[3] == 0x03),
        isTrue,
      );
      // 2. SetEnergyMode FlashMode (0x31 0x01 0x0F 0x0C 0x03)
      expect(
        payloads.any((p) => p.length == 5 && p[0] == 0x31 && p[2] == 0x0F && p[3] == 0x0C && p[4] == 0x03),
        isTrue,
      );
      // 3. Programming Date Fingerprint (0x2E 0xF1 0x99 ...)
      expect(
        payloads.any((p) => p.length == 6 && p[0] == 0x2E && p[1] == 0xF1 && p[2] == 0x99),
        isTrue,
      );
      // 4. RequestDownload uses dataFormatIdentifier = 0x10
      expect(
        payloads.any((p) => p.isNotEmpty && p[0] == 0x34 && p[1] == 0x10),
        isTrue,
      );
      // 5. Per-segment CheckMemoryAddressed (0x31 0x01 0x02 0x02 ...)
      expect(
        payloads.any((p) => p.length >= 4 && p[0] == 0x31 && p[2] == 0x02 && p[3] == 0x02),
        isTrue,
      );
      // 6. Coding record 0x3000 restored via 0x2E 0x30 0x00 DE AD BE EF
      expect(
        payloads.any((p) =>
            p.length == 7 &&
            p[0] == 0x2E &&
            p[1] == 0x30 &&
            p[2] == 0x00 &&
            p[3] == 0xDE &&
            p[6] == 0xEF),
        isTrue,
      );
    });
  });

  group('Stage 3 - BMW SVK 8-Byte SGBM-ID Parser & CAFD-Aware Coding', () {
    test('Parses binary SVK response (DID 0xF101) into HWEL, BTLD, SWFL, and CAFD SGBM-IDs', () {
      // UDS header: 62 F1 01
      // SVK header: 01 01 00 04 (version=1, count=4)
      // Record 1: HWEL (0x01), id=0x00001955, ver=001_003_002
      // Record 2: BTLD (0x02), id=0x000019DC, ver=001_019_003
      // Record 3: SWFL (0x05), id=0x00005D6B, ver=061_030_010
      // Record 4: CAFD (0x08), id=0x00000794, ver=014_040_122
      final svkPayload = Uint8List.fromList([
        0x62, 0xF1, 0x01,
        0x01, 0x01, 0x00, 0x04,
        0x01, 0x00, 0x00, 0x19, 0x55, 0x01, 0x03, 0x02,
        0x02, 0x00, 0x00, 0x19, 0xDC, 0x01, 0x13, 0x03,
        0x05, 0x00, 0x00, 0x5D, 0x6B, 0x3D, 0x1E, 0x0A,
        0x08, 0x00, 0x00, 0x07, 0x94, 0x0E, 0x28, 0x7A,
      ]);

      final records = EcuIdentity.parseSvkRecords(svkPayload);
      expect(records.length, equals(4));
      expect(records[0].formatted, equals('HWEL_00001955_001_003_002'));
      expect(records[1].formatted, equals('BTLD_000019DC_001_019_003'));
      expect(records[2].formatted, equals('SWFL_00005D6B_061_030_010'));
      expect(records[3].formatted, equals('CAFD_00000794_014_040_122'));

      final identity = EcuIdentity.parseFromUds(
        vin: 'WBA3B91050F123456',
        svkPayload: svkPayload,
      );
      expect(identity.hwel, equals('HWEL_00001955_001_003_002'));
      expect(identity.btld, equals('BTLD_000019DC_001_019_003'));
      expect(identity.swfl, equals('SWFL_00005D6B_061_030_010'));
      expect(identity.cafd, equals('CAFD_00000794_014_040_122'));
    });

    test('BmwCodingService.detectCafdFromSvk resolves CAFD-specific parameter overrides and unlocks SecurityAccess before 0x2E', () async {
      final proto = FakeUniFlashProtocol();
      proto.handlers[0x10] = (ecu, req) => [0x50, req[1]];
      proto.handlers[0x22] = (ecu, req) {
        if (req[1] == 0xF1 && req[2] == 0x01) {
          return [
            0x62, 0xF1, 0x01,
            0x01, 0x01, 0x00, 0x01,
            0x08, 0x00, 0x00, 0x07, 0x94, 0x0F, 0x01, 0x01, // CAFD_00000794_015_001_001
          ];
        }
        if (req[1] == 0xF1 && req[2] == 0x90) {
          return [0x62, 0xF1, 0x90, ...ascii.encode('WBA3B91050F123456')];
        }
        if ((req[1] == 0xF1 && req[2] == 0x11) || (req[1] == 0x10 && req[2] == 0x0A)) {
          return [0x62, req[1], req[2], 0x35, 0xE8]; // 13.80V (13800 mV)
        }
        // NCD DID 0x3025
        return [0x62, req[1], req[2], ...List.filled(16, 0x00)];
      };
      proto.handlers[0x27] = (ecu, req) {
        if (req[1] == 0x01) return [0x67, 0x01, 0x01, 0x02, 0x03, 0x04];
        return [0x67, 0x02];
      };
      proto.handlers[0x2E] = (ecu, req) => [0x6E, req[1], req[2]];
      proto.handlers[0x31] = (ecu, req) => [0x71, req[1], req[2], req[3], 0x00];
      proto.handlers[0x11] = (ecu, req) => [0x51, 0x03];

      final service = BmwCodingService(
        protocol: proto,
        remoteKeyProvider: (ecu, level, seed) async => [0x99, 0x88, 0x77, 0x66],
      );

      final cafd = await service.detectCafdFromSvk(0x40);
      expect(cafd, equals('CAFD_00000794_015_001_001'));

      final code = FdlCheatCode(
        id: 'TEST_CAFD_OVERRIDE',
        name: 'Test CAFD Override',
        category: 'Comfort & Convenience',
        description: 'Tests CAFD version override',
        targetEcuAddress: 0x40,
        targetEcuName: 'FEM_BODY (0x40)',
        did: 0x3023,
        byteOffset: 2,
        bitMask: 0x01,
        activeValue: 0x01,
        inactiveValue: 0x00,
        cafdOverrides: const {
          'CAFD_00000794_015': CafdParameterOverride(
            did: 0x3025,
            byteOffset: 6,
            bitMask: 0x04,
            activeValue: 0x04,
            inactiveValue: 0x00,
          ),
        },
      );

      final res = await service.applyCheatCode(code, true);
      expect(res.success, isTrue);

      // Verify SecurityAccess 0x27 0x01 and 0x27 0x02 were called
      expect(
        proto.recordedCalls.any((c) => c.payload.length == 2 && c.payload[0] == 0x27 && c.payload[1] == 0x01),
        isTrue,
      );
      expect(
        proto.recordedCalls.any((c) => c.payload.length == 6 && c.payload[0] == 0x27 && c.payload[1] == 0x02),
        isTrue,
      );
      // Verify 0x2E wrote to overridden DID 0x3025 at byteOffset 6 with bitMask 0x04
      final writeCall = proto.recordedCalls.firstWhere((c) => c.payload[0] == 0x2E);
      expect(writeCall.payload[1], equals(0x30));
      expect(writeCall.payload[2], equals(0x25));
      expect(writeCall.payload[3 + 6], equals(0x04));
    });
  });
}
