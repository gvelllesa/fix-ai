import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/supabase_client.dart';
import '../../../core/services/notification_service.dart';

/// Controller for managing authentication state and actions.
class AuthController extends ChangeNotifier {
  final SupabaseClient _supabaseClient = SupabaseClientManager().client;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _errorMessage;
  String? get errorMessage => _errorMessage;

  /// Signs up a new user with Supabase Auth
  Future<bool> signUp(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabaseClient.auth.signUp(
        email: email,
        password: password,
      );
      // Initialize notifications and sync token automatically
      await NotificationService().init();
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Signs in an existing user with Supabase Auth
  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // Initialize notifications and sync token automatically
      await NotificationService().init();
      
      _isLoading = false;
      notifyListeners();
      return true;
    } on AuthException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'An unexpected error occurred: $e';
    }

    _isLoading = false;
    notifyListeners();
    return false;
  }

  /// Signs in with Google OAuth via Supabase
  Future<void> signInWithGoogle() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabaseClient.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: kIsWeb ? null : 'io.supabase.fixai://login-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: {
          'client_id': '441114435122-7uko127j5q4rl9rlmjq4728rfdb46tk0.apps.googleusercontent.com',
        },
      );
    } on AuthException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Google sign-in failed: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Signs in with Apple OAuth via Supabase
  Future<void> signInWithApple() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await _supabaseClient.auth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: kIsWeb ? null : 'io.supabase.fixai://login-callback',
      );
    } on AuthException catch (e) {
      _errorMessage = e.message;
    } catch (e) {
      _errorMessage = 'Apple sign-in failed: $e';
    }

    _isLoading = false;
    notifyListeners();
  }
}
