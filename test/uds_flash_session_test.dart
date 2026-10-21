import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/core/config/feature_flags.dart';
import 'package:ai_car_diagnostics/modules/obd/models/verified_flash_image.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';
import 'package:ai_car_diagnostics/modules/obd/services/uds_flash_session.dart';

class FakeFlashProtocol extends EnetHsfzProtocol {
  final Map<int, List<int> Function(List<int> req)> handlers = {};
  final List<List<int>> recordedRequests = [];

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
    recordedRequests.add(List<int>.from(udsPayload));
    final sid = udsPayload[0];
    if (handlers.containsKey(sid)) {
      final rsp = handlers[sid]!(udsPayload);
      return Uint8List.fromList(rsp);
    }
    return null;
  }

  @override
  Future<void> sendFunctional(List<int> udsPayload) async {
    recordedRequests.add(List<int>.from(udsPayload));
  }

  @override
  Future<void> sendFireAndForget(int targetEcu, List<int> udsPayload) async {
    recordedRequests.add(List<int>.from(udsPayload));
  }
}

void main() {
  group('P1.6 - UDS Flash Session Architecture & Anti-Brick Protection', () {
    late FakeFlashProtocol proto;

    setUp(() {
      proto = FakeFlashProtocol();
    });

    test('Safety feature flag blocks flash execution unless allowExecutionInTest is set', () async {
      final prevFlag = FeatureFlags.kFlashEnabled;
      FeatureFlags.kFlashEnabled = false;
      addTearDown(() => FeatureFlags.kFlashEnabled = prevFlag);

      final session = UdsFlashSession(
        proto: proto,
        remoteKeyProvider: (_) async => [0x11, 0x22, 0x33, 0x44],
      );

      final dummyImage = VerifiedFlashImage(
        manifest: const FlashManifest(
          licensedVin: 'WBA123',
          engineCode: 'B58',
          stage: 'Stage 1',
          payloadSha256: 'abc',
          segments: [],
          createdAtEpoch: 0,
        ),
        segments: [],
        rawPayload: Uint8List(0),
      );

      expect(
        () => session.run(dummyImage).toList(),
        throwsA(isA<StateError>()),
      );
    });

    test('Full successful flashing workflow (ISO 14229-1 spec)', () async {
      // Setup UDS handlers
      proto.handlers[0x10] = (req) => [0x50, req[1]]; // Session control
      proto.handlers[0x27] = (req) {
        if (req[1] == 0x01) {
          return [0x67, 0x01, 0xAA, 0xBB, 0xCC, 0xDD]; // Return seed
        } else if (req[1] == 0x02) {
          return [0x67, 0x02]; // Key accepted
        }
        return [0x7F, 0x27, 0x12];
      };
      proto.handlers[0x31] = (req) {
        // Erase or Check Dependencies
        return [0x71, req[1], req[2], req[3], 0x00]; // Status OK (0x00)
      };
      proto.handlers[0x34] = (req) {
        // RequestDownload: return maxNumberOfBlockLength = 66 (0x0042) => chunk = 64
        return [0x74, 0x20, 0x00, 0x42];
      };
      proto.handlers[0x36] = (req) {
        // TransferData echo: [0x76, bsc]
        return [0x76, req[1]];
      };
      proto.handlers[0x37] = (req) => [0x77]; // TransferExit
      proto.handlers[0x11] = (req) => [0x51, 0x01]; // ECU Reset

      final segmentData = Uint8List.fromList(List.generate(128, (i) => i & 0xFF));
      final testImage = VerifiedFlashImage(
        manifest: const FlashManifest(
          licensedVin: 'WBA123456789',
          engineCode: 'B58',
          stage: 'Stage 1',
          payloadSha256: 'mock',
          segments: [{'address': 0x80010000, 'length': 128}],
          createdAtEpoch: 0,
        ),
        segments: [FlashSegment(0x80010000, segmentData)],
        rawPayload: segmentData,
      );

      final checkpoints = <int>[];
      final session = UdsFlashSession(
        proto: proto,
        remoteKeyProvider: (seed) async {
          expect(seed, equals([0xAA, 0xBB, 0xCC, 0xDD]));
          return [0x12, 0x34, 0x56, 0x78]; // Server-computed key
        },
        onCheckpoint: (seg, offset) => checkpoints.add(offset),
      );

      final progressList = await session.run(testImage, allowExecutionInTest: true).toList();

      expect(progressList.last.stage, equals('COMPLETE'));
      expect(progressList.last.progress, equals(1.0));
      expect(checkpoints, equals([64, 128]));

      // Verify bus silence functional requests were dispatched
      expect(proto.recordedRequests.any((r) => r.length == 2 && r[0] == 0x85 && r[1] == 0x82), isTrue); // DTC Off
      expect(proto.recordedRequests.any((r) => r.length == 3 && r[0] == 0x28 && r[1] == 0x81), isTrue); // Comm Disable
      // Verify final reset and communication restore
      expect(proto.recordedRequests.any((r) => r.length == 2 && r[0] == 0x11 && r[1] == 0x01), isTrue); // Reset
      expect(proto.recordedRequests.any((r) => r.length == 3 && r[0] == 0x28 && r[1] == 0x80), isTrue); // Comm Enable
      expect(proto.recordedRequests.any((r) => r.length == 2 && r[0] == 0x85 && r[1] == 0x81), isTrue); // DTC On
    });

    test('NRC on Erase throws FlashAbort WITHOUT issuing ECU Reset or Clear DTC', () async {
      proto.handlers[0x10] = (req) => [0x50, req[1]];
      proto.handlers[0x27] = (req) => [0x67, req[1], 0x11, 0x22, 0x33, 0x44];
      // Erase routine returns NRC 0x72 (GeneralProgrammingFailure)
      proto.handlers[0x31] = (req) => [0x7F, 0x31, 0x72];

      final segmentData = Uint8List(64);
      final testImage = VerifiedFlashImage(
        manifest: const FlashManifest(
          licensedVin: 'WBA123',
          engineCode: 'B58',
          stage: 'Stage 1',
          payloadSha256: 'mock',
          segments: [{'address': 0x80010000, 'length': 64}],
          createdAtEpoch: 0,
        ),
        segments: [FlashSegment(0x80010000, segmentData)],
        rawPayload: segmentData,
      );

      final session = UdsFlashSession(
        proto: proto,
        remoteKeyProvider: (_) async => [0x99, 0x88, 0x77, 0x66],
      );

      try {
        await session.run(testImage, allowExecutionInTest: true).toList();
        fail('Should have thrown FlashAbort on erase NRC');
      } on FlashAbort catch (e) {
        expect(e.stage, equals('ERASE'));
        expect(e.ecuMayBeInBootloader, isTrue);
        expect(e.nrc, equals(0x72));
      }

      // CRITICAL ANTI-BRICK CHECK:
      // Verify that NO 0x11 (Reset) or 0x14 (Clear DTC) was ever sent after erase abort!
      final sentReset = proto.recordedRequests.any((r) => r.isNotEmpty && r[0] == 0x11);
      final sentClearDtc = proto.recordedRequests.any((r) => r.isNotEmpty && r[0] == 0x14);
      expect(sentReset, isFalse, reason: 'NEVER send ECU reset if abort occurs during/after erase');
      expect(sentClearDtc, isFalse, reason: 'NEVER send Clear DTC during abort');
    });

    test('Block Sequence Counter (BSC) wraps correctly from 0xFF to 0x00 across 256+ blocks', () async {
      proto.handlers[0x10] = (req) => [0x50, req[1]];
      proto.handlers[0x27] = (req) => [0x67, req[1], 0x11, 0x22, 0x33, 0x44];
      proto.handlers[0x31] = (req) => [0x71, req[1], req[2], req[3], 0x00];
      // Set block length = 12 (chunk = 10 bytes)
      proto.handlers[0x34] = (req) => [0x74, 0x10, 0x0C];

      final transferredBscList = <int>[];
      proto.handlers[0x36] = (req) {
        transferredBscList.add(req[1]);
        return [0x76, req[1]];
      };
      proto.handlers[0x37] = (req) => [0x77];
      proto.handlers[0x11] = (req) => [0x51, 0x01];

      // 300 blocks of 10 bytes = 3000 bytes
      const blockCount = 300;
      final payload = Uint8List(blockCount * 10);
      final testImage = VerifiedFlashImage(
        manifest: const FlashManifest(
          licensedVin: 'WBA123',
          engineCode: 'B58',
          stage: 'Stage 1',
          payloadSha256: 'mock',
          segments: [{'address': 0x80010000, 'length': blockCount * 10}],
          createdAtEpoch: 0,
        ),
        segments: [FlashSegment(0x80010000, payload)],
        rawPayload: payload,
      );

      final session = UdsFlashSession(
        proto: proto,
        remoteKeyProvider: (_) async => [0x01, 0x02, 0x03, 0x04],
      );

      await session.run(testImage, allowExecutionInTest: true).toList();

      expect(transferredBscList.length, equals(blockCount));
      // First block is BSC 1
      expect(transferredBscList[0], equals(1));
      // Block 255 (index 254) has BSC 255 (0xFF)
      expect(transferredBscList[254], equals(0xFF));
      // Block 256 (index 255) must WRAP to 0x00 per ISO 14229-1!
      expect(transferredBscList[255], equals(0x00));
      // Block 257 (index 256) is 0x01
      expect(transferredBscList[256], equals(0x01));
    });
  });
}
