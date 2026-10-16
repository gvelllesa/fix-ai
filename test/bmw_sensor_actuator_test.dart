import 'package:flutter_test/flutter_test.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_sensor_registry.dart';
import 'package:ai_car_diagnostics/modules/obd/services/bmw_live_actuator.dart';

void main() {
  group('BmwSensorRegistry Tests', () {
    test('All required tuning and diagnostic sensors are registered', () {
      final requiredSensorIds = [
        'ignition_timing_cyl1',
        'ignition_timing_cyl2',
        'ignition_timing_cyl3',
        'ignition_timing_cyl4',
        'ignition_timing_cyl5',
        'ignition_timing_cyl6',
        'knock_retard_cyl1',
        'knock_retard_cyl2',
        'knock_retard_cyl3',
        'knock_retard_cyl4',
        'knock_retard_cyl5',
        'knock_retard_cyl6',
        'intake_air_temp',
        'lambda_afr_actual',
        'lambda_afr_bank1',
        'lambda_afr_bank2',
        'lambda_target',
        'stft_bank1',
        'stft_bank2',
        'ltft_bank1',
        'boost_target',
        'boost_pre_throttle',
        'boost_deviation',
        'wastegate_duty_cycle',
        'hpfp_target',
        'engine_load_actual',
        'engine_load_target',
        'maf_air_mass',
        'vehicle_speed',
        'current_gear',
        'knock_detected',
        'flex_ethanol_pct',
        'flex_fuel_temp',
      ];

      for (final id in requiredSensorIds) {
        final sensor = BmwSensorRegistry.findById(id);
        expect(sensor, isNotNull, reason: 'Sensor $id should be registered');
      }
    });

    test('Signed sensor conversion works properly (negative ignition timing)', () {
      final ign1 = BmwSensorRegistry.findById('ignition_timing_cyl1')!;
      expect(ign1.isSigned, isTrue);

      // Raw value 0xFFCE (-50 in 16-bit 2s complement) * 0.1 = -5.0 deg
      final convertedNeg = ign1.convertRaw(0xFFCE);
      expect(convertedNeg, closeTo(-5.0, 0.01));

      // Raw value 150 * 0.1 = +15.0 deg
      final convertedPos = ign1.convertRaw(150);
      expect(convertedPos, closeTo(15.0, 0.01));
    });

    test('IAT scaling and offset test', () {
      final iat = BmwSensorRegistry.findById('intake_air_temp')!;
      // Raw 100 * 0.75 - 48 = 75 - 48 = 27.0 °C
      expect(iat.convertRaw(100), closeTo(27.0, 0.01));
      // Raw 64 * 0.75 - 48 = 48 - 48 = 0.0 °C
      expect(iat.convertRaw(64), closeTo(0.0, 0.01));
    });

    test('Lambda AFR actual calculation', () {
      final afr = BmwSensorRegistry.findById('lambda_afr_actual')!;
      // Raw 4096 (lambda 1.0) -> ~14.70 AFR
      expect(afr.convertRaw(4096), closeTo(14.70, 0.05));
    });

    test('Category filtering contains correct groups', () {
      final drivetrain = BmwSensorRegistry.getByCategory('Drivetrain');
      expect(drivetrain.any((s) => s.id == 'engine_rpm'), isTrue);
      expect(drivetrain.any((s) => s.id == 'vehicle_speed'), isTrue);
      expect(drivetrain.any((s) => s.id == 'current_gear'), isTrue);

      final boost = BmwSensorRegistry.getByCategory('Boost & Air');
      expect(boost.any((s) => s.id == 'boost_target'), isTrue);
      expect(boost.any((s) => s.id == 'wastegate_duty_cycle'), isTrue);

      final ignition = BmwSensorRegistry.getByCategory('Ignition & Knock');
      expect(ignition.any((s) => s.id == 'ignition_timing_cyl1'), isTrue);
      expect(ignition.any((s) => s.id == 'knock_retard_cyl1'), isTrue);
    });

    test('Value formatting for gear and flags', () {
      final gear = BmwSensorRegistry.findById('current_gear')!;
      expect(gear.formatValue(0), equals('P/N'));
      expect(gear.formatValue(3), equals('D3'));
      expect(gear.formatValue(255), equals('R'));

      final knock = BmwSensorRegistry.findById('knock_detected')!;
      expect(knock.formatValue(0), equals('NO'));
      expect(knock.formatValue(1), equals('YES'));
    });
  });

  group('BmwLiveActuator Class Tests', () {
    test('Default states are initialized safely', () {
      final actuator = BmwLiveActuator();
      expect(actuator.isCoolantBleedingActive, isFalse);
      expect(actuator.radiatorFanSpeed, equals(0));
      expect(actuator.isFuelTankVentValveActive, isFalse);
      expect(actuator.isExhaustFlapOpen, isFalse);
      expect(actuator.isIntakeVanosActive, isFalse);
      expect(actuator.isExhaustVanosActive, isFalse);
      expect(actuator.isNeedleSweepRunning, isFalse);
    });
  });
}
