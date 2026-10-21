/// Global compile-time and runtime safety feature flags for FIX AI.
class FeatureFlags {
  const FeatureFlags._();

  /// Controls full DME/DDE/TCU/VTG bootloader flashing & calibration writing.
  /// Enabled by default now that Stages 1-5 (`UNI_Flash` / `EdiabasLib` parity) are verified.
  /// Can still be toggled to `false` at runtime or in tests to enforce read-only lock.
  static bool kFlashEnabled =
      const bool.fromEnvironment('FIXAI_FLASH_ENABLED', defaultValue: true);

  /// Controls FDL/NCD ECU Coding (`0x2E` WriteDataByIdentifier & `0x27` SecurityAccess).
  static bool kCodingEnabled =
      const bool.fromEnvironment('FIXAI_CODING_ENABLED', defaultValue: true);

  /// Gates off-highway / motorsport-only calibration options (e.g. catless DTC
  /// suppression) behind an explicit flag.
  static bool kMotorsportEnabled =
      const bool.fromEnvironment('FIXAI_MOTORSPORT', defaultValue: true);

  /// Gates real-time Gemini Live WebSocket voice calls.
  static bool kLiveVoiceCallEnabled =
      const bool.fromEnvironment('FIXAI_LIVE_VOICE', defaultValue: true);
}
