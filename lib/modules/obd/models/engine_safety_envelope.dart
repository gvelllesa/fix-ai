import '../services/bmw_flash_options.dart';

/// Hard safety boundaries defined per BMW engine architecture.
/// 
/// Enforces physical limits for boost pressure, ignition retard, fuel rail pressure,
/// and anti-lag durations. Prevents catastrophic engine failure (piston ringland cracking,
/// rod bending, turbo overspeed, or valve float) from over-aggressive calibrations.
class EngineSafetyEnvelope {
  final String engineCode;
  final double maxBoostPsi;
  final double maxIgnitionRetardDeg;
  final double maxHpfpRailPressureBar;
  final double maxEthanolPercent;
  final int maxAntiLagDurationSeconds;

  const EngineSafetyEnvelope({
    required this.engineCode,
    required this.maxBoostPsi,
    required this.maxIgnitionRetardDeg,
    required this.maxHpfpRailPressureBar,
    required this.maxEthanolPercent,
    required this.maxAntiLagDurationSeconds,
  });

  // ==========================================
  // Engine-Specific Safety Calibration Envelopes
  // ==========================================

  /// BMW N20B20 (2.0L 4-Cyl Turbo - Cast pistons & open deck block)
  /// // TODO(calibration-engineer): verify engine safety thresholds with dyno logs for N20
  static const EngineSafetyEnvelope n20 = EngineSafetyEnvelope(
    engineCode: 'N20',
    maxBoostPsi: 22.0,
    maxIgnitionRetardDeg: 12.0,
    maxHpfpRailPressureBar: 200.0,
    maxEthanolPercent: 50.0, // Stock HPFP fuel volume limited
    maxAntiLagDurationSeconds: 3,
  );

  /// BMW N55B30 (3.0L Inline-6 TwinScroll - Cast pistons & iron cylinder sleeves)
  /// // TODO(calibration-engineer): verify engine safety thresholds with dyno logs for N55
  static const EngineSafetyEnvelope n55 = EngineSafetyEnvelope(
    engineCode: 'N55',
    maxBoostPsi: 22.5,
    maxIgnitionRetardDeg: 15.0,
    maxHpfpRailPressureBar: 220.0,
    maxEthanolPercent: 60.0,
    maxAntiLagDurationSeconds: 4,
  );

  /// BMW B58B30 (3.0L Modular Inline-6 - Closed deck, forged crank & rods)
  /// // TODO(calibration-engineer): verify engine safety thresholds with dyno logs for B58
  static const EngineSafetyEnvelope b58 = EngineSafetyEnvelope(
    engineCode: 'B58',
    maxBoostPsi: 25.0,
    maxIgnitionRetardDeg: 18.0,
    maxHpfpRailPressureBar: 350.0, // Gen 2 DI system rated to 350 Bar
    maxEthanolPercent: 85.0,
    maxAntiLagDurationSeconds: 5,
  );

  /// BMW S55B30 (3.0L M Power Twin Turbo - Closed deck, twin-turbo, crank hub sensitive)
  /// // TODO(calibration-engineer): verify engine safety thresholds with dyno logs for S55
  static const EngineSafetyEnvelope s55 = EngineSafetyEnvelope(
    engineCode: 'S55',
    maxBoostPsi: 28.0,
    maxIgnitionRetardDeg: 20.0,
    maxHpfpRailPressureBar: 220.0,
    maxEthanolPercent: 85.0,
    maxAntiLagDurationSeconds: 4,
  );

  /// BMW S58B30 (3.0L M Power Twin Turbo G8x - 3D printed cylinder head core, 350 Bar DI)
  /// // TODO(calibration-engineer): verify engine safety thresholds with dyno logs for S58
  static const EngineSafetyEnvelope s58 = EngineSafetyEnvelope(
    engineCode: 'S58',
    maxBoostPsi: 32.0,
    maxIgnitionRetardDeg: 20.0,
    maxHpfpRailPressureBar: 350.0,
    maxEthanolPercent: 85.0,
    maxAntiLagDurationSeconds: 5,
  );

  /// Retrieves the strict safety envelope for a specific engine identifier
  static EngineSafetyEnvelope forEngine(String rawEngineCode) {
    final normalized = rawEngineCode.toUpperCase();
    if (normalized.contains('N20') || normalized.contains('N26')) return n20;
    if (normalized.contains('N55')) return n55;
    if (normalized.contains('B58')) return b58;
    if (normalized.contains('S55')) return s55;
    if (normalized.contains('S58')) return s58;

    throw UnsupportedError(
      'უცნობი ძრავის კოდი: "$rawEngineCode". Flashing ოპერაცია შეჩერებულია უსაფრთხოების ზღვრების არარსებობის გამო.',
    );
  }

  /// Verifies that all calibration parameters in [options] strictly fall within
  /// this engine architecture's physical tolerances.
  /// 
  /// Throws [ArgumentError] if any boundary is violated (never silently modifies).
  void assertSafetyCompliance(BmwFlashOptions options) {
    // 1. Rolling Anti-Lag Boost Target
    if (options.antiLag.enabled && options.antiLag.boostTargetPsi > maxBoostPsi) {
      throw ArgumentError(
        'უსაფრთხოების ზღვრის დარღვევა ($engineCode): Anti-Lag ტურბინის წნევა (${options.antiLag.boostTargetPsi} PSI) აღემატება დასაშვებ მაქსიმუმს ($maxBoostPsi PSI).',
      );
    }

    // 2. Rolling Anti-Lag Ignition Retard
    if (options.antiLag.enabled && options.antiLag.ignitionRetardDeg > maxIgnitionRetardDeg) {
      throw ArgumentError(
        'უსაფრთხოების ზღვრის დარღვევა ($engineCode): ანთების დაგვიანება (${options.antiLag.ignitionRetardDeg}° ATDC) აღემატება კრიტიკულ ზღვარს ($maxIgnitionRetardDeg° ATDC) — გამოსაბოლქვი სარქველების გადახურების საფრთხე.',
      );
    }

    // 3. Rolling Anti-Lag Duration
    if (options.antiLag.enabled && options.antiLag.maxDurationSeconds > maxAntiLagDurationSeconds) {
      throw ArgumentError(
        'უსაფრთხოების ზღვრის დარღვევა ($engineCode): Anti-Lag ხანგრძლივობა (${options.antiLag.maxDurationSeconds}წმ) აღემატება დასაშვებ $maxAntiLagDurationSeconds წამს.',
      );
    }

    // 4. Boost by Gear Limits
    if (options.boostByGear.enabled) {
      for (int i = 0; i < options.boostByGear.gearLimitsPsi.length; i++) {
        final gearLimit = options.boostByGear.gearLimitsPsi[i];
        if (gearLimit > maxBoostPsi) {
          throw ArgumentError(
            'უსაფრთხოების ზღვრის დარღვევა ($engineCode): სიჩქარე ${i + 1}-ის წნევა ($gearLimit PSI) აღემატება $maxBoostPsi PSI-ს.',
          );
        }
      }
    }

    // 5. HPFP Target Pressure
    if (options.hpfp.maxPressureBar > maxHpfpRailPressureBar) {
      throw ArgumentError(
        'უსაფრთხოების ზღვრის დარღვევა ($engineCode): HPFP წნევა (${options.hpfp.maxPressureBar} Bar) აღემატება საწვავის რეილის უსაფრთხო ზღვარს ($maxHpfpRailPressureBar Bar).',
      );
    }
  }
}
