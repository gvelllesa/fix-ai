import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../core/config/env_config.dart';
import 'supabase_client.dart';

/// An isolated data pipeline service dedicated to automated feedback 
/// loops and self-learning capabilities for the diagnostic AI.
class SelfLearningService {
  static const String liteModel = 'models/gemini-3.1-flash-lite';
  static const String proModel = 'models/gemini-3.1-flash-lite';

  final SupabaseClient _supabaseClient;
  late final GenerativeModel _model;

  SelfLearningService({SupabaseClient? supabaseClient, GenerativeModel? model}) 
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client {
    _model = model ?? _createModel();
  }

  static dynamic _safeJsonDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      debugPrint('AI returned non-JSON in SelfLearningService');
      return null;
    }
  }

  static GenerativeModel _createModel() {
    return GenerativeModel(
      // Utilizing the highly capable Gemini 1.5 Pro to handle complex data aggregation
      model: liteModel,
      apiKey: EnvConfig.geminiApiKey,
      systemInstruction: Content.system(
        "You are an AI Data Pipeline Analyst. Your job is to ingest raw real-world mechanic feedback "
        "and cross-reference it with known vehicle data to generate statistically updated "
        "insights. Determine if an issue is a high-probability chronic fault and output the updated summary."
      ),
    );
  }

  /// Inserts the user's verified mechanic outcome into the 'resolved_cases' table.
  Future<void> submitRealFixFeedback(String carProfileId, String userSymptom, String finalRealFix) async {
    try {
      final String userId = _supabaseClient.auth.currentUser?.id ?? '';
      
      // Smart Relational Hook: Since the signature only passes the car profile, 
      // we dynamically fetch the most recent chat session ID for this car/user 
      // to satisfy the strict relational schema of 'resolved_cases'.
      final recentChat = await _supabaseClient
          .from('chat_history')
          .select('id')
          .eq('car_profile_id', carProfileId)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (recentChat == null) {
         throw Exception('No recent diagnostic chat found for this vehicle to attach feedback.');
      }

      await _supabaseClient.from('resolved_cases').insert({
        'chat_id': recentChat['id'],
        'actual_fix': finalRealFix,
        'feedback_notes': 'Symptom: $userSymptom',
      });
    } catch (e) {
      throw Exception('Failed to submit real fix: $e');
    }
  }

  /// Cron-job style background function meant to be executed periodically.
  /// It reads new mechanic feedback, processes probability shifts via Gemini, 
  /// and updates the global 'saved_insights' table to make the engine smarter.
  Future<void> optimizeDiagnosticWeights(String carModel) async {
    try {
      // 1. Fetch recent unresolved/unprocessed feedback entries
      final List<dynamic> recentCases = await _supabaseClient
          .from('resolved_cases')
          .select('id, actual_fix, feedback_notes, chat_id')
          .order('created_at', ascending: false)
          .limit(50); // Batch process size

      if (recentCases.isEmpty) return;

      // 2. Fetch existing global insights for cross-referencing this specific model
      final List<dynamic> globalInsights = await _supabaseClient
          .from('saved_insights')
          .select('*')
          .ilike('model', '%$carModel%')
          .limit(100);

      // 3. Construct the analytical data ingestion prompt
      final prompt = '''
Analyze the following batch of real-world workshop fixes and cross-reference them against our existing global insights database specifically for the model: $carModel. 
If you detect a strong correlation (e.g., a specific symptom leads to a specific fix significantly more often than previously thought), rewrite the insight summary with updated probability weightings.
(e.g., "90% of our local users found that this symptom was caused by a warped brake disc rather than worn pads").

Recent Real-World Fixes:
${jsonEncode(recentCases)}

Current Global Insights Database for $carModel:
${jsonEncode(globalInsights)}

Output a structured JSON array of updated insights to be upserted into the database. Ensure the confidence_score is adjusted accurately (0.0 to 1.0).
Format:
[
  {
    "brand": "Brand Name",
    "model": "$carModel",
    "issue_description": "Updated description with the new real-world % weighting...",
    "confidence_score": 0.95
  }
]
''';

      // 4. Ingest and aggregate the data via Gemini
      final response = await _model.generateContent([Content.text(prompt)]);
      
      // Clean up potential markdown formatting from the response
      final String aiAnalysisText = response.text?.replaceAll('```json', '').replaceAll('```', '') ?? '[]';
      
      final parsed = _safeJsonDecode(aiAnalysisText.trim());
      if (parsed == null || parsed is! List) {
        debugPrint('Self-learning: AI returned non-JSON, skipping upsert.');
        return;
      }
      final List<dynamic> updatedInsights = parsed;

      // Batch upsert to evolve the global knowledge base
      final batch = updatedInsights.map((insight) => {
        'brand': insight['brand'],
        'model': insight['model'],
        'issue_description': insight['issue_description'],
        'confidence_score': insight['confidence_score'],
      }).toList();
      if (batch.isNotEmpty) {
        await _supabaseClient.from('saved_insights').upsert(batch);
      }

    } catch (e) {
      debugPrint('Automated Sync Error: $e');
    }
  }
}
