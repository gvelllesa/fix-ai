import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

/// An isolated data pipeline service dedicated to automated feedback
/// loops and self-learning capabilities via the `ai-proxy` Edge Function.
class SelfLearningService {
  static const String liteModel = 'gemini-2.5-flash';
  static const String proModel = 'gemini-2.5-flash';

  final SupabaseClient _supabaseClient;

  SelfLearningService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  static const String _systemInstruction =
      'You are an AI Data Pipeline Analyst. Your job is to ingest raw real-world mechanic feedback '
      'and cross-reference it with known vehicle data to generate statistically updated '
      'insights. Determine if an issue is a high-probability chronic fault and output the updated summary.';

  static dynamic _safeJsonDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      debugPrint('AI returned non-JSON in SelfLearningService');
      return null;
    }
  }

  /// Inserts the user's verified mechanic outcome into the 'resolved_cases' table.
  Future<void> submitRealFixFeedback(
    String carProfileId,
    String userSymptom,
    String finalRealFix,
  ) async {
    try {
      final String userId = _supabaseClient.auth.currentUser?.id ?? '';

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
  /// It reads new mechanic feedback, processes probability shifts via `ai-proxy`,
  /// and updates the global 'saved_insights' table.
  Future<void> optimizeDiagnosticWeights(String carModel) async {
    try {
      final List<dynamic> recentCases = await _supabaseClient
          .from('resolved_cases')
          .select('id, actual_fix, feedback_notes, chat_id')
          .order('created_at', ascending: false)
          .limit(50);

      if (recentCases.isEmpty) return;

      final List<dynamic> globalInsights = await _supabaseClient
          .from('saved_insights')
          .select('*')
          .ilike('model', '%$carModel%')
          .limit(100);

      final prompt = '''
Analyze the following batch of real-world workshop fixes and cross-reference them against our existing global insights database specifically for the model: $carModel. 
If you detect a strong correlation, rewrite the insight summary with updated probability weightings.

Recent Real-World Fixes:
${jsonEncode(recentCases)}

Current Global Insights Database for $carModel:
${jsonEncode(globalInsights)}

Output a structured JSON array of updated insights to be upserted into the database. Ensure the confidence_score is adjusted accurately (0.0 to 1.0).
''';

      final res = await _supabaseClient.functions.invoke(
        'ai-proxy',
        body: {
          'action': 'generate_content',
          'model': liteModel,
          'prompt': prompt,
          'systemInstruction': _systemInstruction,
        },
      );
      if (res.status != 200) return;

      String rawText = '[]';
      if (res.data is Map && res.data['text'] != null) {
        rawText = res.data['text'].toString();
      } else if (res.data is String) {
        final decoded = _safeJsonDecode(res.data as String);
        if (decoded is Map && decoded['text'] != null) {
          rawText = decoded['text'].toString();
        }
      }

      final String aiAnalysisText =
          rawText.replaceAll('```json', '').replaceAll('```', '');

      final parsed = _safeJsonDecode(aiAnalysisText.trim());
      if (parsed == null || parsed is! List) {
        debugPrint('Self-learning: AI returned non-JSON, skipping upsert.');
        return;
      }
      final List<dynamic> updatedInsights = parsed;

      final batch = updatedInsights
          .map((insight) => {
                'brand': insight['brand'],
                'model': insight['model'],
                'issue_description': insight['issue_description'],
                'confidence_score': insight['confidence_score'],
              })
          .toList();
      if (batch.isNotEmpty) {
        await _supabaseClient.from('saved_insights').upsert(batch);
      }
    } catch (e) {
      debugPrint('Automated Sync Error: $e');
    }
  }
}
