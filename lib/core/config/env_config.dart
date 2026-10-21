/// Compile-time public configuration injected via `--dart-define`.
///
/// Private API keys (Gemini, Telegram Bot, EU VIN Decoder) are strictly
/// prohibited in the client binary and reside only in Supabase Edge Function
/// secrets.
class EnvConfig {
  const EnvConfig._();

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://pfztaizoqlxfgqyiojdh.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBmemF0YWl6b3FseGZncXlpb2pkaCIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzA0MDY3MjAwLCJleHAiOjIwMTk2NDMyMDB9.dummy_signature',
  );

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
