import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../data/supabase_client.dart';

/// Top-level background message handler for FCM
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Ensure Firebase is initialized before handling background messages
  await Firebase.initializeApp();
  debugPrint("FCM Background Message Received: \${message.messageId}");
  // Here we could trigger local Hive updates or Predictive Alerts
}

/// Centralized service for managing Push Notifications and FCM Tokens
class NotificationService {
  // Singleton Pattern
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final SupabaseClient _supabaseClient = SupabaseClientManager().client;
  bool _isInitialized = false;

  /// Initializes Firebase Cloud Messaging and sets up listeners.
  /// Gracefully fails if native Google Services are not configured.
  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // 1. Initialize Firebase
      await Firebase.initializeApp();
      
      // 2. Request Notification Permissions from OS
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: true,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized || 
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('Notification permissions granted: \${settings.authorizationStatus}');
        
        // 3. Setup Listeners
        FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
        
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('FCM Foreground Message Received: \${message.notification?.title}');
          // Note: Flutter local notifications could be triggered here for high-fidelity native alerts
        });

        // 4. Fetch and Sync Device Token
        await _fetchAndSyncToken();
        
        _isInitialized = true;
      } else {
        debugPrint('Notification permissions declined by user.');
      }
    } catch (e) {
      debugPrint('Warning: Firebase Messaging initialization failed. Ensure google-services.json/GoogleService-Info.plist is configured properly. Error: \$e');
    }
  }

  /// Extracts the FCM Device Token and syncs it with the Supabase `users` table.
  Future<void> _fetchAndSyncToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) {
        debugPrint('Failed to retrieve FCM Token.');
        return;
      }

      debugPrint('FCM Token Extracted successfully.');

      final userId = _supabaseClient.auth.currentUser?.id;
      if (userId != null) {
        await syncTokenWithSupabase(userId, token);
      }
    } catch (e) {
      debugPrint('Error fetching or syncing FCM Token: \$e');
    }
  }

  /// Synchronizes the provided hardware token with the active user's Supabase profile.
  Future<void> syncTokenWithSupabase(String userId, String token) async {
    try {
      // Updates the 'fcm_token' column. This column must exist in the 'users' table.
      await _supabaseClient.from('users').update({
        'fcm_token': token,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', userId);
      
      debugPrint('Token successfully synced to Supabase for User ID: \$userId');
    } catch (e) {
      debugPrint('Supabase Sync Error (fcm_token): \$e');
    }
  }

  /// Manually retrieves the current FCM token without syncing (useful for diagnostics).
  Future<String?> getDeviceToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('Failed to retrieve device token manually: \$e');
      return null;
    }
  }
}
