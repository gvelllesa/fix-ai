/// Global compile-time and safety feature flags for FIX AI.
class FeatureFlags {
  const FeatureFlags._();

  /// Disables full DME/DDE bootloader flashing until HIL (Hardware-in-the-Loop)
  /// bench validation, verified ODX/PDX containers, and HSM Seed/Key signing
  /// are provisioned on the backend.
  static const bool kFlashEnabled = false;

  /// Gates off-highway / motorsport-only calibration options (e.g. catless DTC
  /// suppression) behind an explicit compile-time flag.
  static const bool kMotorsportEnabled =
      bool.fromEnvironment('FIXAI_MOTORSPORT', defaultValue: false);

  /// Gates real-time Gemini Live WebSocket voice calls until ephemeral session
  /// token exchange is enabled on the backend proxy.
  static const bool kLiveVoiceCallEnabled =
      bool.fromEnvironment('FIXAI_LIVE_VOICE', defaultValue: false);
}
