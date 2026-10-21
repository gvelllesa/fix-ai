import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'data/supabase_client.dart';
import 'modules/chat/screens/chat_screen.dart';
import 'modules/auth/screens/sign_in_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'data/local_cache_service.dart';

/// Sends an operational notification via the server-side `telegram-notify`
/// Supabase Edge Function. Private bot tokens are never stored in the client.
Future<void> sendTelegramNotification(String message) async {
  try {
    final client = SupabaseClientManager().client;
    if (client.auth.currentSession == null) {
      debugPrint('[TelegramNotify] Skipped: no active authenticated session.');
      return;
    }
    final response = await client.functions.invoke(
      'telegram-notify',
      body: {'message': message},
    );
    if (response.status == 200) {
      debugPrint('Telegram notification sent via Edge Function.');
    } else {
      debugPrint('Telegram notification rejected (${response.status}): ${response.data}');
    }
  } catch (e) {
    debugPrint('Error sending Telegram notification via Edge Function: $e');
  }
}

void main() async {
  // უსაფრთხოების ფენები
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Validate compile-time public configuration (non-fatal warning in debug/test)
  if (!EnvConfig.isConfigured) {
    debugPrint(
      '[main] EnvConfig notice: SUPABASE_URL / SUPABASE_ANON_KEY not passed via --dart-define.',
    );
  }

  // 2. Initialize Supabase safely
  try {
    await SupabaseClientManager().initialize();
  } catch (e) {
    debugPrint('[main] Supabase init warning: $e');
  }

  // 3. Initialize Local Cache safely with encrypted storage
  try {
    List<int>? encryptionKey;
    try {
      const secureStorage = FlutterSecureStorage();
      var keyBase64 = await secureStorage.read(key: 'hive_encryption_key');
      if (keyBase64 == null) {
        final newKey = Hive.generateSecureKey();
        await secureStorage.write(
          key: 'hive_encryption_key',
          value: base64UrlEncode(newKey),
        );
        encryptionKey = newKey;
      } else {
        encryptionKey = base64Url.decode(keyBase64);
      }
    } catch (e) {
      debugPrint('[main] FlutterSecureStorage key retrieval notice: $e');
    }
    await LocalCacheService().init(encryptionKey: encryptionKey);
  } catch (e) {
    debugPrint('[main] LocalCache init warning: $e');
  }

  // 4. Initialize Theme Controller safely
  final themeController = ThemeController();
  try {
    await themeController.initialize();
  } catch (e) {
    debugPrint('[main] ThemeController init warning: $e');
  }

  // 5. Launch the primary UI
  try {
    runApp(AiCarApp(themeController: themeController));
  } catch (e, stackTrace) {
    debugPrint('🔥 კრიტიკული შეცდომა გაშვებისას: $e\n$stackTrace');

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

  const AiCarApp({super.key, required this.themeController});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: themeController,
      builder: (context, _) {
        Session? initialSession;
        Stream<AuthState>? authStream;
        try {
          initialSession = Supabase.instance.client.auth.currentSession;
          authStream = Supabase.instance.client.auth.onAuthStateChange;
        } catch (_) {
          initialSession = null;
          authStream = const Stream.empty();
        }

        return MaterialApp(
          title: 'FIX AI',
          debugShowCheckedModeBanner: false,
          themeMode: themeController.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          routes: {
            '/login': (_) => const SignInScreen(),
          },
          home: StreamBuilder<AuthState>(
            initialData: AuthState(AuthChangeEvent.initialSession, initialSession),
            stream: authStream,
            builder: (context, snapshot) {
              Session? session = snapshot.data?.session ?? initialSession;

              if (session != null) {
                return const ChatScreen(
                  carProfile: {
                    'brand': 'BMW',
                    'model': 'M3',
                    'year': '2020',
                    'mileage': '35000',
                    'id': 'test-profile-1',
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

              return const SignInScreen();
            },
          ),
        );
      },
    );
  }
}
