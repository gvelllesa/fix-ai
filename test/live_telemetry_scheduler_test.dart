import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/live_telemetry_service.dart';
import 'package:ai_car_diagnostics/modules/obd/services/connection_manager.dart';
import 'uds_transport_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P3.1 & P3.2: LiveTelemetryScheduler & Gauge Tests', () {
    test('priorityForSensor correctly classifies high, medium, and low priority sensors', () {
      expect(LiveTelemetryService.priorityForSensor('engine_rpm'), equals(TelemetryPriority.high));
      expect(LiveTelemetryService.priorityForSensor('boost_pressure'), equals(TelemetryPriority.high));
      expect(LiveTelemetryService.priorityForSensor('ignition_timing_cyl1'), equals(TelemetryPriority.high));
      expect(LiveTelemetryService.priorityForSensor('knock_detected'), equals(TelemetryPriority.high));

      expect(LiveTelemetryService.priorityForSensor('wideband_lambda_bank1'), equals(TelemetryPriority.medium));
      expect(LiveTelemetryService.priorityForSensor('short_term_fuel_trim_b1'), equals(TelemetryPriority.medium));
      expect(LiveTelemetryService.priorityForSensor('throttle_valve_angle'), equals(TelemetryPriority.medium));

      expect(LiveTelemetryService.priorityForSensor('engine_coolant_temperature'), equals(TelemetryPriority.low));
      expect(LiveTelemetryService.priorityForSensor('engine_oil_temperature'), equals(TelemetryPriority.low));
      expect(LiveTelemetryService.priorityForSensor('battery_voltage'), equals(TelemetryPriority.low));
    });

    test('getSensorNotifier returns dedicated ValueNotifier that reflects sensor updates', () {
      final fakeProtocol = FakeUdsProtocol();
      final service = LiveTelemetryService(protocol: fakeProtocol);

      final rpmNotifier = service.getSensorNotifier('engine_rpm');
      final boostNotifier = service.getSensorNotifier('boost_pressure');

      expect(rpmNotifier.value, equals(0.0));
      expect(boostNotifier.value, equals(0.0));

      rpmNotifier.value = 2450.0;
      expect(rpmNotifier.value, equals(2450.0));

      // Same instance returned on subsequent calls
      expect(service.getSensorNotifier('engine_rpm'), same(rpmNotifier));

      service.dispose();
    });

    test('Telemetry scheduler skips polling when ConnectionManager.instance.isExclusiveActive is true', () async {
      final fakeProtocol = FakeUdsProtocol();
      final service = LiveTelemetryService(protocol: fakeProtocol);

      // Lock exclusive mutex (e.g. flashing active)
      ConnectionManager.instance.isExclusiveLocked.value = true;
      expect(ConnectionManager.instance.isExclusiveActive, isTrue);

      service.startPolling(tick: const Duration(milliseconds: 10));

      // Wait 50ms
      await Future.delayed(const Duration(milliseconds: 50));

      // No UDS requests should have been sent over the wire while exclusive lock is held
      expect(fakeProtocol.sentRequests.isEmpty, isTrue, reason: 'Must not send telemetry during exclusive flash/coding mutex');

      // Unlock
      ConnectionManager.instance.isExclusiveLocked.value = false;
      service.stopPolling();
      service.dispose();
    });
  });
}
