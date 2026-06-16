import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'data/supabase_client.dart';
import 'data/backend_sync_processor.dart';
import 'modules/chat/screens/chat_screen.dart';
import 'modules/auth/screens/sign_in_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';

Future<void> sendTelegramNotification(String message) async {
  final botToken = EnvConfig.telegramBotToken;
  final chatId = EnvConfig.telegramChatId;

  if (botToken.isEmpty || chatId.isEmpty) {
    debugPrint('Telegram Bot not configured. Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in .env.');
    return;
  }
  
  final url = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');
  try {
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'chat_id': chatId,
        'text': message,
        'parse_mode': 'HTML',
      }),
    );
    if (response.statusCode == 200) {
      debugPrint('Telegram notification sent successfully.');
    } else {
      debugPrint('Failed to send Telegram notification: ${response.body}');
    }
  } catch (e) {
    debugPrint('Error sending Telegram notification: $e');
  }
}

void main() async {
  // უსაფრთხოების ფენები
  WidgetsFlutterBinding.ensureInitialized();

  try {
    // Initialize Environment and Backend Services
    await EnvConfig.load();
    await SupabaseClientManager().initialize();

    final themeController = ThemeController();
    await themeController.initialize();

    runApp(AiCarApp(themeController: themeController));

    // Fire-and-forget: run background sync AFTER the UI is rendered
    Future.microtask(() async {
      try {
        debugPrint('--- [START] Background Sync Pipelines ---');
        final processor = BackendSyncProcessor();

        final dummyText = "Man, my BMW X4 is having serious issues. The dealer just told me the N55 engine has a stretched timing chain at only 60k miles!";
        final processResult = await processor.processRawForumData(dummyText, 'BMW', 'X4');
        final syncResult = await processor.syncUserFeedbackWithInsights();

        final telegramMessage = '''
<b>[DriveSense AI Sync Report]</b>

<b>Forum Scraping Status:</b> ${processResult['status'] ?? 'N/A'}
<b>Inserted Insights:</b> ${processResult['inserted_count'] ?? 0}
${processResult['error'] != null ? '\n<b>Error:</b> ${processResult['error']}' : ''}

<b>Supabase Saved Insights Sync Status:</b> ${syncResult['status'] ?? 'N/A'}
<b>Updated Rows:</b> ${syncResult['updated_count'] ?? 0}
${syncResult['error'] != null ? '\n<b>Error:</b> ${syncResult['error']}' : ''}
''';

        await sendTelegramNotification(telegramMessage);
        debugPrint('--- [END] Background Sync Pipelines ---');
      } catch (e) {
        debugPrint('Background sync failed silently: $e');
      }
    });
  } catch (e, stackTrace) {
    // თუ აქ რამე ქრაშავს, ლოგებში მაინც დავინახავთ ერორს და აპი არ გაითიშება
    print('🔥 კრიტიკული შეცდომა გაშვებისას: $e');
    print(stackTrace);
    
    // Fallback UI რათა აპლიკაციამ უბრალოდ არ დაქრაშოს (შავად/თეთრად არ გამოირთოს)
    runApp(MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'App Initialization Error:\n\n$e\n\n$stackTrace',
              style: const TextStyle(color: Colors.red, fontSize: 12),
              textDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    ));
  }
}

class AiCarApp extends StatelessWidget {
  final ThemeController themeController;
  
  const AiCarApp({Key? key, required this.themeController}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        return MaterialApp(
          title: 'AiCar Diagnostic',
          debugShowCheckedModeBanner: false,
          themeMode: themeController.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
        home: StreamBuilder<AuthState>(
          initialData: AuthState(AuthChangeEvent.initialSession, Supabase.instance.client.auth.currentSession),
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            final session = snapshot.data?.session ?? Supabase.instance.client.auth.currentSession;
            
            if (session != null) {
              // User is authenticated
              return const ChatScreen(
                carProfile: {
                  'brand': 'BMW',
                  'model': 'M3',
                  'year': '2020',
                  'mileage': '35000',
                  'id': 'test-profile-1'
                },
              );
            }
            
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF121212),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                ),
              );
            }
            
            // User is not authenticated
            return const SignInScreen();
          },
        ),
      );
    });
  }
}
