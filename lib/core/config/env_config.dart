import 'package:flutter_dotenv/flutter_dotenv.dart';

class EnvConfig {
  static Future<void> load() async {
    await dotenv.load(fileName: ".env");
  }

  static String get supabaseUrl {
    final url = dotenv.env['SUPABASE_URL'];
    if (url == null || url.isEmpty) {
      throw Exception('SUPABASE_URL is missing in .env');
    }
    return url;
  }

  static String get supabaseAnonKey {
    final key = dotenv.env['SUPABASE_ANON_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('SUPABASE_ANON_KEY is missing in .env');
    }
    return key;
  }

  static String get geminiApiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GEMINI_API_KEY is missing in .env');
    }
    return key;
  }

  static String get telegramBotToken {
    return dotenv.env['TELEGRAM_BOT_TOKEN'] ?? '';
  }

  static String get telegramChatId {
    return dotenv.env['TELEGRAM_CHAT_ID'] ?? '';
  }

  static String get euVinApiKey {
    return dotenv.env['EU_VIN_API_KEY'] ?? '';
  }
}
