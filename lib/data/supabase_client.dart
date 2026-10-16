import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env_config.dart';

/// A singleton manager for the Supabase client.
class SupabaseClientManager {
  static final SupabaseClientManager _instance = SupabaseClientManager._internal();
  
  factory SupabaseClientManager() {
    return _instance;
  }
  
  SupabaseClientManager._internal();

  SupabaseClient? _client;
  bool _isInitialized = false;

  /// Returns the configured Supabase client.
  SupabaseClient get client {
    if (_client != null) return _client!;
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('[SupabaseClientManager] Warning: accessing uninitialized client: $e');
      throw StateError('SupabaseClientManager has not been initialized. Call initialize() first.');
    }
  }

  /// Initializes the Supabase connection safely using environment variables.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final url = EnvConfig.supabaseUrl;
      final key = EnvConfig.supabaseAnonKey;
      if (url.isNotEmpty && key.isNotEmpty) {
        await Supabase.initialize(
          url: url,
          publishableKey: key,
        );
        _client = Supabase.instance.client;
        _isInitialized = true;
      }
    } catch (e) {
      debugPrint('[SupabaseClientManager] Supabase.initialize warning: $e');
      try {
        _client = Supabase.instance.client;
        _isInitialized = true;
      } catch (_) {}
    }
  }
}
