import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/config/env_config.dart';

/// A singleton manager for the Supabase client.
class SupabaseClientManager {
  static final SupabaseClientManager _instance = SupabaseClientManager._internal();
  
  factory SupabaseClientManager() {
    return _instance;
  }
  
  SupabaseClientManager._internal();

  late final SupabaseClient _client;
  bool _isInitialized = false;

  /// Returns the configured Supabase client.
  SupabaseClient get client {
    if (!_isInitialized) {
      throw StateError('SupabaseClientManager has not been initialized. Call initialize() first.');
    }
    return _client;
  }

  /// Initializes the Supabase connection safely using environment variables.
  Future<void> initialize() async {
    if (_isInitialized) return;

    await Supabase.initialize(
      url: EnvConfig.supabaseUrl,
      publishableKey: EnvConfig.supabaseAnonKey,
    );
    
    _client = Supabase.instance.client;
    _isInitialized = true;
  }
}
