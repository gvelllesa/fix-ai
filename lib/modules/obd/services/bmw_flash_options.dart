import 'dart:typed_data';

/// Cooling mode target temperatures for BMW DME (N55/B58/S55)
enum CoolingTargetMode {
  stock(105, 'Stock (105°C - 108°C)', 'Factory fuel economy target'),
  sport(95, 'Sport Cooling (95°C)', 'Lower engine bay & oil temp, better thermal headroom'),
  track(85, 'Track Cooling (85°C)', 'Maximum cooling for track days and heavy loads');

  final int targetTempCelsius;
  final String label;
  final String description;

  const CoolingTargetMode(this.targetTempCelsius, this.label, this.description);
}

/// Exhaust burble aggressiveness
enum BurbleAggressiveness {
  off('Off', 0),
  oem('OEM / Subtle', 1),
  soft('Soft', 2),
  medium('Medium', 3),
  hard('Hard / Aggressive', 4);

  final String label;
  final int level;

  const BurbleAggressiveness(this.label, this.level);
}

/// OTS (Off The Shelf) Map Stages
enum OtsMapStage {
  stage0('Stage 0 (OEM / Stock Power)', 'Original factory calibration'),
  stage1_91('Stage 1 (91 Oct / 95 RON)', 'Up to +60 HP on stock hardware'),
  stage1_93('Stage 1 (93 Oct / 98 RON)', 'Up to +75 HP on stock hardware'),
  stage2_91('Stage 2 (91 Oct / 95 RON)', 'Requires high-flow downpipe (+90 HP)'),
  stage2_93('Stage 2 (93 Oct / 98 RON)', 'Requires high-flow downpipe (+110 HP)'),
  // ignore: constant_identifier_names
  stage2plus_e30('Stage 2+ (E30 Ethanol blend)', 'Requires upgraded intercooler & HPFP (+130 HP)');

  final String title;
  final String requirement;

  const OtsMapStage(this.title, this.requirement);
}

/// Supported FlexFuel Sensor integration types
enum FlexFuelSensorType {
  canBus0x4F0('CAN Bus Broadcast (0x4F0)', 'Zeitronix ECA-2 / BM3 / Motiv Reflex CAN'),
  dmeRamDid('DME Internal RAM DID (0xD410)', 'Direct DME RAM analog sensor lookup'),
  analogPin('Analog 0-5V Input', 'Continental flex sensor wired to DME analog pin');

  final String label;
  final String description;

  const FlexFuelSensorType(this.label, this.description);
}

/// HPFP (High Pressure Fuel Pump) Flow Scaling Profiles
/// Calibration values match BM3 & MHD binary pump volume scalar (KL_KRS) and PRMAX tables.
enum HpfpProfile {
  oem(
    id: 0,
    name: 'oem',
    label: 'OEM / Stock HPFP (Bosch HDP5/6)',
    flowScalar: 1.00,
    maxPressureBar: 200,
    description: 'Factory flow rating up to ~450whp (200 Bar limit)',
  ),
  dorchStage1(
    id: 1,
    name: 'dorchStage1',
    label: 'Dorch Engineering Stage 1',
    flowScalar: 1.34,
    maxPressureBar: 200,
    description: '34% higher flow, supports up to E50 / 550whp',
  ),
  dorchStage2(
    id: 2,
    name: 'dorchStage2',
    label: 'Dorch Engineering Stage 2',
    flowScalar: 1.68,
    maxPressureBar: 250,
    description: '68% higher flow, full E85 capable, 250 Bar rail limit',
  ),
  dorchStage2_5(
    id: 3,
    name: 'dorchStage2_5',
    label: 'Dorch Engineering Stage 2.5',
    flowScalar: 1.84,
    maxPressureBar: 250,
    description: '84% higher flow, extreme DI flow for 750+whp',
  ),
  spoolFX150(
    id: 4,
    name: 'spoolFX150',
    label: 'Spool Performance FX150',
    flowScalar: 1.50,
    maxPressureBar: 200,
    description: '50% flow increase over stock pump',
  ),
  spoolFX170(
    id: 5,
    name: 'spoolFX170',
    label: 'Spool Performance FX170',
    flowScalar: 1.70,
    maxPressureBar: 230,
    description: '70% flow increase, supports full E85',
  ),
  spoolFX200(
    id: 6,
    name: 'spoolFX200',
    label: 'Spool Performance FX200',
    flowScalar: 2.00,
    maxPressureBar: 250,
    description: 'Double OEM flow rate for big turbo builds',
  ),
  xdi35(
    id: 7,
    name: 'xdi35',
    label: 'XDI HPFP-35',
    flowScalar: 1.35,
    maxPressureBar: 200,
    description: 'Xtreme-DI 35% flow upgrade',
  ),
  xdi60(
    id: 8,
    name: 'xdi60',
    label: 'XDI HPFP-60',
    flowScalar: 1.60,
    maxPressureBar: 220,
    description: 'Xtreme-DI 60% flow upgrade',
  ),
  xdi40(
    id: 9,
    name: 'xdi40',
    label: 'XDI-40 (B58 Gen 1/2)',
    flowScalar: 1.40,
    maxPressureBar: 210,
    description: 'Xtreme-DI 40% flow upgrade',
  ),
  xdi75(
    id: 10,
    name: 'xdi75',
    label: 'XDI-75 (Race Spec)',
    flowScalar: 1.75,
    maxPressureBar: 250,
    description: 'Xtreme-DI 75% flow upgrade',
  ),
  nostrumStage1(
    id: 11,
    name: 'nostrumStage1',
    label: 'Nostrum Energy Stage 1',
    flowScalar: 1.36,
    maxPressureBar: 200,
    description: 'Nostrum HPFP 36% volumetric increase',
  ),
  nostrumStage2(
    id: 12,
    name: 'nostrumStage2',
    label: 'Nostrum Energy Stage 2',
    flowScalar: 1.65,
    maxPressureBar: 240,
    description: 'Nostrum HPFP 65% volumetric increase',
  ),
  nostrumStage3(
    id: 13,
    name: 'nostrumStage3',
    label: 'Nostrum Energy Stage 3',
    flowScalar: 1.95,
    maxPressureBar: 250,
    description: 'Nostrum HPFP 95% volumetric increase',
  ),
  precisionRaceworks(
    id: 14,
    name: 'precisionRaceworks',
    label: 'Precision Raceworks HPFP',
    flowScalar: 1.80,
    maxPressureBar: 250,
    description: 'Precision Raceworks high flow fuel pump system',
  );

  final int id;
  final String name;
  final String label;
  final double flowScalar;
  final int maxPressureBar;
  final String description;

  const HpfpProfile({
    required this.id,
    required this.name,
    required this.label,
    required this.flowScalar,
    required this.maxPressureBar,
    required this.description,
  });

  /// Binary calibration representation:
  /// Byte 0: Profile ID
  /// Byte 1-2: Flow Scalar * 1000 (16-bit big-endian, e.g. 1.68 -> 1680 -> 0x0690)
  /// Byte 3-4: Max Pressure Bar (16-bit big-endian, e.g. 250 -> 0x00FA)
  List<int> toCalibrationBytes() {
    final scalarInt = (flowScalar * 1000).toInt().clamp(500, 3000);
    final pressureInt = maxPressureBar.clamp(150, 350);
    return [
      id & 0xFF,
      (scalarInt >> 8) & 0xFF,
      scalarInt & 0xFF,
      (pressureInt >> 8) & 0xFF,
      pressureInt & 0xFF,
    ];
  }
}

/// TMAP Sensor Scaling Maps (Manifold and Pre-Throttle Chargepipe)
/// Used for linear voltage-to-pressure calibration transfer function:
/// Pressure(kPa) = (Voltage(V) - 0.5V) * Gradient + Offset + 20 kPa
enum TmapSensorType {
  oem2_5Bar(
    id: 0,
    name: 'oem2_5Bar',
    label: 'OEM 2.5 Bar Sensor',
    maxBar: 2.5,
    gradientKpaPerVolt: 57.5,
    offsetKpa: -8.75,
    description: 'Stock factory TMAP sensor (up to ~21.5 PSI gauge pressure)',
  ),
  n20_3_5Bar(
    id: 1,
    name: 'n20_3_5Bar',
    label: 'BMW N20 3.5 Bar (13627843531)',
    maxBar: 3.5,
    gradientKpaPerVolt: 82.5,
    offsetKpa: -21.25,
    description: 'Standard N55 upgrade sensor (up to ~36 PSI boost reading)',
  ),
  custom4_0Bar(
    id: 2,
    name: 'custom4_0Bar',
    label: 'Aftermarket 4.0 Bar Sensor',
    maxBar: 4.0,
    gradientKpaPerVolt: 95.0,
    offsetKpa: -27.5,
    description: 'High boost sensor for single turbo builds (up to 43.5 PSI)',
  ),
  custom5_0Bar(
    id: 3,
    name: 'custom5_0Bar',
    label: 'Aftermarket 5.0 Bar Sensor',
    maxBar: 5.0,
    gradientKpaPerVolt: 120.0,
    offsetKpa: -40.0,
    description: 'Extreme race application (up to 58 PSI boost reading)',
  );

  final int id;
  final String name;
  final String label;
  final double maxBar;
  final double gradientKpaPerVolt;
  final double offsetKpa;
  final String description;

  const TmapSensorType({
    required this.id,
    required this.name,
    required this.label,
    required this.maxBar,
    required this.gradientKpaPerVolt,
    required this.offsetKpa,
    required this.description,
  });

  /// Binary calibration bytes:
  /// Byte 0: Sensor ID
  /// Byte 1-2: Gradient * 10 (16-bit big endian)
  /// Byte 3-4: Offset * 10 (signed 16-bit big endian)
  List<int> toCalibrationBytes() {
    final gradInt = (gradientKpaPerVolt * 10).toInt();
    final offsetInt = (offsetKpa * 10).toInt();
    return [
      id & 0xFF,
      (gradInt >> 8) & 0xFF,
      gradInt & 0xFF,
      (offsetInt >> 8) & 0xFF,
      offsetInt & 0xFF,
    ];
  }
}

/// Rolling Anti-Lag (RAL) Configuration
class RollingAntiLagConfig {
  bool enabled;
  double boostTargetPsi; // 10.0 to 20.0 PSI
  double maxDurationSeconds; // 1.0 to 5.0s
  double ignitionRetardDeg; // -20.0° to -10.0° ATDC

  RollingAntiLagConfig({
    this.enabled = true,
    this.boostTargetPsi = 15.0,
    this.maxDurationSeconds = 3.0,
    this.ignitionRetardDeg = -15.0,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'boostTargetPsi': boostTargetPsi,
    'maxDurationSeconds': maxDurationSeconds,
    'ignitionRetardDeg': ignitionRetardDeg,
  };

  factory RollingAntiLagConfig.fromJson(Map<String, dynamic> json) => RollingAntiLagConfig(
    enabled: json['enabled'] as bool? ?? true,
    boostTargetPsi: (json['boostTargetPsi'] as num?)?.toDouble() ?? 15.0,
    maxDurationSeconds: (json['maxDurationSeconds'] as num?)?.toDouble() ?? 3.0,
    ignitionRetardDeg: (json['ignitionRetardDeg'] as num?)?.toDouble() ?? -15.0,
  );

  /// 4-byte DME Custom ROM DID 0xD420 payload:
  /// Byte 0: Enable flag (0x01 / 0x00)
  /// Byte 1: Boost Target PSI * 10 (e.g. 15.0 PSI -> 150 -> 0x96)
  /// Byte 2: Max Duration (100ms units, e.g. 3.0s -> 30 -> 0x1E)
  /// Byte 3: Ignition Retard absolute magnitude * 10 (e.g. 15.0° -> 150 -> 0x96)
  List<int> toBytes() {
    final boostInt = (boostTargetPsi.clamp(10.0, 20.0) * 10).toInt();
    final durationInt = (maxDurationSeconds.clamp(1.0, 5.0) * 10).toInt();
    final retardInt = (ignitionRetardDeg.abs().clamp(10.0, 20.0) * 10).toInt();
    return [
      enabled ? 0x01 : 0x00,
      boostInt & 0xFF,
      durationInt & 0xFF,
      retardInt & 0xFF,
    ];
  }
}

/// Boost By Gear Configuration (Gears 1 to 8)
class BoostByGearConfig {
  bool enabled;
  List<double> gearLimitsPsi; // 8 gear limits

  BoostByGearConfig({
    this.enabled = true,
    List<double>? gearLimitsPsi,
  }) : gearLimitsPsi = gearLimitsPsi ?? [14.0, 16.5, 19.0, 22.0, 24.0, 24.0, 24.0, 24.0];

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'gearLimitsPsi': gearLimitsPsi,
  };

  factory BoostByGearConfig.fromJson(Map<String, dynamic> json) => BoostByGearConfig(
    enabled: json['enabled'] as bool? ?? true,
    gearLimitsPsi: (json['gearLimitsPsi'] as List?)?.map((e) => (e as num).toDouble()).toList() ??
        [14.0, 16.5, 19.0, 22.0, 24.0, 24.0, 24.0, 24.0],
  );

  /// 9-byte DME Custom ROM DID 0xD430 payload:
  /// Byte 0: Enabled (0x01 / 0x00)
  /// Bytes 1..8: Gear 1 to 8 limit in 0.5 PSI units (e.g. 14.0 PSI -> 28 -> 0x1C)
  List<int> toBytes() {
    final bytes = <int>[enabled ? 0x01 : 0x00];
    for (int i = 0; i < 8; i++) {
      final psi = (i < gearLimitsPsi.length ? gearLimitsPsi[i] : 24.0).clamp(5.0, 35.0);
      bytes.add((psi * 2).toInt() & 0xFF);
    }
    return bytes;
  }
}

/// Torque By Gear Configuration (Gears 1 to 8)
class TorqueByGearConfig {
  bool enabled;
  List<int> gearLimitsNm; // 8 gear limits in Nm

  TorqueByGearConfig({
    this.enabled = true,
    List<int>? gearLimitsNm,
  }) : gearLimitsNm = gearLimitsNm ?? [450, 520, 620, 750, 800, 800, 800, 800];

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'gearLimitsNm': gearLimitsNm,
  };

  factory TorqueByGearConfig.fromJson(Map<String, dynamic> json) => TorqueByGearConfig(
    enabled: json['enabled'] as bool? ?? true,
    gearLimitsNm: (json['gearLimitsNm'] as List?)?.map((e) => (e as num).toInt()).toList() ??
        [450, 520, 620, 750, 800, 800, 800, 800],
  );

  /// 17-byte DME Custom ROM DID 0xD431 payload:
  /// Byte 0: Enabled (0x01 / 0x00)
  /// Bytes 1..16: 8 x 16-bit big endian integers (Nm limits)
  List<int> toBytes() {
    final bytes = <int>[enabled ? 0x01 : 0x00];
    for (int i = 0; i < 8; i++) {
      final nm = (i < gearLimitsNm.length ? gearLimitsNm[i] : 800).clamp(200, 1200);
      bytes.add((nm >> 8) & 0xFF);
      bytes.add(nm & 0xFF);
    }
    return bytes;
  }
}

/// Transmission Upshift "Shift Brap" (ZF 8HP / M-DCT spark cut & exhaust pop)
class ShiftBrapConfig {
  bool enabled;
  int aggressiveness; // 1 = Subtle, 2 = Medium, 3 = Aggressive
  int durationMs; // 50 to 250 ms

  ShiftBrapConfig({
    this.enabled = true,
    this.aggressiveness = 2,
    this.durationMs = 120,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'aggressiveness': aggressiveness,
    'durationMs': durationMs,
  };

  factory ShiftBrapConfig.fromJson(Map<String, dynamic> json) => ShiftBrapConfig(
    enabled: json['enabled'] as bool? ?? true,
    aggressiveness: json['aggressiveness'] as int? ?? 2,
    durationMs: json['durationMs'] as int? ?? 120,
  );

  /// 4-byte DME Custom ROM DID 0xD460 payload:
  /// Byte 0: Enabled (0x01 / 0x00)
  /// Byte 1: Aggressiveness (1..3)
  /// Byte 2-3: Duration in ms (16-bit big endian, e.g. 120 ms -> 0x0078)
  List<int> toBytes() {
    final dur = durationMs.clamp(50, 250);
    return [
      enabled ? 0x01 : 0x00,
      aggressiveness.clamp(1, 3),
      (dur >> 8) & 0xFF,
      dur & 0xFF,
    ];
  }
}

/// GTS Startup Roar / Start Bark
class GtsStartupRoarConfig {
  bool enabled;
  int durationMs; // 300 to 1500 ms
  int flareRpmTarget; // 1200 to 2200 RPM

  GtsStartupRoarConfig({
    this.enabled = true,
    this.durationMs = 750,
    this.flareRpmTarget = 1800,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'durationMs': durationMs,
    'flareRpmTarget': flareRpmTarget,
  };

  factory GtsStartupRoarConfig.fromJson(Map<String, dynamic> json) => GtsStartupRoarConfig(
    enabled: json['enabled'] as bool? ?? true,
    durationMs: json['durationMs'] as int? ?? 750,
    flareRpmTarget: json['flareRpmTarget'] as int? ?? 1800,
  );

  /// 5-byte DME Custom ROM DID 0xD450 payload:
  /// Byte 0: Enabled
  /// Byte 1-2: Duration in ms (16-bit big-endian)
  /// Byte 3-4: Flare RPM target (16-bit big-endian)
  List<int> toBytes() {
    final dur = durationMs.clamp(300, 1500);
    final rpm = flareRpmTarget.clamp(1200, 2500);
    return [
      enabled ? 0x01 : 0x00,
      (dur >> 8) & 0xFF,
      dur & 0xFF,
      (rpm >> 8) & 0xFF,
      rpm & 0xFF,
    ];
  }
}

/// Knock CEL Alert Notification
class KnockCelConfig {
  bool enabled;
  double timingThresholdDeg; // e.g. 3.0° retard threshold
  int flashRateHz; // 2 to 8 Hz

  KnockCelConfig({
    this.enabled = true,
    this.timingThresholdDeg = 3.0,
    this.flashRateHz = 4,
  });

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'timingThresholdDeg': timingThresholdDeg,
    'flashRateHz': flashRateHz,
  };

  factory KnockCelConfig.fromJson(Map<String, dynamic> json) => KnockCelConfig(
    enabled: json['enabled'] as bool? ?? true,
    timingThresholdDeg: (json['timingThresholdDeg'] as num?)?.toDouble() ?? 3.0,
    flashRateHz: json['flashRateHz'] as int? ?? 4,
  );

  /// 4-byte DME Custom ROM DID 0xD465 payload:
  /// Byte 0: Enabled
  /// Byte 1-2: Timing retard threshold in tenths of degree (e.g. 3.0° -> 30 -> 0x001E)
  /// Byte 3: Flash rate in Hz (e.g. 4 Hz -> 0x04)
  List<int> toBytes() {
    final thresh = (timingThresholdDeg.clamp(1.0, 8.0) * 10).toInt();
    return [
      enabled ? 0x01 : 0x00,
      (thresh >> 8) & 0xFF,
      thresh & 0xFF,
      flashRateHz.clamp(2, 8),
    ];
  }
}

/// Catless Downpipe CEL Suppression (DME Error Suppression Mask)
class CatlessDtcSuppressionConfig {
  bool enabled;
  List<String> suppressedCodes;
  int suppressionMaskBitfield; // 32-bit mask

  CatlessDtcSuppressionConfig({
    this.enabled = true,
    List<String>? suppressedCodes,
    this.suppressionMaskBitfield = 0x0000001F,
  }) : suppressedCodes = suppressedCodes ?? const ['180001', '12B104', '180002', 'P0420', 'P0430'];

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'suppressedCodes': suppressedCodes,
    'suppressionMaskBitfield': suppressionMaskBitfield,
  };

  factory CatlessDtcSuppressionConfig.fromJson(Map<String, dynamic> json) => CatlessDtcSuppressionConfig(
    enabled: json['enabled'] as bool? ?? true,
    suppressedCodes: (json['suppressedCodes'] as List?)?.map((e) => e.toString()).toList() ??
        const ['180001', '12B104', '180002', 'P0420', 'P0430'],
    suppressionMaskBitfield: json['suppressionMaskBitfield'] as int? ?? 0x0000001F,
  );

  /// 5-byte DME Custom ROM DID 0xD470 payload:
  /// Byte 0: Enabled
  /// Bytes 1..4: 32-bit big-endian error suppression mask
  List<int> toBytes() {
    final mask = enabled ? suppressionMaskBitfield : 0x00000000;
    return [
      enabled ? 0x01 : 0x00,
      (mask >> 24) & 0xFF,
      (mask >> 16) & 0xFF,
      (mask >> 8) & 0xFF,
      mask & 0xFF,
    ];
  }
}

/// TCU Shift Speed Profiles for ZF 8HP / 6HP
enum TcuShiftSpeed {
  comfort('Comfort', 'Smooth factory shifting with reduced clutch wear'),
  sport('Sport', 'Faster, crisper gear changes for spirited driving'),
  race('Race', 'Maximum line pressure speed for track use'),
  dragRace('Drag Race', 'Aggressive pre-fill, instant clutch engagement for 1/4 mile');

  final String label;
  final String description;

  const TcuShiftSpeed(this.label, this.description);
}

/// xHP TCU Transmission Tuning Configuration for ZF 8HP / 6HP Transmissions
/// (Reverse-engineered from xHP Flashtool com.rbttuning.xhpflashtool.apk)
class XhpTcuOptions {
  final bool linePressureBump; // 19 Bar clutch clamping pressure for 800+ Nm high-torque builds (ic_line_pressure_bump)
  final bool customLaunchControlEnabled; // Custom launch control program (ic_custom_launch_control)
  final int launchRpm; // 2000 - 4500 RPM, default 3200 (ic_launch_rpm)
  final double launchBoostPsi; // 0.0 - 20.0 PSI, default 10.0
  final int torquePunch; // 1 - 5 level, upshift clamp sharpness (ic_torque_punch)
  final bool kickdownManualDisabled; // Inhibits kickdown in M mode to prevent unwanted downshifts (ic_kickdown_launch)
  final bool takeOffIn2ndGear; // Launch in 2nd gear in D/M to maximize traction (ic_take_off_in_2nd_gear)
  final bool trueManualMode; // Prevents auto-upshifting at rev limiter in M mode (ic_true_manual)
  final int throttleBlipAggressiveness; // 80% to 150%, rev-matching downshift blips (ic_throttle_blips)
  final bool gearDisplayKombi; // Enables D1..D8 and S1..S8 indication on instrument cluster (ic_gear_display)
  final int maxShiftRpm; // 6000 to 7500 RPM, matching raised engine rev limits (ic_max_rpm)
  final bool torqueLimitsPerGearRemoved; // Removes internal TCU torque limiters on 1st-8th gears (ic_torque_limits_per_gear)
  final bool standstillDecouplingDisabled; // Disables clutch drag decoupling at red lights for instant response (ic_standstill_decoupling)
  final bool transmissionWarmupDisabled; // Disables cold transmission warmup program that holds gears high (ic_disable_warm_up)
  final TcuShiftSpeed shiftSpeed; // Shift speed profiles

  const XhpTcuOptions({
    this.linePressureBump = false,
    this.customLaunchControlEnabled = false,
    this.launchRpm = 3200,
    this.launchBoostPsi = 10.0,
    this.torquePunch = 3,
    this.kickdownManualDisabled = false,
    this.takeOffIn2ndGear = false,
    this.trueManualMode = false,
    this.throttleBlipAggressiveness = 100,
    this.gearDisplayKombi = true,
    this.maxShiftRpm = 7000,
    this.torqueLimitsPerGearRemoved = false,
    this.standstillDecouplingDisabled = false,
    this.transmissionWarmupDisabled = false,
    this.shiftSpeed = TcuShiftSpeed.sport,
  });

  XhpTcuOptions copyWith({
    bool? linePressureBump,
    bool? customLaunchControlEnabled,
    int? launchRpm,
    double? launchBoostPsi,
    int? torquePunch,
    bool? kickdownManualDisabled,
    bool? takeOffIn2ndGear,
    bool? trueManualMode,
    int? throttleBlipAggressiveness,
    bool? gearDisplayKombi,
    int? maxShiftRpm,
    bool? torqueLimitsPerGearRemoved,
    bool? standstillDecouplingDisabled,
    bool? transmissionWarmupDisabled,
    TcuShiftSpeed? shiftSpeed,
  }) {
    return XhpTcuOptions(
      linePressureBump: linePressureBump ?? this.linePressureBump,
      customLaunchControlEnabled: customLaunchControlEnabled ?? this.customLaunchControlEnabled,
      launchRpm: launchRpm ?? this.launchRpm,
      launchBoostPsi: launchBoostPsi ?? this.launchBoostPsi,
      torquePunch: torquePunch ?? this.torquePunch,
      kickdownManualDisabled: kickdownManualDisabled ?? this.kickdownManualDisabled,
      takeOffIn2ndGear: takeOffIn2ndGear ?? this.takeOffIn2ndGear,
      trueManualMode: trueManualMode ?? this.trueManualMode,
      throttleBlipAggressiveness: throttleBlipAggressiveness ?? this.throttleBlipAggressiveness,
      gearDisplayKombi: gearDisplayKombi ?? this.gearDisplayKombi,
      maxShiftRpm: maxShiftRpm ?? this.maxShiftRpm,
      torqueLimitsPerGearRemoved: torqueLimitsPerGearRemoved ?? this.torqueLimitsPerGearRemoved,
      standstillDecouplingDisabled: standstillDecouplingDisabled ?? this.standstillDecouplingDisabled,
      transmissionWarmupDisabled: transmissionWarmupDisabled ?? this.transmissionWarmupDisabled,
      shiftSpeed: shiftSpeed ?? this.shiftSpeed,
    );
  }

  Map<String, dynamic> toJson() => {
    'linePressureBump': linePressureBump,
    'customLaunchControlEnabled': customLaunchControlEnabled,
    'launchRpm': launchRpm,
    'launchBoostPsi': launchBoostPsi,
    'torquePunch': torquePunch,
    'kickdownManualDisabled': kickdownManualDisabled,
    'takeOffIn2ndGear': takeOffIn2ndGear,
    'trueManualMode': trueManualMode,
    'throttleBlipAggressiveness': throttleBlipAggressiveness,
    'gearDisplayKombi': gearDisplayKombi,
    'maxShiftRpm': maxShiftRpm,
    'torqueLimitsPerGearRemoved': torqueLimitsPerGearRemoved,
    'standstillDecouplingDisabled': standstillDecouplingDisabled,
    'transmissionWarmupDisabled': transmissionWarmupDisabled,
    'shiftSpeed': shiftSpeed.name,
  };

  factory XhpTcuOptions.fromJson(Map<String, dynamic> json) => XhpTcuOptions(
    linePressureBump: json['linePressureBump'] as bool? ?? false,
    customLaunchControlEnabled: json['customLaunchControlEnabled'] as bool? ?? false,
    launchRpm: json['launchRpm'] as int? ?? 3200,
    launchBoostPsi: (json['launchBoostPsi'] as num?)?.toDouble() ?? 10.0,
    torquePunch: json['torquePunch'] as int? ?? 3,
    kickdownManualDisabled: json['kickdownManualDisabled'] as bool? ?? false,
    takeOffIn2ndGear: json['takeOffIn2ndGear'] as bool? ?? false,
    trueManualMode: json['trueManualMode'] as bool? ?? false,
    throttleBlipAggressiveness: json['throttleBlipAggressiveness'] as int? ?? 100,
    gearDisplayKombi: json['gearDisplayKombi'] as bool? ?? true,
    maxShiftRpm: json['maxShiftRpm'] as int? ?? 7000,
    torqueLimitsPerGearRemoved: json['torqueLimitsPerGearRemoved'] as bool? ?? false,
    standstillDecouplingDisabled: json['standstillDecouplingDisabled'] as bool? ?? false,
    transmissionWarmupDisabled: json['transmissionWarmupDisabled'] as bool? ?? false,
    shiftSpeed: TcuShiftSpeed.values.firstWhere(
      (e) => e.name == json['shiftSpeed'],
      orElse: () => TcuShiftSpeed.sport,
    ),
  );

  /// 16-byte TCU Calibration payload for UDS DID 0xD440 on EGS ECU (0x18)
  /// Byte 0: Bitfield 1 (Features & Interlocks)
  ///   - Bit 0: Line Pressure Bump (19 Bar)
  ///   - Bit 1: Custom Launch Control Enable
  ///   - Bit 2: Kickdown Manual Lockout
  ///   - Bit 3: Take-Off in 2nd Gear
  ///   - Bit 4: True Manual Rev-Limiter Hold
  ///   - Bit 5: Kombi Gear Display (D1..D8 / S1..S8)
  ///   - Bit 6: Torque Limits Per Gear Removed
  ///   - Bit 7: Standstill Decoupling Disabled
  /// Byte 1: Bitfield 2 & Shift Speed & Torque Punch
  ///   - Bit 0: Transmission Cold Warmup Bypass
  ///   - Bits 1..3: Shift Speed Profile Index (0: Comfort, 1: Sport, 2: Race, 3: DragRace)
  ///   - Bits 4..7: Torque Punch Level (1 to 5)
  /// Bytes 2-3: Launch RPM Target (16-bit big-endian unsigned, 2000 - 4500 RPM)
  /// Byte 4: Launch Boost Target PSI * 10 (8-bit, 0 - 200 for 0.0 - 20.0 PSI)
  /// Byte 5: Throttle Blip Aggressiveness (8-bit, 80% to 150%)
  /// Bytes 6-7: Max Shift RPM (16-bit big-endian unsigned, 6000 - 7500 RPM)
  /// Bytes 8-15: 8 Reserved / Padding Bytes [0x00 * 8]
  List<int> toBytes() {
    int b0 = 0;
    if (linePressureBump) b0 |= 0x01;
    if (customLaunchControlEnabled) b0 |= 0x02;
    if (kickdownManualDisabled) b0 |= 0x04;
    if (takeOffIn2ndGear) b0 |= 0x08;
    if (trueManualMode) b0 |= 0x10;
    if (gearDisplayKombi) b0 |= 0x20;
    if (torqueLimitsPerGearRemoved) b0 |= 0x40;
    if (standstillDecouplingDisabled) b0 |= 0x80;

    int b1 = 0;
    if (transmissionWarmupDisabled) b1 |= 0x01;
    b1 |= (shiftSpeed.index & 0x07) << 1;
    b1 |= (torquePunch.clamp(1, 5) & 0x0F) << 4;

    final clampedLaunchRpm = launchRpm.clamp(2000, 4500);
    final b2 = (clampedLaunchRpm >> 8) & 0xFF;
    final b3 = clampedLaunchRpm & 0xFF;

    final b4 = (launchBoostPsi.clamp(0.0, 20.0) * 10).round() & 0xFF;
    final b5 = throttleBlipAggressiveness.clamp(80, 150) & 0xFF;

    final clampedMaxShiftRpm = maxShiftRpm.clamp(6000, 7500);
    final b6 = (clampedMaxShiftRpm >> 8) & 0xFF;
    final b7 = clampedMaxShiftRpm & 0xFF;

    return [
      b0,
      b1,
      b2,
      b3,
      b4,
      b5,
      b6,
      b7,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
      0x00,
    ];
  }

  factory XhpTcuOptions.fromBytes(List<int> bytes) {
    if (bytes.length < 16) {
      throw ArgumentError('XhpTcuOptions requires at least 16 bytes, received ${bytes.length}');
    }

    final b0 = bytes[0];
    final b1 = bytes[1];

    final linePressure = (b0 & 0x01) != 0;
    final launchCtrl = (b0 & 0x02) != 0;
    final kickdownLock = (b0 & 0x04) != 0;
    final takeOff2nd = (b0 & 0x08) != 0;
    final trueManual = (b0 & 0x10) != 0;
    final kombiDisplay = (b0 & 0x20) != 0;
    final noTorqueLimits = (b0 & 0x40) != 0;
    final noStandstillDecouple = (b0 & 0x80) != 0;

    final noWarmup = (b1 & 0x01) != 0;
    final speedIdx = (b1 >> 1) & 0x07;
    final shiftSpeed = (speedIdx >= 0 && speedIdx < TcuShiftSpeed.values.length)
        ? TcuShiftSpeed.values[speedIdx]
        : TcuShiftSpeed.sport;
    final punch = ((b1 >> 4) & 0x0F).clamp(1, 5);

    final launchRpmVal = ((bytes[2] << 8) | bytes[3]).clamp(2000, 4500);
    final launchBoostVal = (bytes[4] / 10.0).clamp(0.0, 20.0);
    final blipVal = bytes[5].clamp(80, 150);
    final maxRpmVal = ((bytes[6] << 8) | bytes[7]).clamp(6000, 7500);

    return XhpTcuOptions(
      linePressureBump: linePressure,
      customLaunchControlEnabled: launchCtrl,
      launchRpm: launchRpmVal,
      launchBoostPsi: launchBoostVal,
      torquePunch: punch,
      kickdownManualDisabled: kickdownLock,
      takeOffIn2ndGear: takeOff2nd,
      trueManualMode: trueManual,
      throttleBlipAggressiveness: blipVal,
      gearDisplayKombi: kombiDisplay,
      maxShiftRpm: maxRpmVal,
      torqueLimitsPerGearRemoved: noTorqueLimits,
      standstillDecouplingDisabled: noStandstillDecouple,
      transmissionWarmupDisabled: noWarmup,
      shiftSpeed: shiftSpeed,
    );
  }
}

/// Complete BMW DME Flash Tuning Configuration (matching MHD / BM3 Flasher options)
class BmwFlashOptions {
  OtsMapStage stage;
  CoolingTargetMode coolingMode;
  BurbleAggressiveness burbleAggressiveness;
  double burbleDurationSeconds; // 0.0 to 2.5s
  double sportBurbleDurationSeconds; // 0.0 to 2.5s
  bool coldStartDisabled; // Deactivates noisy cold start cat heating
  bool vmaxDisabled; // Removes 250 km/h limiter (set to 330 km/h)
  bool linearThrottle; // 1:1 pedal to torque mapping
  int idleRpmTarget; // 650 - 950 RPM
  bool exhaustFlapOpenInSport; // Forces exhaust valve open in Sport mode

  // Advanced BM3 & MHD Custom ROM Features
  RollingAntiLagConfig antiLag;
  BoostByGearConfig boostByGear;
  TorqueByGearConfig torqueByGear;
  HpfpProfile hpfp;
  TmapSensorType manifoldTMAP;
  TmapSensorType preThrottleTMAPSensor;
  GtsStartupRoarConfig gtsStartupRoar;
  bool wastegateRattleFix; // PWG offset enabled
  int wastegateDutyCycleOffsetPercent; // -20% to +20%
  ShiftBrapConfig shiftBrap;
  KnockCelConfig knockCel;
  CatlessDtcSuppressionConfig catlessSuppression;

  // Multimap Configuration (Bootmod3 & MHD Custom ROM)
  bool multimapEnabled;
  int activeSlot; // 1..4
  OtsMapStage slot1Stage;
  OtsMapStage slot2Stage;
  OtsMapStage slot3Stage;
  String slot4Description;

  // FlexFuel CAN & Sensor Options
  bool flexFuelEnabled;
  FlexFuelSensorType flexFuelSensorType;
  double maxEthanolBoostScalar; // 1.0 to 1.5 (default 1.35)
  double maxEthanolTimingAdvance; // 0.0 to 8.0 deg (default 5.5)

  // Anti-Theft Kill Switch & Custom Steering Wheel PIN
  bool antiTheftEnabled;
  List<int> antiTheftPin; // 4 digits, validated against weak pins

  /// Validates an anti-theft steering wheel PIN (must be 4 digits, not 1234, not all identical).
  static bool isValidPin(List<int>? pin) {
    if (pin == null || pin.length != 4) return false;
    if (pin.any((d) => d < 0 || d > 9)) return false;
    // Disallow sequential 1,2,3,4
    if (pin[0] == 1 && pin[1] == 2 && pin[2] == 3 && pin[3] == 4) return false;
    // Disallow all identical digits e.g. 0000, 1111, 2222
    if (pin[0] == pin[1] && pin[1] == pin[2] && pin[2] == pin[3]) return false;
    return true;
  }

  // xHP ZF 8HP / 6HP TCU Transmission Tuning Options
  XhpTcuOptions tcuOptions;

  // Backward compatibility getters & setters
  bool get aftermarketDownpipe => catlessSuppression.enabled;
  set aftermarketDownpipe(bool val) => catlessSuppression.enabled = val;

  bool get shiftBrapEnabled => shiftBrap.enabled;
  set shiftBrapEnabled(bool val) => shiftBrap.enabled = val;

  bool get knockCelNotification => knockCel.enabled;
  set knockCelNotification(bool val) => knockCel.enabled = val;

  BmwFlashOptions({
    this.stage = OtsMapStage.stage1_93,
    this.coolingMode = CoolingTargetMode.sport,
    this.burbleAggressiveness = BurbleAggressiveness.medium,
    this.burbleDurationSeconds = 1.0,
    this.sportBurbleDurationSeconds = 1.5,
    bool aftermarketDownpipe = false,
    this.coldStartDisabled = true,
    this.vmaxDisabled = true,
    this.linearThrottle = false,
    this.idleRpmTarget = 650,
    this.exhaustFlapOpenInSport = true,
    bool knockCelNotification = true,
    bool shiftBrapEnabled = false,
    this.wastegateRattleFix = false,
    this.wastegateDutyCycleOffsetPercent = -10,
    RollingAntiLagConfig? antiLag,
    BoostByGearConfig? boostByGear,
    TorqueByGearConfig? torqueByGear,
    this.hpfp = HpfpProfile.oem,
    this.manifoldTMAP = TmapSensorType.oem2_5Bar,
    this.preThrottleTMAPSensor = TmapSensorType.oem2_5Bar,
    GtsStartupRoarConfig? gtsStartupRoar,
    ShiftBrapConfig? shiftBrap,
    KnockCelConfig? knockCel,
    CatlessDtcSuppressionConfig? catlessSuppression,
    this.multimapEnabled = true,
    this.activeSlot = 1,
    this.slot1Stage = OtsMapStage.stage1_91,
    this.slot2Stage = OtsMapStage.stage1_93,
    this.slot3Stage = OtsMapStage.stage2plus_e30,
    this.slot4Description = 'Anti-Theft / Valet (30 km/h / 2500 RPM limit)',
    this.flexFuelEnabled = true,
    this.flexFuelSensorType = FlexFuelSensorType.canBus0x4F0,
    this.maxEthanolBoostScalar = 1.35,
    this.maxEthanolTimingAdvance = 5.5,
    this.antiTheftEnabled = false,
    List<int>? antiTheftPin,
    XhpTcuOptions? tcuOptions,
  })  : antiLag = antiLag ?? RollingAntiLagConfig(),
        boostByGear = boostByGear ?? BoostByGearConfig(),
        torqueByGear = torqueByGear ?? TorqueByGearConfig(),
        gtsStartupRoar = gtsStartupRoar ?? GtsStartupRoarConfig(),
        shiftBrap = shiftBrap ?? ShiftBrapConfig(enabled: shiftBrapEnabled),
        knockCel = knockCel ?? KnockCelConfig(enabled: knockCelNotification),
        catlessSuppression = catlessSuppression ?? CatlessDtcSuppressionConfig(enabled: aftermarketDownpipe),
        antiTheftPin = antiTheftPin ?? const [],
        tcuOptions = tcuOptions ?? const XhpTcuOptions();

  BmwFlashOptions copyWith({
    OtsMapStage? stage,
    CoolingTargetMode? coolingMode,
    BurbleAggressiveness? burbleAggressiveness,
    double? burbleDurationSeconds,
    double? sportBurbleDurationSeconds,
    bool? coldStartDisabled,
    bool? vmaxDisabled,
    bool? linearThrottle,
    int? idleRpmTarget,
    bool? exhaustFlapOpenInSport,
    RollingAntiLagConfig? antiLag,
    BoostByGearConfig? boostByGear,
    TorqueByGearConfig? torqueByGear,
    HpfpProfile? hpfp,
    TmapSensorType? manifoldTMAP,
    TmapSensorType? preThrottleTMAPSensor,
    GtsStartupRoarConfig? gtsStartupRoar,
    bool? wastegateRattleFix,
    int? wastegateDutyCycleOffsetPercent,
    ShiftBrapConfig? shiftBrap,
    KnockCelConfig? knockCel,
    CatlessDtcSuppressionConfig? catlessSuppression,
    bool? multimapEnabled,
    int? activeSlot,
    OtsMapStage? slot1Stage,
    OtsMapStage? slot2Stage,
    OtsMapStage? slot3Stage,
    String? slot4Description,
    bool? flexFuelEnabled,
    FlexFuelSensorType? flexFuelSensorType,
    double? maxEthanolBoostScalar,
    double? maxEthanolTimingAdvance,
    bool? antiTheftEnabled,
    List<int>? antiTheftPin,
    XhpTcuOptions? tcuOptions,
  }) {
    return BmwFlashOptions(
      stage: stage ?? this.stage,
      coolingMode: coolingMode ?? this.coolingMode,
      burbleAggressiveness: burbleAggressiveness ?? this.burbleAggressiveness,
      burbleDurationSeconds: burbleDurationSeconds ?? this.burbleDurationSeconds,
      sportBurbleDurationSeconds: sportBurbleDurationSeconds ?? this.sportBurbleDurationSeconds,
      coldStartDisabled: coldStartDisabled ?? this.coldStartDisabled,
      vmaxDisabled: vmaxDisabled ?? this.vmaxDisabled,
      linearThrottle: linearThrottle ?? this.linearThrottle,
      idleRpmTarget: idleRpmTarget ?? this.idleRpmTarget,
      exhaustFlapOpenInSport: exhaustFlapOpenInSport ?? this.exhaustFlapOpenInSport,
      antiLag: antiLag ?? this.antiLag,
      boostByGear: boostByGear ?? this.boostByGear,
      torqueByGear: torqueByGear ?? this.torqueByGear,
      hpfp: hpfp ?? this.hpfp,
      manifoldTMAP: manifoldTMAP ?? this.manifoldTMAP,
      preThrottleTMAPSensor: preThrottleTMAPSensor ?? this.preThrottleTMAPSensor,
      gtsStartupRoar: gtsStartupRoar ?? this.gtsStartupRoar,
      wastegateRattleFix: wastegateRattleFix ?? this.wastegateRattleFix,
      wastegateDutyCycleOffsetPercent: wastegateDutyCycleOffsetPercent ?? this.wastegateDutyCycleOffsetPercent,
      shiftBrap: shiftBrap ?? this.shiftBrap,
      knockCel: knockCel ?? this.knockCel,
      catlessSuppression: catlessSuppression ?? this.catlessSuppression,
      multimapEnabled: multimapEnabled ?? this.multimapEnabled,
      activeSlot: activeSlot ?? this.activeSlot,
      slot1Stage: slot1Stage ?? this.slot1Stage,
      slot2Stage: slot2Stage ?? this.slot2Stage,
      slot3Stage: slot3Stage ?? this.slot3Stage,
      slot4Description: slot4Description ?? this.slot4Description,
      flexFuelEnabled: flexFuelEnabled ?? this.flexFuelEnabled,
      flexFuelSensorType: flexFuelSensorType ?? this.flexFuelSensorType,
      maxEthanolBoostScalar: maxEthanolBoostScalar ?? this.maxEthanolBoostScalar,
      maxEthanolTimingAdvance: maxEthanolTimingAdvance ?? this.maxEthanolTimingAdvance,
      antiTheftEnabled: antiTheftEnabled ?? this.antiTheftEnabled,
      antiTheftPin: antiTheftPin ?? this.antiTheftPin,
      tcuOptions: tcuOptions ?? this.tcuOptions,
    );
  }

  Map<String, dynamic> toJson() => {
    'stage': stage.name,
    'coolingMode': coolingMode.name,
    'burbleAggressiveness': burbleAggressiveness.name,
    'burbleDurationSeconds': burbleDurationSeconds,
    'sportBurbleDurationSeconds': sportBurbleDurationSeconds,
    'aftermarketDownpipe': aftermarketDownpipe,
    'coldStartDisabled': coldStartDisabled,
    'vmaxDisabled': vmaxDisabled,
    'linearThrottle': linearThrottle,
    'idleRpmTarget': idleRpmTarget,
    'exhaustFlapOpenInSport': exhaustFlapOpenInSport,
    'knockCelNotification': knockCelNotification,
    'shiftBrapEnabled': shiftBrapEnabled,
    'wastegateRattleFix': wastegateRattleFix,
    'wastegateDutyCycleOffsetPercent': wastegateDutyCycleOffsetPercent,
    'antiLag': antiLag.toJson(),
    'boostByGear': boostByGear.toJson(),
    'torqueByGear': torqueByGear.toJson(),
    'hpfp': hpfp.name,
    'manifoldTMAP': manifoldTMAP.name,
    'preThrottleTMAPSensor': preThrottleTMAPSensor.name,
    'gtsStartupRoar': gtsStartupRoar.toJson(),
    'shiftBrap': shiftBrap.toJson(),
    'knockCel': knockCel.toJson(),
    'catlessSuppression': catlessSuppression.toJson(),
    'multimapEnabled': multimapEnabled,
    'activeSlot': activeSlot,
    'slot1Stage': slot1Stage.name,
    'slot2Stage': slot2Stage.name,
    'slot3Stage': slot3Stage.name,
    'slot4Description': slot4Description,
    'flexFuelEnabled': flexFuelEnabled,
    'flexFuelSensorType': flexFuelSensorType.name,
    'maxEthanolBoostScalar': maxEthanolBoostScalar,
    'maxEthanolTimingAdvance': maxEthanolTimingAdvance,
    'antiTheftEnabled': antiTheftEnabled,
    'antiTheftPin': antiTheftPin,
    'tcuOptions': tcuOptions.toJson(),
  };

  factory BmwFlashOptions.fromJson(Map<String, dynamic> json) {
    return BmwFlashOptions(
      stage: OtsMapStage.values.firstWhere(
        (e) => e.name == json['stage'],
        orElse: () => OtsMapStage.stage1_93,
      ),
      coolingMode: CoolingTargetMode.values.firstWhere(
        (e) => e.name == json['coolingMode'],
        orElse: () => CoolingTargetMode.sport,
      ),
      burbleAggressiveness: BurbleAggressiveness.values.firstWhere(
        (e) => e.name == json['burbleAggressiveness'],
        orElse: () => BurbleAggressiveness.medium,
      ),
      burbleDurationSeconds: (json['burbleDurationSeconds'] as num?)?.toDouble() ?? 1.0,
      sportBurbleDurationSeconds: (json['sportBurbleDurationSeconds'] as num?)?.toDouble() ?? 1.5,
      aftermarketDownpipe: json['aftermarketDownpipe'] as bool? ?? false,
      coldStartDisabled: json['coldStartDisabled'] as bool? ?? true,
      vmaxDisabled: json['vmaxDisabled'] as bool? ?? true,
      linearThrottle: json['linearThrottle'] as bool? ?? false,
      idleRpmTarget: json['idleRpmTarget'] as int? ?? 650,
      exhaustFlapOpenInSport: json['exhaustFlapOpenInSport'] as bool? ?? true,
      knockCelNotification: json['knockCelNotification'] as bool? ?? true,
      shiftBrapEnabled: json['shiftBrapEnabled'] as bool? ?? false,
      wastegateRattleFix: json['wastegateRattleFix'] as bool? ?? false,
      wastegateDutyCycleOffsetPercent: json['wastegateDutyCycleOffsetPercent'] as int? ?? -10,
      antiLag: json['antiLag'] != null
          ? RollingAntiLagConfig.fromJson(json['antiLag'] as Map<String, dynamic>)
          : null,
      boostByGear: json['boostByGear'] != null
          ? BoostByGearConfig.fromJson(json['boostByGear'] as Map<String, dynamic>)
          : null,
      torqueByGear: json['torqueByGear'] != null
          ? TorqueByGearConfig.fromJson(json['torqueByGear'] as Map<String, dynamic>)
          : null,
      hpfp: HpfpProfile.values.firstWhere(
        (e) => e.name == json['hpfp'],
        orElse: () => HpfpProfile.oem,
      ),
      manifoldTMAP: TmapSensorType.values.firstWhere(
        (e) => e.name == json['manifoldTMAP'],
        orElse: () => TmapSensorType.oem2_5Bar,
      ),
      preThrottleTMAPSensor: TmapSensorType.values.firstWhere(
        (e) => e.name == json['preThrottleTMAPSensor'],
        orElse: () => TmapSensorType.oem2_5Bar,
      ),
      gtsStartupRoar: json['gtsStartupRoar'] != null
          ? GtsStartupRoarConfig.fromJson(json['gtsStartupRoar'] as Map<String, dynamic>)
          : null,
      shiftBrap: json['shiftBrap'] != null
          ? ShiftBrapConfig.fromJson(json['shiftBrap'] as Map<String, dynamic>)
          : null,
      knockCel: json['knockCel'] != null
          ? KnockCelConfig.fromJson(json['knockCel'] as Map<String, dynamic>)
          : null,
      catlessSuppression: json['catlessSuppression'] != null
          ? CatlessDtcSuppressionConfig.fromJson(json['catlessSuppression'] as Map<String, dynamic>)
          : null,
      multimapEnabled: json['multimapEnabled'] as bool? ?? true,
      activeSlot: json['activeSlot'] as int? ?? 1,
      slot1Stage: OtsMapStage.values.firstWhere(
        (e) => e.name == json['slot1Stage'],
        orElse: () => OtsMapStage.stage1_91,
      ),
      slot2Stage: OtsMapStage.values.firstWhere(
        (e) => e.name == json['slot2Stage'],
        orElse: () => OtsMapStage.stage1_93,
      ),
      slot3Stage: OtsMapStage.values.firstWhere(
        (e) => e.name == json['slot3Stage'],
        orElse: () => OtsMapStage.stage2plus_e30,
      ),
      slot4Description: json['slot4Description'] as String? ?? 'Anti-Theft / Valet (30 km/h / 2500 RPM limit)',
      flexFuelEnabled: json['flexFuelEnabled'] as bool? ?? true,
      flexFuelSensorType: FlexFuelSensorType.values.firstWhere(
        (e) => e.name == json['flexFuelSensorType'],
        orElse: () => FlexFuelSensorType.canBus0x4F0,
      ),
      maxEthanolBoostScalar: (json['maxEthanolBoostScalar'] as num?)?.toDouble() ?? 1.35,
      maxEthanolTimingAdvance: (json['maxEthanolTimingAdvance'] as num?)?.toDouble() ?? 5.5,
      antiTheftEnabled: json['antiTheftEnabled'] as bool? ?? false,
      antiTheftPin: (json['antiTheftPin'] as List?)?.map((e) => e as int).toList() ?? const [],
      tcuOptions: json['tcuOptions'] != null
          ? XhpTcuOptions.fromJson(json['tcuOptions'] as Map<String, dynamic>)
          : null,
    );
  }

  /// Generates the complete binary calibration vector for Custom ROM table injection
  Uint8List serializeCustomRomBinaryTable() {
    final builder = BytesBuilder();

    // Magic Header 'FXAI\x01\x00\x00\x00' (8 bytes)
    builder.add([0x46, 0x58, 0x41, 0x49, 0x01, 0x00, 0x00, 0x00]);

    // 1. Rolling Anti-Lag (4 bytes)
    builder.add(antiLag.toBytes());

    // 2. Boost By Gear (9 bytes)
    builder.add(boostByGear.toBytes());

    // 3. Torque By Gear (17 bytes)
    builder.add(torqueByGear.toBytes());

    // 4. HPFP Calibration (5 bytes)
    builder.add(hpfp.toCalibrationBytes());

    // 5. TMAP Manifold Calibration (5 bytes)
    builder.add(manifoldTMAP.toCalibrationBytes());

    // 6. TMAP Pre-Throttle Calibration (5 bytes)
    builder.add(preThrottleTMAPSensor.toCalibrationBytes());

    // 7. GTS Startup Roar (5 bytes)
    builder.add(gtsStartupRoar.toBytes());

    // 8. Wastegate Rattle Fix (2 bytes)
    builder.add([
      wastegateRattleFix ? 0x01 : 0x00,
      wastegateDutyCycleOffsetPercent & 0xFF,
    ]);

    // 9. Transmission Shift Brap (4 bytes)
    builder.add(shiftBrap.toBytes());

    // 10. Knock CEL Alert (4 bytes)
    builder.add(knockCel.toBytes());

    // 11. Catless Downpipe DTC Suppression Mask (5 bytes)
    builder.add(catlessSuppression.toBytes());

    // 12. Multimap Slot Index (1 byte) & Slot Stages (3 bytes)
    builder.add([
      activeSlot & 0xFF,
      slot1Stage.index & 0xFF,
      slot2Stage.index & 0xFF,
      slot3Stage.index & 0xFF,
    ]);

    // 13. FlexFuel Calibration (5 bytes)
    // Clamped safely between 1.0 and 2.5 scalar, timing 0.0 to 10.0 deg
    final clampedBoostScalar = maxEthanolBoostScalar.clamp(1.0, 2.5);
    final ffBoost = (clampedBoostScalar * 100).toInt() & 0xFF;
    final clampedTiming = maxEthanolTimingAdvance.clamp(0.0, 10.0);
    final ffTiming = (clampedTiming * 10).toInt() & 0xFF;
    builder.add([
      flexFuelEnabled ? 0x01 : 0x00,
      flexFuelSensorType.index & 0xFF,
      ffBoost,
      ffTiming,
      0x00,
    ]);

    // 14. Anti-Theft Status & 4-digit PIN (5 bytes)
    if (antiTheftEnabled && !isValidPin(antiTheftPin)) {
      throw ArgumentError(
        'Anti-Theft is enabled but PIN is invalid. PIN must be 4 digits and cannot be 1-2-3-4 or identical digits.',
      );
    }
    builder.add([
      antiTheftEnabled ? 0x01 : 0x00,
      antiTheftPin.isNotEmpty ? antiTheftPin[0] & 0xFF : 0,
      antiTheftPin.length > 1 ? antiTheftPin[1] & 0xFF : 0,
      antiTheftPin.length > 2 ? antiTheftPin[2] & 0xFF : 0,
      antiTheftPin.length > 3 ? antiTheftPin[3] & 0xFF : 0,
    ]);

    // 15. xHP ZF 8HP / 6HP TCU Options DID 0xD440 (16 bytes)
    builder.add(tcuOptions.toBytes());

    return builder.toBytes();
  }

  /// Direct binary serialization of flash options
  List<int> toBytes() => serializeCustomRomBinaryTable();

  /// Generates the binary table with an appended 4-byte big-endian CRC32 checksum.
  Uint8List serializeWithCrc() {
    final payload = serializeCustomRomBinaryTable();
    final crc = Crc32.compute(payload);
    final builder = BytesBuilder();
    builder.add(payload);
    final crcBytes = ByteData(4)..setUint32(0, crc, Endian.big);
    builder.add(crcBytes.buffer.asUint8List());
    return builder.toBytes();
  }

  /// Verifies the 4-byte big-endian CRC32 checksum at the end of a binary payload.
  static bool verifyCrc(Uint8List dataWithCrc) {
    if (dataWithCrc.length < 4) return false;
    final payload = Uint8List.sublistView(dataWithCrc, 0, dataWithCrc.length - 4);
    final expectedCrc = ByteData.sublistView(
      dataWithCrc,
      dataWithCrc.length - 4,
    ).getUint32(0, Endian.big);
    final actualCrc = Crc32.compute(payload);
    return expectedCrc == actualCrc;
  }

  /// Generates the calibration patch description for the DME/TCU flash payload
  Map<String, dynamic> generatePatchSummary() {
    return {
      'thermostat_target_celsius': coolingMode.targetTempCelsius,
      'burble_overrun_delay_ms': (burbleDurationSeconds * 1000).toInt(),
      'burble_sport_delay_ms': (sportBurbleDurationSeconds * 1000).toInt(),
      'burble_timing_retard_deg': burbleAggressiveness.level * -6.0,
      'cat_heating_disabled': coldStartDisabled,
      'speed_limiter_kmh': vmaxDisabled ? 330 : 250,
      'throttle_linear_enabled': linearThrottle,
      'target_idle_rpm': idleRpmTarget,
      'rolling_antilag_enabled': antiLag.enabled,
      'rolling_antilag_target_psi': antiLag.boostTargetPsi,
      'rolling_antilag_retard_deg': antiLag.ignitionRetardDeg,
      'boost_by_gear_enabled': boostByGear.enabled,
      'boost_by_gear_limits': boostByGear.gearLimitsPsi,
      'torque_by_gear_enabled': torqueByGear.enabled,
      'torque_by_gear_limits_nm': torqueByGear.gearLimitsNm,
      'hpfp_profile': hpfp.label,
      'hpfp_flow_scalar': hpfp.flowScalar,
      'hpfp_max_bar': hpfp.maxPressureBar,
      'manifold_tmap_sensor': manifoldTMAP.label,
      'pre_throttle_tmap_sensor': preThrottleTMAPSensor.label,
      'gts_startup_roar_enabled': gtsStartupRoar.enabled,
      'gts_startup_roar_duration_ms': gtsStartupRoar.durationMs,
      'wastegate_rattle_fix_enabled': wastegateRattleFix,
      'wastegate_pwm_offset_percent': wastegateDutyCycleOffsetPercent,
      'shift_brap_enabled': shiftBrap.enabled,
      'shift_brap_duration_ms': shiftBrap.durationMs,
      'knock_cel_enabled': knockCel.enabled,
      'knock_cel_threshold_deg': knockCel.timingThresholdDeg,
      'catless_downpipe_suppression': catlessSuppression.enabled,
      'catless_suppressed_dtcs': catlessSuppression.suppressedCodes,
      'multimap_enabled': multimapEnabled,
      'active_multimap_slot': activeSlot,
      'multimap_slot1': slot1Stage.name,
      'multimap_slot2': slot2Stage.name,
      'multimap_slot3': slot3Stage.name,
      'multimap_slot4': slot4Description,
      'flexfuel_enabled': flexFuelEnabled,
      'flexfuel_sensor_protocol': flexFuelSensorType.name,
      'flexfuel_max_boost_scalar': maxEthanolBoostScalar,
      'flexfuel_max_timing_deg': maxEthanolTimingAdvance,
      'antitheft_hook_enabled': antiTheftEnabled,
      'antitheft_pin': antiTheftPin.join(''),
      'tcu_line_pressure_bump': tcuOptions.linePressureBump,
      'tcu_custom_launch_control': tcuOptions.customLaunchControlEnabled,
      'tcu_launch_rpm': tcuOptions.launchRpm,
      'tcu_launch_boost_psi': tcuOptions.launchBoostPsi,
      'tcu_torque_punch': tcuOptions.torquePunch,
      'tcu_kickdown_lockout_manual': tcuOptions.kickdownManualDisabled,
      'tcu_take_off_2nd_gear': tcuOptions.takeOffIn2ndGear,
      'tcu_true_manual_mode': tcuOptions.trueManualMode,
      'tcu_throttle_blip_percent': tcuOptions.throttleBlipAggressiveness,
      'tcu_kombi_gear_display': tcuOptions.gearDisplayKombi,
      'tcu_max_shift_rpm': tcuOptions.maxShiftRpm,
      'tcu_torque_limits_removed': tcuOptions.torqueLimitsPerGearRemoved,
      'tcu_standstill_decoupling_disabled': tcuOptions.standstillDecouplingDisabled,
      'tcu_warmup_disabled': tcuOptions.transmissionWarmupDisabled,
      'tcu_shift_speed': tcuOptions.shiftSpeed.label,
    };
  }
}

/// Standard IEEE 802.3 CRC32 checksum calculator
class Crc32 {
  static final List<int> _table = List<int>.generate(256, (i) {
    int c = i;
    for (int k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
    }
    return c;
  });

  /// Computes the 32-bit CRC checksum for [data].
  static int compute(List<int> data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc = (crc >>> 8) ^ _table[(crc ^ byte) & 0xFF];
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

