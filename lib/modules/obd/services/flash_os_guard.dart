import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Guard that prevents operating system interruptions during active ECU programming:
/// - Acquires and maintains CPU and screen wake locks ([WakelockPlus]).
/// - Promotes process to an Android Foreground Service with high-priority notification.
/// - Enforces Immersive Sticky mode to prevent accidental navigation gesture exits.
/// - Monitors AppLifecycleState to detect and log dangerous background transitions.
class FlashOsGuard with WidgetsBindingObserver {
  static final FlashOsGuard instance = FlashOsGuard._internal();

  FlashOsGuard._internal();

  bool _isGuarded = false;
  bool get isGuarded => _isGuarded;

  void Function(AppLifecycleState state)? onLifecycleWarning;

  /// Acquires all OS level locks before flashing starts
  Future<void> acquire({
    String notificationTitle = 'FixAI DME Flashing In Progress',
    String notificationBody = 'DO NOT DISCONNECT ADAPTER OR TURN OFF IGNITION',
  }) async {
    if (_isGuarded) return;
    _isGuarded = true;

    WidgetsBinding.instance.addObserver(this);

    try {
      // 1. Keep screen on and CPU awake
      await WakelockPlus.enable();
    } catch (e) {
      debugPrint('[FlashOsGuard] Wakelock enable error: $e');
    }

    try {
      // 2. Hide system navigation bars to prevent accidental touch gestures
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint('[FlashOsGuard] Immersive UI mode error: $e');
    }

    try {
      // 3. Start foreground task if supported on platform (Android)
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        FlutterForegroundTask.init(
          androidNotificationOptions: AndroidNotificationOptions(
            channelId: 'fixai_flash_channel',
            channelName: 'FixAI ECU Flashing Safety Channel',
            channelDescription: 'Maintains foreground process stability during DME calibration write',
            channelImportance: NotificationChannelImportance.MAX,
            priority: NotificationPriority.MAX,
          ),
          iosNotificationOptions: const IOSNotificationOptions(
            showNotification: true,
            playSound: false,
          ),
          foregroundTaskOptions: ForegroundTaskOptions(
            eventAction: ForegroundTaskEventAction.nothing(),
            autoRunOnBoot: false,
            autoRunOnMyPackageReplaced: false,
            allowWakeLock: true,
            allowWifiLock: true,
          ),
        );

        await FlutterForegroundTask.startService(
          serviceId: 9001,
          notificationTitle: notificationTitle,
          notificationText: notificationBody,
        );
      }
    } catch (e) {
      debugPrint('[FlashOsGuard] Foreground service start error: $e');
    }

    debugPrint('[FlashOsGuard] OS protection acquired: WakeLock + Immersive Mode active.');
  }

  /// Releases all locks and restores normal OS mode after flashing finishes or fails
  Future<void> release() async {
    if (!_isGuarded) return;
    _isGuarded = false;

    WidgetsBinding.instance.removeObserver(this);

    try {
      await WakelockPlus.disable();
    } catch (e) {
      debugPrint('[FlashOsGuard] Wakelock disable error: $e');
    }

    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('[FlashOsGuard] Edge-to-edge UI restore error: $e');
    }

    try {
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('[FlashOsGuard] Foreground service stop error: $e');
    }

    debugPrint('[FlashOsGuard] OS protection released.');
  }

  /// Runs [action] protected by the OS guard, ensuring cleanup in all outcomes
  static Future<T> runProtected<T>(Future<T> Function() action) async {
    await instance.acquire();
    try {
      return await action();
    } finally {
      await instance.release();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isGuarded && (state == AppLifecycleState.paused || state == AppLifecycleState.inactive)) {
      debugPrint('[FlashOsGuard] CRITICAL WARNING: App entered background state ($state) while DME Flash is active!');
      onLifecycleWarning?.call(state);
    }
  }
}
