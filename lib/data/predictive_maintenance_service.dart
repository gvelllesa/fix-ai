import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../core/config/env_config.dart';
import 'supabase_client.dart';
import 'local_cache_service.dart';

/// Service responsible for predicting future vehicle failures based on global 
/// data, vehicle mileage, and AI heuristics.
class PredictiveMaintenanceService {
  static const String liteModel = 'models/gemini-3.1-flash-lite';
  static const String proModel = 'models/gemini-3.1-flash-lite';

  final SupabaseClient _supabaseClient;
  late final GenerativeModel _model;

  PredictiveMaintenanceService({SupabaseClient? supabaseClient, GenerativeModel? model}) 
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client {
    _model = model ?? _createModel();
  }

  static dynamic _safeJsonDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      debugPrint('AI returned non-JSON in PredictiveMaintenanceService');
      return null;
    }
  }

  static GenerativeModel _createModel() {
    return GenerativeModel(
      // Utilizing Gemini 3.1 Pro to evaluate complex predictive maintenance thresholds
      model: liteModel,
      apiKey: EnvConfig.geminiApiKey,
      systemInstruction: Content.system(
        "You are an Advanced Automotive Predictive Maintenance Engine. "
        "Your task is to analyze the current vehicle mileage and history against known global failure thresholds (insights). "
        "Determine if the car is currently approaching or at a critical failure point for any specific parts (e.g., cooling system at 120k km, timing chain at 150k km). "
        "Output ONLY a valid JSON object matching this schema: "
        "{ \"should_warn\": true/false, \"warning_title\": \"Brief description of the impending failure\", \"preventive_action_steps\": [\"Step 1\", \"Step 2\"] }. "
        "Do not include markdown blocks, headers, or any other formatting."
      ),
    );
  }

  /// Evaluates if the vehicle is nearing a critical chronic failure milestone.
  Future<Map<String, dynamic>> checkPredictiveAlerts(String carProfileId) async {
    try {
      // 1. Fetch current vehicle profile (mileage, model, history)
      Map<String, dynamic>? carData;
      
      try {
        carData = await _supabaseClient
            .from('car_profiles')
            .select('*') // Selects all to safely grab model, mileage, and potential history arrays
            .eq('id', carProfileId)
            .maybeSingle();

        if (carData != null) {
          // Keep the cache warm with the fresh network data
          await LocalCacheService().cacheVehicleProfile(carData);
        }
      } catch (e) {
        debugPrint('Network error fetching profile, falling back to LocalCacheService: $e');
        carData = await LocalCacheService().getCachedVehicleProfile(carProfileId);
      }

      if (carData == null) {
        throw Exception('Car profile not found for ID: $carProfileId (Network failed and cache is empty)');
      }

      final brand = carData['brand'] ?? 'Unknown';
      final model = carData['model'] ?? 'Unknown';
      final history = carData['history'] ?? 'No history provided';
      
      // Defensive mileage parsing
      final mileageStr = carData['mileage']?.toString() ?? '0';
      final mileage = int.tryParse(mileageStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

      // 2. Fetch known chronic issues (saved_insights) for this specific brand/model
      List<dynamic> globalInsights = [];
      
      try {
        globalInsights = await _supabaseClient
            .from('saved_insights')
            .select('issue_description, confidence_score')
            .ilike('brand', '%$brand%')
            .ilike('model', '%$model%')
            .gte('confidence_score', 0.60) // Target highly verified recurring issues
            .limit(20);
            
        // Keep the cache warm with the fresh network data
        final insightsToCache = globalInsights.map((e) => e as Map<String, dynamic>).toList();
        await LocalCacheService().cacheChronicInsights(model, insightsToCache);
      } catch (e) {
        debugPrint('Network error fetching insights, falling back to LocalCacheService: $e');
        globalInsights = await LocalCacheService().getCachedChronicInsights(model);
      }

      if (globalInsights.isEmpty) {
        // No global insights to evaluate against
        return {
          'should_warn': false,
          'warning_title': '',
          'preventive_action_steps': []
        };
      }

      // 3. Construct the prompt for Gemini
      final prompt = '''
Evaluate the following vehicle data against our global chronic insights. Determine if the vehicle is currently at risk of an impending part failure based on its current mileage ($mileage km) and its maintenance history.

Vehicle Profile:
Brand: $brand
Model: $model
Current Mileage: $mileage km
Service History / State: $history

Global Chronic Insights for this Model:
${jsonEncode(globalInsights)}

Provide a JSON response indicating whether an alert should be triggered. Be proactive but realistic. If the car's mileage is significantly below known failure points, set should_warn to false.
''';

      // 4. Generate the predictive response via Gemini
      final response = await _model.generateContent([Content.text(prompt)]);
      
      // 5. Parse the structured JSON output
      final rawText = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '{}';
      final parsed = _safeJsonDecode(rawText);
      if (parsed == null || parsed is! Map) {
        return {
          'should_warn': false,
          'warning_title': 'AI response was not parseable.',
          'preventive_action_steps': []
        };
      }
      final Map<String, dynamic> result = Map<String, dynamic>.from(parsed);

      // Return a guaranteed map format matching the strict UI requirements
      return {
        'should_warn': result['should_warn'] == true,
        'warning_title': result['warning_title']?.toString() ?? '',
        'preventive_action_steps': List<String>.from(result['preventive_action_steps'] ?? []),
      };

    } catch (e) {
      debugPrint('Predictive Alerts Error: $e');
      // Fail gracefully for UI consumers
      return {
        'should_warn': false,
        'warning_title': 'Unable to process predictive insights at this time.',
        'preventive_action_steps': []
      };
    }
  }
}
