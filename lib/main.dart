import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'core/config/env_config.dart';
import 'core/services/cellular_routing_service.dart';
import 'data/supabase_client.dart';
import 'data/local_cache_service.dart';
import 'data/backend_sync_processor.dart';
import 'data/offline_vehicle_pack_service.dart';
import 'core/services/app_lifecycle_manager.dart';
import 'core/services/connectivity_service.dart';
import 'core/navigation/app_nav_keys.dart';
import 'core/services/ai/offline_model_manager.dart';
import 'core/services/ai/local_llama_service.dart';
import 'modules/chat/services/ai_coding_safety_registration.dart';
import 'modules/chat/screens/chat_screen.dart';
import 'modules/auth/screens/sign_in_screen.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'core/services/admob_service_native.dart'
    if (dart.library.html) 'core/services/admob_service_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

Future<void> sendTelegramNotification(String message) async {
  final botToken = EnvConfig.telegramBotToken;
  final chatId = EnvConfig.telegramChatId;

  if (botToken.isEmpty || chatId.isEmpty) {
    debugPrint('Telegram Bot not configured. Set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in .env.');
    return;
  }
  
    final url = Uri.parse('https://api.telegram.org/bot$botToken/sendMessage');
    try {
      final response = await CellularHttpClient().post(
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
    if (!kIsWeb) {
      // Firebase needs platform-specific config (google-services.json on
      // Android). Web would require a firebase_options.dart with Web keys
      // which we don't have yet — skip Firebase entirely on Web.
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('Got a message whilst in the foreground!');
      });
    } else {
      debugPrint('Firebase skipped on Web (no Web config).');
    }
  } on FirebaseException catch (e) {
    debugPrint('Firebase initialization warning (e.g. missing google-services.json): $e');
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  try {
    // Initialize AdMob (no-op on Web via the conditional import).
    if (!kIsWeb) {
      await AdMobService.initialize();
    }
  } catch (e) {
    debugPrint('AdMob initialization block failed: $e');
  }

  try {
    // Initialize Environment and Backend Services
    await EnvConfig.load();
    // 2.1/2.3 FIX: secure init (key generation + encrypted boxes) now lives
    // entirely inside LocalCacheService. The cipher is cached on the singleton
    // and reused on every lazy reopen, preventing silent encryption-loss.
    await LocalCacheService().initSecure();
    await SupabaseClientManager().initialize();
    AppLifecycleManager().initialize();

    // 6.24 FIX (offline-first): pre-load BMW Group pack (DTC + coding + protocol seed).
    OfflineVehiclePackService().ensureLoaded().catchError((Object e) {
      debugPrint('OfflineVehiclePack init failed (non-fatal): $e');
    });

    await ConnectivityService.instance.start();
    ConnectivityService.instance.registerOnReconnect(() async {
      await OfflineVehiclePackService().syncPack(forceRefresh: true);
    });
    if (ConnectivityService.instance.isOnline) {
      OfflineVehiclePackService()
          .syncPack(forceRefresh: true)
          .catchError((Object e) {
        debugPrint('OfflineVehiclePack launch refresh failed (non-fatal): $e');
        return OfflinePackSyncResult(
          dtcCount: 0,
          codingCount: 0,
          cafdCount: 0,
          seedPackVersion: 0,
          dtcFromNetwork: false,
          codingFromNetwork: false,
          syncedAt: DateTime.now(),
        );
      });
    }

    final themeController = ThemeController();
    await themeController.initialize();

    registerAiCodingSafetyUi();
    runApp(AiCarApp(themeController: themeController));

    if (!kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        OfflineModelManager.instance.ensureModel().catchError((Object e) {
          debugPrint('OfflineModelManager ensureModel failed (non-fatal): $e');
          return null;
        });
        LocalLlamaService.instance.restoreSavedModel().catchError((Object e) {
          debugPrint('LocalLlamaService restore failed (non-fatal): $e');
        });
      });
    }

    // BUG-08 FIX: Use addPostFrameCallback instead of Future.microtask so
    // background sync runs only AFTER the first frame is fully rendered,
    // avoiding any potential startup jank on the main isolate.
    //
    // C1 FIX (audit): the previous version unconditionally called
    // processRawForumData() with a HARDCODED dummy "BMW X4 / N55 timing
    // chain" string on EVERY cold start. That polluted the saved_insights
    // table (the very table GeminiDiagnosticService reads back as chronic
    // issues) with fake data once per launch, and fired a Telegram report
    // every time the app opened. The injection is now gated behind a
    // compile-time flag (RUN_DEBUG_SYNC=true) so production launches only
    // sync REAL verified cases — they never fabricate forum text.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        debugPrint('--- [START] Background Sync Pipelines ---');
        final processor = BackendSyncProcessor();

        const runDebugSync =
            bool.fromEnvironment('RUN_DEBUG_SYNC', defaultValue: false);
        if (runDebugSync) {
          // Dev/debug only: ingest a sample dump so the digestion pipeline can
          // be exercised end-to-end without touching real user content.
          final dummyText =
              "Man, my BMW X4 is having serious issues. The dealer just told "
              "me the N55 engine has a stretched timing chain at only 60k "
              "miles!";
          await processor.processRawForumData(dummyText, 'BMW', 'X4');
        }

        // Always: sync REAL verified cases against the insights table. This
        // is the only production-safe ingestion path.
        final syncResult = await processor.syncUserFeedbackWithInsights();

        final telegramMessage = '''
<b>[DriveSense AI Sync Report]</b>

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

class AiCarApp extends StatefulWidget {
  final ThemeController themeController;
  
  const AiCarApp({Key? key, required this.themeController}) : super(key: key);

  @override
  State<AiCarApp> createState() => _AiCarAppState();
}

class _AiCarAppState extends State<AiCarApp> {
  @override
  void initState() {
    super.initState();
    // 1.1 FIX: This listener is now SIDE-EFFECT ONLY (cache clear + snackbar).
    // All routing is handled declaratively by the StreamBuilder in build().
    // The previous imperative pushAndRemoveUntil fought the StreamBuilder and
    // could strand the user when navigatorKey.currentState was null (1.2).
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      if (event == AuthChangeEvent.tokenRefreshed) {
        debugPrint('Supabase Token Refreshed successfully.');
      } else if (event == AuthChangeEvent.signedOut ||
          (event == AuthChangeEvent.initialSession && data.session == null)) {
        // Clear local caches gracefully
        try {
          if (Hive.isBoxOpen('cached_profile')) Hive.box('cached_profile').clear();
          if (Hive.isBoxOpen('cached_history')) Hive.box('cached_history').clear();
          if (Hive.isBoxOpen('cached_insights')) Hive.box('cached_insights').clear();
        } catch (e) {
          debugPrint('Cache clear skipped: $e');
        }

        if (event == AuthChangeEvent.signedOut) {
          // Defer snackbar to next frame — ScaffoldMessenger may not be mounted yet.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            appScaffoldMessengerKey.currentState?.showSnackBar(
              const SnackBar(content: Text("Your session has expired. Please sign in again.")),
            );
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.themeController,
      builder: (context, _) {
        return MaterialApp(
          navigatorKey: appNavigatorKey,
          scaffoldMessengerKey: appScaffoldMessengerKey,
          title: 'AiCar Diagnostic',
          debugShowCheckedModeBanner: false,
          themeMode: widget.themeController.themeMode,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
        // BUG-12 FIX: Do NOT pass initialData to StreamBuilder.
        // Passing a cached `initialSession` can cause the UI to render
        // ChatScreen before Supabase has validated the token server-side.
        // Instead, use a loading state until the first real auth event fires.
        home: StreamBuilder<AuthState>(
          stream: Supabase.instance.client.auth.onAuthStateChange,
          builder: (context, snapshot) {
            // 1.3 FIX: Only treat ConnectionState.waiting (pre-first-event)
            // as loading. initialSession WITH a valid session is a real,
            // authoritative routing target — not a perpetual loader state.
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                backgroundColor: Color(0xFF121212),
                body: Center(
                  child: CircularProgressIndicator(color: Colors.blueAccent),
                ),
              );
            }

            final session = snapshot.data?.session;

            if (session != null) {
              // User is authenticated — StreamBuilder is the sole router.
              return const ChatScreen(
                carProfile: {
                  'brand': 'Unknown',
                  'make': 'Unknown',
                  'model': 'Unknown',
                  'year': '',
                  'mileage': '',
                  'id': 'session-profile',
                },
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
