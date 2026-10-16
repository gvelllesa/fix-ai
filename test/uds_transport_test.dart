import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';

/// Test protocol subclass that intercepts outgoing HSFZ frames and allows
/// feeding responses back via [emitMessageForTest] or [handleRawBytesForTest].
class FakeUdsProtocol extends EnetHsfzProtocol {
  final List<List<int>> sentRequests = [];
  void Function(int dst, List<int> payload)? onSendHsfz;

  @override
  bool get isConnected => true;

  @override
  Future<void> sendHsfz(int dst, List<int> udsPayload, {int src = EnetHsfzProtocol.testerAddress}) async {
    sentRequests.add(udsPayload);
    onSendHsfz?.call(dst, udsPayload);
  }
}

void main() {
  group('P1.1 & P1.7: UDS Transport & Parser Hardening Tests', () {
    test('1. Two concurrent 0x22 requests with different DIDs receive their respective correct responses', () async {
      final protocol = FakeUdsProtocol();

      protocol.onSendHsfz = (dst, payload) {
        if (payload[0] == 0x22 && payload.length >= 3) {
          final d1 = payload[1];
          final d2 = payload[2];
          // Asynchronously emit response for the specific DID
          Future.microtask(() {
            protocol.emitMessageForTest(HsfzMessage(
              sourceAddress: dst,
              targetAddress: EnetHsfzProtocol.testerAddress,
              messageType: EnetHsfzProtocol.hsfzTypeData,
              payload: Uint8List.fromList([0x62, d1, d2, 0xAA, 0xBB]),
            ));
          });
        }
      };

      // Launch both simultaneously
      final future1 = protocol.sendUdsAndAwait(0x12, [0x22, 0xF1, 0x90]);
      final future2 = protocol.sendUdsAndAwait(0x12, [0x22, 0x58, 0x15]);

      final res1 = await future1;
      final res2 = await future2;

      expect(res1, isNotNull);
      expect(res1![0], 0x62);
      expect(res1[1], 0xF1);
      expect(res1[2], 0x90);

      expect(res2, isNotNull);
      expect(res2![0], 0x62);
      expect(res2[1], 0x58);
      expect(res2[2], 0x15);
    });

    test('2. NRC 0x78 (responsePending) twice followed by positive routine response returns positive response', () async {
      final protocol = FakeUdsProtocol();

      protocol.onSendHsfz = (dst, payload) {
        if (payload[0] == 0x31) {
          Timer(const Duration(milliseconds: 20), () {
            // First NRC 0x78
            protocol.emitMessageForTest(HsfzMessage(
              sourceAddress: dst,
              targetAddress: EnetHsfzProtocol.testerAddress,
              messageType: EnetHsfzProtocol.hsfzTypeData,
              payload: Uint8List.fromList([0x7F, 0x31, 0x78]),
            ));
          });
          Timer(const Duration(milliseconds: 50), () {
            // Second NRC 0x78
            protocol.emitMessageForTest(HsfzMessage(
              sourceAddress: dst,
              targetAddress: EnetHsfzProtocol.testerAddress,
              messageType: EnetHsfzProtocol.hsfzTypeData,
              payload: Uint8List.fromList([0x7F, 0x31, 0x78]),
            ));
          });
          Timer(const Duration(milliseconds: 90), () {
            // Final positive response: 0x71 subfunc(0x01) RID(0xFF, 0x01) result(0x00)
            protocol.emitMessageForTest(HsfzMessage(
              sourceAddress: dst,
              targetAddress: EnetHsfzProtocol.testerAddress,
              messageType: EnetHsfzProtocol.hsfzTypeData,
              payload: Uint8List.fromList([0x71, 0x01, 0xFF, 0x01, 0x00]),
            ));
          });
        }
      };

      final res = await protocol.sendUdsAndAwait(
        0x12,
        [0x31, 0x01, 0xFF, 0x01],
        timeout: const Duration(milliseconds: 300),
        p2Star: const Duration(milliseconds: 300),
      );

      expect(res, isNotNull);
      expect(res![0], 0x71);
      expect(res[1], 0x01);
      expect(res[2], 0xFF);
      expect(res[3], 0x01);
      expect(res[4], 0x00);
    });

    test('3. Response with mismatched DID echo is ignored and call times out', () async {
      final protocol = FakeUdsProtocol();

      protocol.onSendHsfz = (dst, payload) {
        // Send a frame with a DIFFERENT DID (0x58 0x0D instead of requested 0xF1 0x90)
        Future.microtask(() {
          protocol.emitMessageForTest(HsfzMessage(
            sourceAddress: dst,
            targetAddress: EnetHsfzProtocol.testerAddress,
            messageType: EnetHsfzProtocol.hsfzTypeData,
            payload: Uint8List.fromList([0x62, 0x58, 0x0D, 0x00]),
          ));
        });
      };

      final res = await protocol.sendUdsAndAwait(
        0x12,
        [0x22, 0xF1, 0x90],
        timeout: const Duration(milliseconds: 50),
      );

      expect(res, isNull, reason: 'Mismatched echo must be ignored and not steal the completer');
    });

    test('4. suppressPosRsp bit in request (req[1] & 0x80) returns immediately without awaiting response', () async {
      final protocol = FakeUdsProtocol();

      // TesterPresent with suppressPosRsp bit (0x3E 0x80)
      final res = await protocol.sendUdsAndAwait(
        0x12,
        [0x3E, 0x80],
        timeout: const Duration(seconds: 5),
      );

      expect(res, isNotNull);
      expect(res, isEmpty);
      expect(protocol.sentRequests, hasLength(1));
      expect(protocol.sentRequests[0], [0x3E, 0x80]);
    });

    test('5. Fragmented HSFZ frame delivered byte-by-byte is parsed correctly by offset buffer', () async {
      final protocol = EnetHsfzProtocol();
      final messages = <HsfzMessage>[];
      final sub = protocol.messageStream.listen(messages.add);

      // Packet: [4B len = 0x00000005] [2B type = 0x0001] [src 0x12] [dst 0xF4] [payload 0x62 0xF1 0x90]
      final raw = <int>[
        0x00, 0x00, 0x00, 0x05, // body length 5
        0x00, 0x01,             // msg type data
        0x12, 0xF4,             // src, dst
        0x62, 0xF1, 0x90,       // UDS payload
      ];

      for (final byte in raw) {
        protocol.handleRawBytesForTest([byte]);
      }

      await Future.delayed(const Duration(milliseconds: 10));
      expect(messages, hasLength(1));
      expect(messages[0].sourceAddress, 0x12);
      expect(messages[0].targetAddress, 0xF4);
      expect(messages[0].payload, [0x62, 0xF1, 0x90]);

      await sub.cancel();
      protocol.dispose();
    });

    test('6. Two coalesced HSFZ frames in a single chunk are both parsed', () async {
      final protocol = EnetHsfzProtocol();
      final messages = <HsfzMessage>[];
      final sub = protocol.messageStream.listen(messages.add);

      final chunk = <int>[
        // Frame 1: 0x62 0x58 0x15
        0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x12, 0xF4, 0x62, 0x58, 0x15,
        // Frame 2: 0x62 0x20 0x00
        0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x12, 0xF4, 0x62, 0x20, 0x00,
      ];

      protocol.handleRawBytesForTest(chunk);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(messages, hasLength(2));
      expect(messages[0].payload, [0x62, 0x58, 0x15]);
      expect(messages[1].payload, [0x62, 0x20, 0x00]);

      await sub.cancel();
      protocol.dispose();
    });

    test('7. Corrupted bodyLength (>64KB+2) triggers byte-by-byte resync without crash', () async {
      final protocol = EnetHsfzProtocol();
      final messages = <HsfzMessage>[];
      final sub = protocol.messageStream.listen(messages.add);

      final garbage = <int>[0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x01];
      final valid = <int>[
        0x00, 0x00, 0x00, 0x05, 0x00, 0x01, 0x12, 0xF4, 0x62, 0xF1, 0x90,
      ];

      protocol.handleRawBytesForTest([...garbage, ...valid]);

      await Future.delayed(const Duration(milliseconds: 10));
      expect(messages, hasLength(1));
      expect(messages[0].payload, [0x62, 0xF1, 0x90]);

      await sub.cancel();
      protocol.dispose();
    });
  });
}
