import 'dart:async';
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
  // H2 FIX (audit): '\$messageId' was a literal escaped dollar sign, not
  // interpolation — the actual message id was never logged.
  debugPrint('FCM Background Message Received: ${message.messageId}');
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

  // H2 FIX (audit): hold the foreground subscription so it can be cancelled.
  // Previously it was fire-and-forget and, because _isInitialized was only
  // set inside the authorized branch, a denied-permission retry stacked a
  // second duplicate listener.
  StreamSubscription<RemoteMessage>? _onMessageSub;

  /// Initializes Firebase Cloud Messaging and sets up listeners.
  /// Gracefully fails if native Google Services are not configured.
  Future<void> init() async {
    if (_isInitialized) return;
    // Skip FCM on Web — Firebase Web config isn't set up and would throw.
    if (kIsWeb) {
      _isInitialized = true;
      return;
    }

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

      // H2 FIX (audit): mark initialized unconditionally so a denied-permission
      // retry or a transient failure cannot re-enter and stack another
      // .listen() on top of the previous one.
      _isInitialized = true;

      if (settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint(
            'Notification permissions granted: ${settings.authorizationStatus}');

        // 3. Setup Listeners
        FirebaseMessaging.onBackgroundMessage(
            _firebaseMessagingBackgroundHandler);

        _onMessageSub = FirebaseMessaging.onMessage.listen((RemoteMessage msg) {
          // H2 FIX (audit): real interpolation (was '\$...').
          debugPrint('FCM Foreground Message Received: ${msg.notification?.title}');
          // Note: Flutter local notifications could be triggered here for
          // high-fidelity native alerts
        });

        // 4. Fetch and Sync Device Token
        await _fetchAndSyncToken();
      } else {
        debugPrint('Notification permissions declined by user.');
      }
    } catch (e) {
      // H2 FIX (audit): real interpolation.
      debugPrint(
          'Warning: Firebase Messaging initialization failed. Ensure google-services.json/GoogleService-Info.plist is configured properly. Error: $e');
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
      // H2 FIX (audit): real interpolation (was '\$e').
      debugPrint('Error fetching or syncing FCM Token: $e');
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

      // H2 FIX (audit): real interpolation (was '\$userId').
      debugPrint('Token successfully synced to Supabase for User ID: $userId');
    } catch (e) {
      // H2 FIX (audit): real interpolation (was '\$e').
      debugPrint('Supabase Sync Error (fcm_token): $e');
    }
  }

  /// Manually retrieves the current FCM token without syncing (useful for diagnostics).
  Future<String?> getDeviceToken() async {
    try {
      return await FirebaseMessaging.instance.getToken();
    } catch (e) {
      // H2 FIX (audit): real interpolation (was '\$e').
      debugPrint('Failed to retrieve device token manually: $e');
      return null;
    }
  }

  /// Cancels the foreground FCM subscription. Safe to call multiple times.
  void dispose() {
    // H2 FIX (audit): the foreground listener was never cancellable before.
    _onMessageSub?.cancel();
    _onMessageSub = null;
  }
}
