/// Central BMW UDS Data Identifiers (DIDs) and Routine Identifiers (RIDs).
///
/// Constants marked with [TODO(verify-on-ecu)] indicate diagnostic identifiers
/// that must be validated on physical engine benches (HIL) or vehicle ECUs across
/// specific BMW chassis families (F2x/F3x, F8x, G2x/G8x).
class BmwUdsIds {
  const BmwUdsIds._();

  // ==========================================
  // ISO 14229 / Standard BMW Identification DIDs
  // ==========================================

  /// Standard VIN (17 ASCII characters) - ISO 14229 standard
  static const int didVin = 0xF190;

  /// Active Diagnostic Session Data Identifier (ISO 14229 standard)
  static const int didActiveDiagnosticSession = 0xF186;

  /// System Supplier ECU Hardware Version (ISO 14229)
  static const int didEcuHardwareVersion = 0xF191;

  /// System Supplier ECU Software Version (ISO 14229)
  static const int didEcuSoftwareVersion = 0xF194;

  /// System Supplier ECU Software Number / SVK
  /// // TODO(verify-on-ecu): verify BMW SVK format and table structure on MEVD17 / MG1
  static const int didEcuSvk = 0xF101;

  /// ECU Supply Voltage (KL30) - high-precision millivolts
  /// // TODO(verify-on-ecu): verify 0x5815 scaling on MEVD172G vs MG1CS003
  static const int didKl30SupplyVoltage = 0x5815;

  /// Alternative ECU Supply Voltage (KL30)
  /// // TODO(verify-on-ecu): verify 0xF111 availability on legacy DME/DDE
  static const int didKl30SupplyVoltageAlt = 0xF111;

  // ==========================================
  // Engine Telemetry & Live Sensor DIDs
  // ==========================================

  /// Engine Speed (RPM)
  /// // TODO(verify-on-ecu): verify 0x2000 factor (0.25 rpm/bit) on MEVD17
  static const int didEngineRpm = 0x2000;

  /// Alternative Engine Speed DID
  /// // TODO(verify-on-ecu): verify 0x5800 factor on B58 / S58
  static const int didEngineRpmAlt = 0x5800;

  /// Vehicle Speed (km/h)
  /// // TODO(verify-on-ecu): verify 0x580D scaling factor on DSC / DME
  static const int didVehicleSpeed = 0x580D;

  /// Boost Pressure Absolute / Relative
  /// // TODO(verify-on-ecu): verify 0x2005 pressure offset and sensor scale
  static const int didBoostPressure = 0x2005;

  /// Ignition Timing Advance
  /// // TODO(verify-on-ecu): verify 0x2008 signed retard/advance degrees
  static const int didIgnitionTiming = 0x2008;

  /// Lambda / AFR
  /// // TODO(verify-on-ecu): verify 0x2009 wideband scaling factor
  static const int didLambdaAfr = 0x2009;

  /// Short-Term Fuel Trim (STFT)
  /// // TODO(verify-on-ecu): verify 0x200A percentage scaling
  static const int didFuelTrimStft = 0x200A;

  /// Long-Term Fuel Trim (LTFT)
  /// // TODO(verify-on-ecu): verify 0x200B percentage scaling
  static const int didFuelTrimLtft = 0x200B;

  /// Engine Coolant Temperature
  /// // TODO(verify-on-ecu): verify 0x2001 -40C offset on N55 / B58
  static const int didCoolantTemp = 0x2001;

  /// Engine Oil Temperature
  /// // TODO(verify-on-ecu): verify 0x2002 -40C offset on N55 / B58
  static const int didOilTemp = 0x2002;

  /// Intake Air Temperature (IAT)
  /// // TODO(verify-on-ecu): verify 0x2003 -40C offset
  static const int didIntakeAirTemp = 0x2003;

  /// High Pressure Fuel Pump (HPFP) Actual Rail Pressure
  /// // TODO(verify-on-ecu): verify 0x2006 bar pressure scaling
  static const int didHpfpRailPressure = 0x2006;

  /// Knock Sensor Retard per Cylinder
  /// // TODO(verify-on-ecu): verify 0x2015 individual cylinder retard mapping
  static const int didKnockRetard = 0x2015;

  // ==========================================
  // Custom ROM & Patch Identifiers (Bootmod3 / MHD / FixAI)
  // ==========================================

  /// Custom ROM Signature / Bootloader Status
  /// // TODO(verify-on-ecu): verify 0xD400 Custom ROM signature response on target DME
  static const int didCustomRomStatus = 0xD400;

  /// Active Multimap Slot
  /// // TODO(verify-on-ecu): verify 0xD401 slot selection DID on DME RAM
  static const int didCustomRomActiveSlot = 0xD401;

  /// FlexFuel Live Sensor Payload (CAN 0x4F0 mirror)
  /// // TODO(verify-on-ecu): verify 0xD410 FlexFuel structure (ethanol %, fuel temp, scalar)
  static const int didFlexFuelLive = 0xD410;

  /// Rolling Anti-Lag Configuration
  /// // TODO(verify-on-ecu): verify 0xD420 RAM write structure
  static const int didAntiLagConfig = 0xD420;

  /// Anti-Theft Kill Switch State
  /// // TODO(verify-on-ecu): verify 0xD430 anti-theft PIN lock status
  static const int didAntiTheftState = 0xD430;

  /// xHP Transmission Calibration Parameters
  /// // TODO(verify-on-ecu): verify 0xD440 TCU calibration write structure on ZF 8HP
  static const int didXhpTcuConfig = 0xD440;

  // ==========================================
  // Routine Identifiers (RIDs - Service 0x31)
  // ==========================================

  /// Rolling Anti-Lag Actuation Routine
  /// // TODO(verify-on-ecu): verify Routine 0xD421 start/stop routine control
  static const int ridRollingAntiLag = 0xD421;

  /// Transmission Shift Brap Test Routine
  /// // TODO(verify-on-ecu): verify Routine 0xD461 ignition cut pulse
  static const int ridShiftBrap = 0xD461;

  /// Kombi Knock CEL Flash Routine
  /// // TODO(verify-on-ecu): verify Routine 0xD466 KOMBI cluster alert routine
  static const int ridKnockCelFlash = 0xD466;

  /// Cruise RES Needle Sweep Routine
  /// // TODO(verify-on-ecu): verify Routine 0xD402 tachometer gauge sweep
  static const int ridCruiseResSweep = 0xD402;

  /// Anti-Theft PIN Authentication Routine
  /// // TODO(verify-on-ecu): verify Routine 0xD431 PIN verification routine
  static const int ridAntiTheftAuth = 0xD431;

  /// Brake Bleed Routine (ISTA ABL_DIT_AS3450_ENTL)
  /// // TODO(verify-on-ecu): verify Routine 0xD010 / 0x0322 on DSC MK100 / DSC Premium
  static const int ridBrakeBleed = 0xD010;
  static const int ridBrakeBleedLegacy = 0x0322;

  /// Valvetronic Teach-In Routine (ISTA)
  /// // TODO(verify-on-ecu): verify Routine 0x1005 on DME MEVD172G
  static const int ridValvetronicCalibration = 0x1005;

  /// Active Front Steering (AFS) Center Calibration
  /// // TODO(verify-on-ecu): verify Routine 0xA012 on AFS ECU 0x1B
  static const int ridAfsCalibration = 0xA012;

  /// VTG Transfer Case Clutch Calibration
  /// // TODO(verify-on-ecu): verify Routine 0xA101 on VTG ECU 0x19
  static const int ridVtgCalibration = 0xA101;
}
