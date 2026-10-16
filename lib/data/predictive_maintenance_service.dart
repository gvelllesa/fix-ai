import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'local_cache_service.dart';

/// Service responsible for predicting future vehicle failures based on global
/// data, vehicle mileage, and AI heuristics via the `ai-proxy` Edge Function.
class PredictiveMaintenanceService {
  static const String liteModel = 'gemini-2.5-flash';
  static const String proModel = 'gemini-2.5-flash';

  final SupabaseClient _supabaseClient;

  PredictiveMaintenanceService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  static const String _systemInstruction =
      'You are an Advanced Automotive Predictive Maintenance Engine. '
      'Your task is to analyze the current vehicle mileage and history against known global failure thresholds (insights). '
      'Determine if the car is currently approaching or at a critical failure point for any specific parts (e.g., cooling system at 120k km, timing chain at 150k km). '
      'Output ONLY a valid JSON object matching this schema: '
      '{ "should_warn": true/false, "warning_title": "Brief description of the impending failure", "preventive_action_steps": ["Step 1", "Step 2"] }. '
      'Do not include markdown blocks, headers, or any other formatting.';

  static dynamic _safeJsonDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      debugPrint('AI returned non-JSON in PredictiveMaintenanceService');
      return null;
    }
  }

  Future<String> _invokeAiProxy(String prompt) async {
    final res = await _supabaseClient.functions.invoke(
      'ai-proxy',
      body: {
        'action': 'generate_content',
        'model': liteModel,
        'prompt': prompt,
        'systemInstruction': _systemInstruction,
      },
    );
    if (res.status != 200) {
      throw Exception('ai-proxy status ${res.status}: ${res.data}');
    }
    if (res.data is Map && res.data['text'] != null) {
      return res.data['text'].toString();
    }
    if (res.data is String) {
      final decoded = _safeJsonDecode(res.data as String);
      if (decoded is Map && decoded['text'] != null) {
        return decoded['text'].toString();
      }
    }
    return '{}';
  }

  /// Evaluates if the vehicle is nearing a critical chronic failure milestone.
  Future<Map<String, dynamic>> checkPredictiveAlerts(String carProfileId) async {
    try {
      Map<String, dynamic>? carData;

      try {
        try {
          carData = await _supabaseClient
              .from('garage')
              .select('*')
              .eq('id', carProfileId)
              .maybeSingle();
        } catch (_) {}

        carData ??= await _supabaseClient
            .from('car_profiles')
            .select('*')
            .eq('id', carProfileId)
            .maybeSingle();

        if (carData != null) {
          await LocalCacheService().cacheVehicleProfile(carData);
        }
      } catch (e) {
        debugPrint('Network error fetching profile, falling back to LocalCacheService: $e');
        carData = await LocalCacheService().getCachedVehicleProfile(carProfileId);
      }

      if (carData == null) {
        throw Exception('Car profile not found for ID: $carProfileId (Network failed and cache is empty)');
      }

      final brand = carData['make'] ?? carData['brand'] ?? 'Unknown';
      final model = carData['model'] ?? 'Unknown';
      final history = carData['history'] ?? 'No history provided';

      final mileageStr = carData['mileage']?.toString() ?? '0';
      final mileage = int.tryParse(mileageStr.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

      List<dynamic> globalInsights = [];

      try {
        globalInsights = await _supabaseClient
            .from('saved_insights')
            .select('issue_description, confidence_score')
            .ilike('brand', '%$brand%')
            .ilike('model', '%$model%')
            .gte('confidence_score', 0.60)
            .limit(20);

        final insightsToCache =
            globalInsights.map((e) => e as Map<String, dynamic>).toList();
        await LocalCacheService().cacheChronicInsights(model, insightsToCache);
      } catch (e) {
        debugPrint('Network error fetching insights, falling back to LocalCacheService: $e');
        globalInsights = await LocalCacheService().getCachedChronicInsights(model);
      }

      if (globalInsights.isEmpty) {
        return {
          'should_warn': false,
          'warning_title': '',
          'preventive_action_steps': [],
        };
      }

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

      final responseText = await _invokeAiProxy(prompt);
      final rawText = responseText.replaceAll('```json', '').replaceAll('```', '').trim();
      final parsed = _safeJsonDecode(rawText);
      if (parsed == null || parsed is! Map) {
        return {
          'should_warn': false,
          'warning_title': 'AI response was not parseable.',
          'preventive_action_steps': [],
        };
      }
      final Map<String, dynamic> result = Map<String, dynamic>.from(parsed);

      return {
        'should_warn': result['should_warn'] == true,
        'warning_title': result['warning_title']?.toString() ?? '',
        'preventive_action_steps':
            List<String>.from(result['preventive_action_steps'] ?? []),
      };
    } catch (e) {
      debugPrint('Predictive Alerts Error: $e');
      return {
        'should_warn': false,
        'warning_title': 'Unable to process predictive insights at this time.',
        'preventive_action_steps': [],
      };
    }
  }
}
