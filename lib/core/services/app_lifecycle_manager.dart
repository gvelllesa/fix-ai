import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Signature for app-lifecycle callbacks.
typedef LifecycleCallback = Future<void> Function();

/// App-level lifecycle observer. Register once in main() before runApp.
/// Services call registerOnPause / registerOnResume to receive lifecycle
/// events regardless of which screen is currently mounted.
///
/// 3.6 FIX: previously only _ChatScreenState observed AppLifecycleState,
/// so hardware/telemetry streams on other routes (VoiceCallScreen, dialogs)
/// were never suspended on background. This singleton closes that gap.
///
/// H1 FIX (audit): registerOnPause/registerOnResume now return a deregister
/// function. Callers that are NOT singletons (e.g. ObdDataProcessor, which is
/// constructed fresh per ChatController) MUST invoke the returned handle in
/// their dispose(), otherwise every new owner leaks a closure into the
/// singleton's list and the dead owner is retained for app lifetime.
class AppLifecycleManager with WidgetsBindingObserver {
  static final AppLifecycleManager _instance = AppLifecycleManager._internal();
  factory AppLifecycleManager() => _instance;
  AppLifecycleManager._internal();

  final List<LifecycleCallback> _pauseCallbacks = [];
  final List<LifecycleCallback> _resumeCallbacks = [];
  bool _initialized = false;

  /// Call once from main() before runApp().
  void initialize() {
    if (_initialized) return;
    _initialized = true;
    WidgetsBinding.instance.addObserver(this);
  }

  /// Register a callback to fire when the app is paused or goes inactive.
  ///
  /// Returns a [VoidCallback] that unregisters it. Non-singleton owners must
  /// call the returned function in their dispose() to avoid a leak.
  VoidCallback registerOnPause(LifecycleCallback callback) {
    _pauseCallbacks.add(callback);
    return () => _pauseCallbacks.remove(callback);
  }

  /// Register a callback to fire when the app resumes.
  ///
  /// Returns a [VoidCallback] that unregisters it. See [registerOnPause].
  VoidCallback registerOnResume(LifecycleCallback callback) {
    _resumeCallbacks.add(callback);
    return () => _resumeCallbacks.remove(callback);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      for (final cb in List<LifecycleCallback>.from(_pauseCallbacks)) {
        cb().catchError((Object e) {
          debugPrint('Lifecycle pause callback error: $e');
        });
      }
    } else if (state == AppLifecycleState.resumed) {
      for (final cb in List<LifecycleCallback>.from(_resumeCallbacks)) {
        cb().catchError((Object e) {
          debugPrint('Lifecycle resume callback error: $e');
        });
      }
    }
  }
}
