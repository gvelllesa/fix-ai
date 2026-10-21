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

  /// Returns the configured Supabase client, falling back to a standalone
  /// client instance if [Supabase.initialize] has not completed.
  SupabaseClient get client {
    if (_client != null) return _client!;
    try {
      _client = Supabase.instance.client;
      return _client!;
    } catch (e) {
      debugPrint('[SupabaseClientManager] Creating fallback client: $e');
      _client = SupabaseClient(
        EnvConfig.supabaseUrl,
        EnvConfig.supabaseAnonKey,
      );
      return _client!;
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
      } catch (_) {
        _client = SupabaseClient(
          EnvConfig.supabaseUrl,
          EnvConfig.supabaseAnonKey,
        );
        _isInitialized = true;
      }
    }
  }
}
