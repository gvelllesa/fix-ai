import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';

/// Offline Local Cache Engine
/// Transparent fallback layer for critical diagnostic components.
class LocalCacheService {
  // Singleton Pattern
  static final LocalCacheService _instance = LocalCacheService._internal();
  factory LocalCacheService() => _instance;
  LocalCacheService._internal();

  // Box Names
  static const String _profileBoxName = 'cached_profile';
  static const String _historyBoxName = 'cached_history';
  static const String _insightsBoxName = 'cached_insights';

  /// Initializes the Hive database and opens required boxes.
  /// Should be called inside `main.dart` before `runApp()`.
  Future<void> init({List<int>? encryptionKey}) async {
    await Hive.initFlutter();
    
    // Future-proofing for encryption: If an encryption key is provided, use HiveAesCipher.
    // Note: Generating and storing the key securely requires flutter_secure_storage.
    HiveCipher? cipher;
    if (encryptionKey != null && encryptionKey.length == 32) {
      cipher = HiveAesCipher(encryptionKey);
    }

    await Hive.openBox(_profileBoxName, encryptionCipher: cipher);
    await Hive.openBox(_historyBoxName, encryptionCipher: cipher);
    await Hive.openBox(_insightsBoxName, encryptionCipher: cipher);
    
    debugPrint('LocalCacheService initialized successfully.');
  }

  // ==========================================
  // Vehicle Profile Cache
  // ==========================================

  /// Caches a vehicle profile. The unique key is the profile ID.
  Future<void> cacheVehicleProfile(Map<String, dynamic> profile) async {
    try {
      final box = Hive.box(_profileBoxName);
      final id = profile['id']?.toString();
      if (id != null) {
        // Store as JSON string to maintain type safety across Maps
        await box.put(id, jsonEncode(profile));
      }
    } catch (e) {
      debugPrint('Failed to cache vehicle profile: $e');
    }
  }

  /// Retrieves a cached vehicle profile. Returns null if not found.
  Future<Map<String, dynamic>?> getCachedVehicleProfile(String carProfileId) async {
    try {
      final box = Hive.box(_profileBoxName);
      final dataStr = box.get(carProfileId);
      if (dataStr != null) {
        return jsonDecode(dataStr as String) as Map<String, dynamic>;
      }
    } catch (e) {
      debugPrint('Failed to get cached vehicle profile: $e');
    }
    return null;
  }

  // ==========================================
  // Chronic Insights Cache
  // ==========================================

  /// Caches the list of chronic insights for a specific car model.
  Future<void> cacheChronicInsights(String carModel, List<Map<String, dynamic>> insights) async {
    try {
      final box = Hive.box(_insightsBoxName);
      // Keyed by the model name in lowercase for consistency
      final key = carModel.toLowerCase().trim();
      await box.put(key, jsonEncode(insights));
    } catch (e) {
      debugPrint('Failed to cache chronic insights: $e');
    }
  }

  /// Retrieves cached chronic insights for a specific car model. Returns an empty list if not found.
  Future<List<Map<String, dynamic>>> getCachedChronicInsights(String carModel) async {
    try {
      final box = Hive.box(_insightsBoxName);
      final key = carModel.toLowerCase().trim();
      final dataStr = box.get(key);
      
      if (dataStr != null) {
        final List<dynamic> decoded = jsonDecode(dataStr as String);
        return decoded.map((e) => e as Map<String, dynamic>).toList();
      }
    } catch (e) {
      debugPrint('Failed to get cached chronic insights: $e');
    }
    return [];
  }
}
