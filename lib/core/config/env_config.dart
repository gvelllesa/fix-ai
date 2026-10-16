/// Compile-time public configuration injected via `--dart-define`.
///
/// Private API keys (Gemini, Telegram Bot, EU VIN Decoder) are strictly
/// prohibited in the client binary and reside only in Supabase Edge Function
/// secrets.
class EnvConfig {
  const EnvConfig._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static void assertConfigured() {
    if (!isConfigured) {
      throw StateError(
        'Missing --dart-define=SUPABASE_URL / --dart-define=SUPABASE_ANON_KEY',
      );
    }
  }
}
