import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/protocols/enet_hsfz_protocol.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_manager.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_flash_options.dart';

class MockSafetyProtocol extends EnetHsfzProtocol {
  final Map<String, List<int>> _responses = {};
  final List<List<int>> recordedRequests = [];

  void setResponse(int targetEcu, List<int> req, List<int> rsp) {
    _responses['$targetEcu:${req.join(",")}'] = rsp;
  }

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
    final key = '$targetEcu:${udsPayload.join(",")}';
    if (_responses.containsKey(key)) {
      return Uint8List.fromList(_responses[key]!);
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
  group('BMW Flash Manager & Fail-Closed Vehicle Safety Tests', () {
    late MockSafetyProtocol mockProto;
    late BmwFlashManager flashManager;

    setUp(() {
      mockProto = MockSafetyProtocol();
      flashManager = BmwFlashManager(protocol: mockProto);
    });

    test('1. Pre-flight check FAILS-CLOSED when battery voltage read returns null', () async {
      // No voltage response configured
      final result = await flashManager.runPreFlightChecks();
      expect(result.passed, isFalse);
      expect(result.errorMessages.any((e) => e.contains('აკუმულატორის ძაბვა ვერ წაიკითხა')), isTrue);
    });

    test('2. Pre-flight check FAILS-CLOSED when battery voltage is below 12.50V (e.g. 12.10V)', () async {
      // 12.10V = 12100 mV = 0x2F44 -> [0x62, 0x58, 0x15, 0x2F, 0x44]
      mockProto.setResponse(0x12, [0x22, 0x58, 0x15], [0x62, 0x58, 0x15, 0x2F, 0x44]);
      // RPM = 0 -> [0x62, 0x20, 0x00, 0x00, 0x00]
      mockProto.setResponse(0x12, [0x22, 0x20, 0x00], [0x62, 0x20, 0x00, 0x00, 0x00]);
      // Speed = 0 -> [0x62, 0x58, 0x0D, 0x00]
      mockProto.setResponse(0x12, [0x22, 0x58, 0x0D], [0x62, 0x58, 0x0D, 0x00]);
      // VIN valid 17 chars
      mockProto.setResponse(0x12, [0x22, 0xF1, 0x90], [0x62, 0xF1, 0x90, ...'WBA3A5C50DF123456'.codeUnits]);

      final result = await flashManager.runPreFlightChecks();
      expect(result.passed, isFalse);
      expect(result.batteryVoltage, closeTo(12.10, 0.05));
      expect(result.errorMessages.any((e) => e.contains('12.50V')), isTrue);
    });

    test('3. Pre-flight check FAILS-CLOSED when engine is running (RPM = 800)', () async {
      // 13.50V -> [0x62, 0x58, 0x15, 0x34, 0xBC] (13500 mV)
      mockProto.setResponse(0x12, [0x22, 0x58, 0x15], [0x62, 0x58, 0x15, 0x34, 0xBC]);
      // RPM = 800 * 4 = 3200 = 0x0C80 -> [0x62, 0x20, 0x00, 0x0C, 0x80]
      mockProto.setResponse(0x12, [0x22, 0x20, 0x00], [0x62, 0x20, 0x00, 0x0C, 0x80]);
      // Speed = 0
      mockProto.setResponse(0x12, [0x22, 0x58, 0x0D], [0x62, 0x58, 0x0D, 0x00]);
      // VIN valid 17 chars
      mockProto.setResponse(0x12, [0x22, 0xF1, 0x90], [0x62, 0xF1, 0x90, ...'WBA3A5C50DF123456'.codeUnits]);

      final result = await flashManager.runPreFlightChecks();
      expect(result.passed, isFalse);
      expect(result.isIgnitionOnEngineOff, isFalse);
      expect(result.errorMessages.any((e) => e.contains('ძრავი ამჟამად მუშაობს')), isTrue);
    });

    test('4. Pre-flight check passes only when all safety interlocks are 100% verified', () async {
      // 13.80V -> 13800 mV = 0x35E8
      mockProto.setResponse(0x12, [0x22, 0x58, 0x15], [0x62, 0x58, 0x15, 0x35, 0xE8]);
      // RPM = 0
      mockProto.setResponse(0x12, [0x22, 0x20, 0x00], [0x62, 0x20, 0x00, 0x00, 0x00]);
      // Speed = 0
      mockProto.setResponse(0x12, [0x22, 0x58, 0x0D], [0x62, 0x58, 0x0D, 0x00]);
      // VIN valid 17 chars
      mockProto.setResponse(0x12, [0x22, 0xF1, 0x90], [0x62, 0xF1, 0x90, ...'WBA3A5C50DF123456'.codeUnits]);

      final result = await flashManager.runPreFlightChecks();
      expect(result.passed, isTrue);
      expect(result.batteryVoltage, closeTo(13.80, 0.05));
      expect(result.isIgnitionOnEngineOff, isTrue);
      expect(result.vin, 'WBA3A5C50DF123456');
      expect(result.errorMessages, isEmpty);
    });

    test('5. executeFlash locks down (SAFETY_LOCK) and does NOT touch DME flash when no verified container is provided', () async {
      // Configure good preflight
      mockProto.setResponse(0x12, [0x22, 0x58, 0x15], [0x62, 0x58, 0x15, 0x35, 0xE8]);
      mockProto.setResponse(0x12, [0x22, 0x20, 0x00], [0x62, 0x20, 0x00, 0x00, 0x00]);
      mockProto.setResponse(0x12, [0x22, 0x58, 0x0D], [0x62, 0x58, 0x0D, 0x00]);
      mockProto.setResponse(0x12, [0x22, 0xF1, 0x90], [0x62, 0xF1, 0x90, ...'WBA3A5C50DF123456'.codeUnits]);

      final events = await flashManager.executeFlash(options: BmwFlashOptions()).toList();
      final lastEvent = events.last;

      expect(lastEvent['step'], 'SAFETY_LOCK');
      expect(lastEvent['success'], isFalse);
      expect(lastEvent['message'], contains('უსაფრთხოების ბლოკი'));

      // Ensure NO dangerous 0x34 RequestDownload or 0x36 TransferData was ever issued
      final dangerousSids = mockProto.recordedRequests.where(
        (req) => req.isNotEmpty && (req[0] == 0x34 || req[0] == 0x36 || req[0] == 0x37),
      );
      expect(dangerousSids, isEmpty);
    });

    test('6. recoverDmeSession NEVER issues 0x11 Reset or 0x14 Clear DTC during recovery', () async {
      mockProto.setResponse(0x12, [0x22, 0xF1, 0x90], [0x62, 0xF1, 0x90, ...'WBA3A5C50DF123456'.codeUnits]);

      final recovered = await flashManager.recoverDmeSession();
      expect(recovered, isTrue);

      // Verify that 0x11 (ECUReset) was NEVER called
      final resetCalls = mockProto.recordedRequests.where(
        (req) => req.isNotEmpty && req[0] == 0x11,
      );
      expect(resetCalls, isEmpty, reason: 'ECU Reset (0x11) must never be called during recovery to prevent bricking');

      // Verify that 0x14 (ClearDTC) was NEVER called
      final clearCalls = mockProto.recordedRequests.where(
        (req) => req.isNotEmpty && req[0] == 0x14,
      );
      expect(clearCalls, isEmpty, reason: 'DTC clear (0x14) must not be called during recovery session');
    });
  });
}
