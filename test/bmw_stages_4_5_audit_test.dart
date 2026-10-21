import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/models/verified_flash_image.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_custom_rom_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_options.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/kdcan_protocol.dart';
import 'package:ai_car_diagnostics/modules/obd/services/uds_flash_session.dart';

void main() {
  group('Stage 4.1: KdcanProtocol (InpaK_DCan & KWP2000 Framing)', () {
    test('builds and parses short, extended, and 0xB8 KWP2000 telegrams with XOR checksum', () {
      // 1. Short header (< 64 bytes)
      final shortFrame = KdcanProtocol.buildKwp2000Frame(0x12, const [0x10, 0x85]);
      expect(shortFrame[0], equals(0x82)); // 0x80 | 2
      expect(shortFrame[1], equals(0x12)); // Target DME
      expect(shortFrame[2], equals(0xF1)); // Source Tester
      expect(shortFrame[3], equals(0x10));
      expect(shortFrame[4], equals(0x85));

      final parsedShort = KdcanProtocol.parseKwp2000Frame(shortFrame);
      expect(parsedShort, isNotNull);
      expect(parsedShort!.targetAddress, equals(0x12));
      expect(parsedShort.sourceAddress, equals(0xF1));
      expect(parsedShort.payload, equals(const [0x10, 0x85]));

      // 2. 0xB8 D-CAN header
      final b8Frame = KdcanProtocol.buildKwp2000Frame(
        0x18,
        const [0x36, 0x01, 0xAA, 0xBB],
        useB8Header: true,
      );
      expect(b8Frame[0], equals(0xB8));
      expect(b8Frame[1], equals(0x18));
      expect(b8Frame[2], equals(0xF1));
      expect(b8Frame[3], equals(0x04));

      final parsedB8 = KdcanProtocol.parseKwp2000Frame(b8Frame);
      expect(parsedB8, isNotNull);
      expect(parsedB8!.formatByte, equals(0xB8));
      expect(parsedB8.payload, equals(const [0x36, 0x01, 0xAA, 0xBB]));
    });

    test('strips half-duplex K-Line TX echo automatically before parsing ECU response', () {
      final txFrame = KdcanProtocol.buildKwp2000Frame(0x12, const [0x21, 0x81]);
      final ecuRspFrame = KdcanProtocol.buildKwp2000Frame(
        0xF1,
        const [0x61, 0x81, 0x57, 0x42, 0x41], // 'WBA'
        sourceAddress: 0x12,
      );
      final wireWithEcho = Uint8List.fromList([...txFrame, ...ecuRspFrame]);

      final parsed = KdcanProtocol.parseKwp2000Frame(wireWithEcho, txEchoToStrip: txFrame);
      expect(parsed, isNotNull);
      expect(parsed!.sourceAddress, equals(0x12));
      expect(parsed.targetAddress, equals(0xF1));
      expect(parsed.payload, equals(const [0x61, 0x81, 0x57, 0x42, 0x41]));
    });

    test('builds INPA K+DCAN mode control telegrams for K_LINE, D_CAN, K_CAN, and AUTO', () {
      final dcanCtrl = KdcanProtocol.buildInpaModeControlTelegram(DcanMode.dCan);
      final parsedDcan = KdcanProtocol.parseKwp2000Frame(dcanCtrl);
      expect(parsedDcan, isNotNull);
      expect(parsedDcan!.payload, equals([0xC1, DcanMode.dCan.code]));

      final klineCtrl = KdcanProtocol.buildInpaModeControlTelegram(DcanMode.kLine);
      final parsedKline = KdcanProtocol.parseKwp2000Frame(klineCtrl);
      expect(parsedKline, isNotNull);
      expect(parsedKline!.payload, equals([0xC0, DcanMode.kLine.code]));
    });
  });

  group('Stage 4.2: KwpFlashSession (UNI_Flash.Program_KWP) & EnetHsfzProtocol Delegation', () {
    test('executes full E-Series KWP2000 flash lifecycle with coding backup and restore', () async {
      late KdcanProtocol kdcan;
      kdcan = KdcanProtocol(
        customTransceiver: (txFrame, {timeout = const Duration(seconds: 1)}) async {
          final req = KdcanProtocol.parseKwp2000Frame(txFrame);
          if (req == null || req.payload.isEmpty) return null;
          final p = req.payload;
          final sid = p[0];

          List<int> rspPayload;
          if (sid == 0xC1 || sid == 0xC0) {
            rspPayload = [sid + 0x40, 0x00];
          } else if (sid == Kwp2000DiagCmd.readDataByLocalIdentifier) {
            // 0x21 0x30 / 0x31 coding backup
            rspPayload = [0x61, p[1], 0xDE, 0xAD, 0xBE, 0xEF];
          } else if (sid == Kwp2000DiagCmd.disableNormalMessageTransmission) {
            rspPayload = [0x68, 0x02];
          } else if (sid == Kwp2000DiagCmd.startDiagnosticSession) {
            rspPayload = [0x50, p[1]];
          } else if (sid == Kwp2000DiagCmd.securityAccess) {
            if (p[1] == 0x01) {
              rspPayload = [0x67, 0x01, 0x12, 0x34];
            } else {
              rspPayload = [0x67, 0x02];
            }
          } else if (sid == Kwp2000DiagCmd.startRoutineByLocalIdentifier) {
            final rid = p[1];
            rspPayload = [0x71, rid, 0x00];
          } else if (sid == Kwp2000DiagCmd.requestDownload) {
            rspPayload = [0x74, 0x40]; // 64-byte max block
          } else if (sid == Kwp2000DiagCmd.transferData) {
            rspPayload = [0x76, p[1]];
          } else if (sid == Kwp2000DiagCmd.requestTransferExit) {
            rspPayload = [0x77];
          } else if (sid == Kwp2000DiagCmd.ecuReset) {
            rspPayload = [0x51, 0x01];
          } else if (sid == Kwp2000DiagCmd.enableNormalMessageTransmission) {
            rspPayload = [0x69, 0x02];
          } else if (sid == Kwp2000DiagCmd.writeDataByLocalIdentifier) {
            rspPayload = [0x7B, p[1]];
          } else {
            rspPayload = [(sid + 0x40) & 0xFF];
          }

          return KdcanProtocol.buildKwp2000Frame(
            KdcanProtocol.testerAddress,
            rspPayload,
            sourceAddress: req.targetAddress,
          );
        },
      );

      final initOk = await kdcan.initialize(mode: DcanMode.dCan);
      expect(initOk, isTrue);

      final session = KwpFlashSession(
        kdcan: kdcan,
        targetEcu: 0x18, // E-Series ZF 6HP GKE215
        remoteKeyProvider: (seed) async => BmwSeedKeyEngine.computeSecurityKey(
          seedBytes: seed,
          ecuAddress: 0x18,
          level: 0x01,
          family: BmwEcuSecurityFamily.kwp2000Eseries,
        ),
      );

      final flashOk = await session.executeSegmentFlash(
        address: 0x040000,
        data: Uint8List.fromList(List<int>.generate(96, (i) => i & 0xFF)),
        signature: const [0xAA, 0xBB, 0xCC, 0xDD],
      );

      expect(flashOk, isTrue);
      expect(session.backedUpCoding, isNotEmpty);
      expect(session.isCodingRestored, isTrue);
    });

    test('EnetHsfzProtocol delegates seamlessly to KdcanProtocol when attached', () async {
      final kdcan = KdcanProtocol(
        customTransceiver: (txFrame, {timeout = const Duration(seconds: 1)}) async {
          final req = KdcanProtocol.parseKwp2000Frame(txFrame)!;
          if (req.payload[0] == 0x22 && req.payload[1] == 0xF1 && req.payload[2] == 0x90) {
            final vinBytes = 'WBA3A9C55CF256789'.codeUnits;
            return KdcanProtocol.buildKwp2000Frame(
              0xF1,
              [0x62, 0xF1, 0x90, ...vinBytes],
              sourceAddress: req.targetAddress,
            );
          }
          return KdcanProtocol.buildKwp2000Frame(0xF1, [req.payload[0] + 0x40]);
        },
      );
      await kdcan.initialize(mode: DcanMode.dCan);

      final enet = EnetHsfzProtocol();
      enet.attachKdcanProtocol(kdcan);
      expect(enet.isConnected, isTrue);
      expect(enet.isKdcanMode, isTrue);

      final vin = await enet.readVin(0x12);
      expect(vin, equals('WBA3A9C55CF256789'));
    });
  });

  group('Stage 5.1: UCL / NRV2B Compression & UdsFlashSession Compressed Transfer', () {
    test('UclNrvCompression performs lossless compressNrv2b / decompressNrv2b with < 50% ratio on calibration blocks', () {
      // Build realistic 512-byte ECU calibration block with repeating tables & 0xFF padding
      final original = Uint8List(512);
      for (var i = 0; i < 256; i++) {
        original[i] = (i % 16) * 10;
      }
      for (var i = 256; i < 512; i++) {
        original[i] = 0xFF;
      }

      final compressed = UclNrvCompression.compressNrv2b(original);
      expect(compressed.length, lessThan(original.length ~/ 2));

      final decompressed = UclNrvCompression.decompressNrv2b(
        compressed,
        uncompressedLength: original.length,
      );
      expect(decompressed, equals(original));
    });

    test('UdsFlashSession transmits NRV-compressed TransferData blocks when DFI == 0x10 and compressPayloadWhenNrv == true', () async {
      final rawData = Uint8List.fromList(List<int>.filled(256, 0xA5));
      final compressedExpected = UclNrvCompression.compressNrv2b(rawData);
      expect(compressedExpected.length, lessThan(32));

      final sentPayloads = <List<int>>[];
      final fakeProto = _RecordingEnetProtocol((ecu, req) async {
        sentPayloads.add(req);
        final sid = req[0];
        if (sid == 0x10) return Uint8List.fromList([0x50, req[1], 0x00, 0x32, 0x01, 0xF4]);
        if (sid == 0x27) {
          return req[1] == 0x01
              ? Uint8List.fromList([0x67, 0x01, 0x11, 0x22, 0x33, 0x44])
              : Uint8List.fromList([0x67, 0x02]);
        }
        if (sid == 0x31) return Uint8List.fromList([0x71, req[1], req[2], req[3], 0x00]);
        if (sid == 0x34) return Uint8List.fromList([0x74, 0x20, 0x01, 0x02]); // 258-byte maxBlock
        if (sid == 0x36) return Uint8List.fromList([0x76, req[1]]);
        if (sid == 0x37) return Uint8List.fromList([0x77]);
        if (sid == 0x11) return Uint8List.fromList([0x51, req[1]]);
        return Uint8List.fromList([(sid + 0x40) & 0xFF]);
      });

      final image = VerifiedFlashImage(
        manifest: const FlashManifest(
          licensedVin: 'WBA3B91050F123456',
          engineCode: 'B58',
          stage: 'Stage 1',
          payloadSha256: 'hash',
          segments: [
            {'address': 0x80200000, 'length': 256},
          ],
          createdAtEpoch: 0,
        ),
        segments: [
          FlashSegment(0x80200000, rawData),
        ],
        rawPayload: rawData,
      );

      final session = UdsFlashSession(
        proto: fakeProto,
        ecu: 0x12,
        remoteKeyProvider: (seed) async => const [0xAA, 0xBB, 0xCC, 0xDD],
      );

      final events = await session
          .run(
            image,
            allowExecutionInTest: true,
            dataFormatIdentifier: FlashCompressionMethod.nrv.dataFormatIdentifier, // 0x10
            compressPayloadWhenNrv: true,
          )
          .toList();

      expect(events.last.stage, equals('COMPLETE'));

      final dlReq = sentPayloads.firstWhere((p) => p[0] == 0x34);
      expect(dlReq[1], equals(0x10)); // NRV DFI
      // RequestDownload still reports uncompressed length (256 = 0x00000100)
      expect(dlReq.sublist(7, 11), equals(const [0x00, 0x00, 0x01, 0x00]));

      final transferReq = sentPayloads.firstWhere((p) => p[0] == 0x36);
      expect(transferReq.sublist(2), equals(compressedExpected));
    });
  });

  group('Stage 5.2: Multi-Family Seed/Key, T8HpConstants, BaseAddresses & SwflCalibrationRegistry', () {
    test('BmwSeedKeyEngine computes distinct deterministic keys for all 6 BMW ECU families', () {
      const seed4 = [0x41, 0x9C, 0x2E, 0x77];
      final mevdKey = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: seed4,
        ecuAddress: 0x12,
        level: 0x01,
      );
      final mg1Key = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: seed4,
        ecuAddress: 0x12,
        level: 0x11,
      );
      final zf8HpKey = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: seed4,
        ecuAddress: 0x18,
        level: 0x11,
      );
      final vtgKey = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: seed4,
        ecuAddress: 0x19,
        level: 0x01,
      );
      final femKey = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: seed4,
        ecuAddress: 0x40,
        level: 0x01,
      );

      expect(mevdKey.length, equals(4));
      expect(mg1Key.length, equals(4));
      expect(zf8HpKey.length, equals(4));
      expect(vtgKey.length, equals(4));
      expect(femKey.length, equals(4));

      // All families produce distinct keys for the same seed
      final uniqueKeys = {
        mevdKey.join(','),
        mg1Key.join(','),
        zf8HpKey.join(','),
        vtgKey.join(','),
        femKey.join(','),
      };
      expect(uniqueKeys.length, equals(5));

      // 8-byte MG1 seed produces 8-byte key
      final mg1Key8 = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: const [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
        ecuAddress: 0x12,
        level: 0x11,
      );
      expect(mg1Key8.length, equals(8));

      // 2-byte KWP2000 E-Series seed produces 2-byte key
      final kwpKey2 = BmwSeedKeyEngine.computeSecurityKey(
        seedBytes: const [0x5A, 0xC3],
        ecuAddress: 0x18,
        level: 0x01,
      );
      expect(kwpKey2.length, equals(2));
    });

    test('T8HpConstants and BaseAddresses match UNI_Flash.dll metadata layout', () {
      expect(T8HpConstants.is8Hp4G('00004C20'), isTrue);
      expect(T8HpConstants.is8Hp4G('000019DC'), isFalse);
      expect(
        BaseAddresses.getDst(T8HpConstants.sgbdIndex8Hptu),
        equals(0x801C0000),
      );

      final fakeSeg = Uint8List(0x110);
      fakeSeg[0x100] = 0x00;
      fakeSeg[0x101] = 0x00;
      fakeSeg[0x102] = 0x19;
      fakeSeg[0x103] = 0xDD;
      fakeSeg[0x104] = 24;
      fakeSeg[0x105] = 7;

      expect(BaseAddresses.getDstId(fakeSeg), equals('000019DD'));
      expect(BaseAddresses.getDstMajor(fakeSeg), equals(24));
      expect(BaseAddresses.getDstMinor(fakeSeg), equals(7));
    });

    test('SwflCalibrationRegistry patches exact SWFL table offsets for MG1CS003 (000030C1)', () {
      final rawSwfl = Uint8List(2048);
      final opts = BmwFlashOptions(
        vmaxDisabled: true,
        coldStartDisabled: true,
        boostByGear: BoostByGearConfig(
          enabled: true,
          gearLimitsPsi: [16.0, 18.0, 22.0, 24.0, 24.0, 24.0, 24.0, 24.0],
        ),
      );

      final patched = SwflCalibrationRegistry.patchSwflCalibration(
        '000030C1',
        rawSwfl,
        opts,
      );
      final map = SwflCalibrationRegistry.resolveMap('000030C1');

      // Check VMAX limiter at 0x0460 -> 330 km/h (0x014A)
      expect(patched[map.vmaxLimiterOffset], equals(0x01));
      expect(patched[map.vmaxLimiterOffset + 1], equals(0x4A));

      // Check Cold Start Cat Heating at 0x0464 -> 0x00 (disabled)
      expect(patched[map.coldStartCatHeatingOffset], equals(0x00));

      // Check FXAI Magic Header at customRomMasterTableOffset (0x0500)
      expect(
        patched.sublist(map.customRomMasterTableOffset, map.customRomMasterTableOffset + 4),
        equals(const [0x46, 0x58, 0x41, 0x49]), // 'FXAI'
      );
    });
  });
}

class _RecordingEnetProtocol extends EnetHsfzProtocol {
  final Future<Uint8List?> Function(int targetEcu, List<int> payload) _handler;

  _RecordingEnetProtocol(this._handler);

  @override
  bool get isConnected => true;

  @override
  Future<void> sendFunctional(List<int> udsPayload) async {}

  @override
  Future<void> sendFireAndForget(int targetEcu, List<int> udsPayload) async {}

  @override
  Future<Uint8List?> sendUdsAndAwait(
    int targetEcu,
    List<int> udsPayload, {
    Duration timeout = const Duration(milliseconds: 1500),
    Duration p2Star = const Duration(seconds: 10),
    int maxPending = 60,
  }) =>
      _handler(targetEcu, udsPayload);
}
