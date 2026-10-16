import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_service_functions.dart';

void main() {
  group('BimmerLink Sound & Power Functions Tests', () {
    test('1. Lithium Battery (LiFePO4) Profile (res_battRegLithium)', () {
      expect(BatteryProfile.values, contains(BatteryProfile.lithium69));

      final lithium = BatteryProfile.lithium69;
      expect(lithium.capacityAh, equals(69));
      expect(lithium.isAgm, isFalse);
      expect(lithium.codingByte, equals(0x07));
      expect(lithium.label, contains('69 Ah Lithium-Ion (LiFePO4 - M3/M4)'));
      expect(lithium.isLithium, isTrue);

      // Verify AGM profiles are not lithium
      expect(BatteryProfile.agm90.isLithium, isFalse);
      expect(BatteryProfile.leadAcid80.isLithium, isFalse);
    });

    test('2. Active Sound Design (ASD) Enums & DIDs (activity_asd.xml)', () {
      expect(AsdState.values.length, equals(3));

      expect(AsdState.active.codeByte, equals(0x01));
      expect(AsdState.active.label, contains('Active'));

      expect(AsdState.muted.codeByte, equals(0x00));
      expect(AsdState.muted.label, contains('Muted'));

      expect(AsdState.reduced.codeByte, equals(0x02));
      expect(AsdState.reduced.label, contains('Reduced'));

      // ECU Constants
      expect(BmwServiceFunctions.asdAddress, equals(0x20));
      expect(BmwServiceFunctions.huNbtAddress, equals(0x63));
      expect(BmwServiceFunctions.didAsdFunctions, equals(0x3000));
    });

    test('3. Exhaust Flap 3-Way Control Enums & Commands (activity_exhaust_flap.xml)', () {
      expect(ExhaustFlapMode.values.length, equals(3));

      expect(ExhaustFlapMode.autoOem.ioParameter, equals(0x00));
      expect(ExhaustFlapMode.autoOem.controlState, isNull);

      expect(ExhaustFlapMode.forceOpen.ioParameter, equals(0x03));
      expect(ExhaustFlapMode.forceOpen.controlState, equals(0x01));

      expect(ExhaustFlapMode.forceClosed.ioParameter, equals(0x03));
      expect(ExhaustFlapMode.forceClosed.controlState, equals(0x00));

      // Constants
      expect(BmwServiceFunctions.dmeAddress, equals(0x12));
      expect(BmwServiceFunctions.udsInputOutputControl, equals(0x2F));
      expect(BmwServiceFunctions.didExhaustFlap, equals(0x310A));
    });

    test('4. Exact UDS Payloads for Exhaust Flap Control', () {
      // forceOpen: [0x2F, 0x31, 0x0A, 0x03, 0x01]
      final forceOpenPayload = [
        BmwServiceFunctions.udsInputOutputControl,
        (BmwServiceFunctions.didExhaustFlap >> 8) & 0xFF,
        BmwServiceFunctions.didExhaustFlap & 0xFF,
        ExhaustFlapMode.forceOpen.ioParameter,
        ExhaustFlapMode.forceOpen.controlState!,
      ];
      expect(forceOpenPayload, equals([0x2F, 0x31, 0x0A, 0x03, 0x01]));

      // forceClosed: [0x2F, 0x31, 0x0A, 0x03, 0x00]
      final forceClosedPayload = [
        BmwServiceFunctions.udsInputOutputControl,
        (BmwServiceFunctions.didExhaustFlap >> 8) & 0xFF,
        BmwServiceFunctions.didExhaustFlap & 0xFF,
        ExhaustFlapMode.forceClosed.ioParameter,
        ExhaustFlapMode.forceClosed.controlState!,
      ];
      expect(forceClosedPayload, equals([0x2F, 0x31, 0x0A, 0x03, 0x00]));

      // autoOem: [0x2F, 0x31, 0x0A, 0x00]
      final autoOemPayload = [
        BmwServiceFunctions.udsInputOutputControl,
        (BmwServiceFunctions.didExhaustFlap >> 8) & 0xFF,
        BmwServiceFunctions.didExhaustFlap & 0xFF,
        ExhaustFlapMode.autoOem.ioParameter,
      ];
      expect(autoOemPayload, equals([0x2F, 0x31, 0x0A, 0x00]));
    });

    test('5. ASD Write Payloads for DID 0x3000', () {
      final activePayload = [
        BmwServiceFunctions.udsWriteDataById,
        (BmwServiceFunctions.didAsdFunctions >> 8) & 0xFF,
        BmwServiceFunctions.didAsdFunctions & 0xFF,
        AsdState.active.codeByte,
      ];
      expect(activePayload, equals([0x2E, 0x30, 0x00, 0x01]));

      final mutedPayload = [
        BmwServiceFunctions.udsWriteDataById,
        (BmwServiceFunctions.didAsdFunctions >> 8) & 0xFF,
        BmwServiceFunctions.didAsdFunctions & 0xFF,
        AsdState.muted.codeByte,
      ];
      expect(mutedPayload, equals([0x2E, 0x30, 0x00, 0x00]));

      final reducedPayload = [
        BmwServiceFunctions.udsWriteDataById,
        (BmwServiceFunctions.didAsdFunctions >> 8) & 0xFF,
        BmwServiceFunctions.didAsdFunctions & 0xFF,
        AsdState.reduced.codeByte,
      ];
      expect(reducedPayload, equals([0x2E, 0x30, 0x00, 0x02]));
    });
  });
}
