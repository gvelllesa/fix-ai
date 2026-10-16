import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';

/// Isolated Edge Function / Backend Utility for data digestion pipelines.
/// Routes AI analysis through the `ai-proxy` Supabase Edge Function so no
/// Gemini API key is embedded in the client binary.
class BackendSyncProcessor {
  static const String liteModel = 'gemini-2.5-flash';
  static const String proModel = 'gemini-2.5-flash';

  final SupabaseClient _supabaseClient;

  BackendSyncProcessor({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  static const String _systemInstruction =
      'You are an AI Data Pipeline Analyst for an automotive diagnostic platform. '
      'Your role is to ingest raw forum data, scrape text, and real-world mechanic feedback. '
      'You cross-reference this to extract chronic failures, provide clear descriptions, '
      'and assign confidence scores for specific vehicle brands and models.';

  /// Safe JSON decode that returns null instead of throwing on malformed AI output.
  static dynamic _safeJsonDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      debugPrint('AI returned non-JSON: ${raw.substring(0, raw.length.clamp(0, 200))}');
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
      throw Exception('ai-proxy failed with status ${res.status}: ${res.data}');
    }
    final data = res.data;
    if (data is Map && data['text'] != null) {
      return data['text'].toString();
    }
    if (data is String) {
      final decoded = _safeJsonDecode(data);
      if (decoded is Map && decoded['text'] != null) {
        return decoded['text'].toString();
      }
    }
    return '[]';
  }

  /// Step 4 Pipeline: Digests raw scraped forum text (from Reddit/Drive2, etc.)
  /// Extracts chronic failures, clear descriptions, and assigns a confidence score.
  /// Inserts the structured data into the 'saved_insights' table.
  Future<Map<String, dynamic>> processRawForumData(
    String rawScrapedText,
    String brand,
    String model,
  ) async {
    try {
      final prompt = '''
Analyze the following raw scraped text from car forums regarding the $brand $model.
Extract any chronic failures or common issues mentioned. Provide a clear, concise description for each issue, 
and assign a confidence_score (between 0.0 and 1.0) based on how frequently or confidently it is discussed in the text.

Raw Scraped Text:
$rawScrapedText

Output ONLY a structured JSON array of objects with the following keys:
- "issue_description": A clear description of the chronic failure.
- "confidence_score": A number between 0.0 and 1.0.
- "source_url": A generic source string like "Scraped Forum Data".
''';

      final rawText = await _invokeAiProxy(prompt);
      final String aiAnalysisText =
          rawText.replaceAll('```json', '').replaceAll('```', '').trim();

      final parsed = _safeJsonDecode(aiAnalysisText);
      if (parsed == null || parsed is! List) {
        return {
          'status': 'Failure',
          'error': 'AI returned non-JSON response',
          'extracted_text': aiAnalysisText,
        };
      }
      final List<dynamic> extractedInsights = parsed;

      if (extractedInsights.isEmpty) {
        debugPrint('No insights extracted for $brand $model.');
        return {
          'status': 'Success (No insights found)',
          'extracted_text': aiAnalysisText,
          'inserted_count': 0,
        };
      }

      final List<Map<String, dynamic>> recordsToInsert =
          extractedInsights.map((insight) {
        return {
          'brand': brand,
          'model': model,
          'issue_description': insight['issue_description'],
          'confidence_score': insight['confidence_score'],
          'source_url': insight['source_url'] ?? 'Scraped Forum Data',
        };
      }).toList();

      await _supabaseClient.from('saved_insights').insert(recordsToInsert);

      return {
        'status': 'Success',
        'extracted_text': aiAnalysisText,
        'inserted_count': recordsToInsert.length,
      };
    } catch (e) {
      debugPrint('Error processing raw forum data for $brand $model: $e');
      return {
        'status': 'Failure',
        'error': e.toString(),
      };
    }
  }

  /// Step 7 Pipeline: Syncs User Feedback with Insights
  /// Reads newly verified fixes from 'resolved_cases' and dynamically updates
  /// the probability metrics and 'chronic_issue_summary' in 'saved_insights'.
  Future<Map<String, dynamic>> syncUserFeedbackWithInsights() async {
    try {
      final List<dynamic> recentCases = await _supabaseClient
          .from('resolved_cases')
          .select('id, actual_fix, feedback_notes, chat_id')
          .order('created_at', ascending: false)
          .limit(100);

      if (recentCases.isEmpty) {
        debugPrint('No recent resolved cases to sync.');
        return {
          'status': 'Success (No cases)',
          'updated_count': 0,
        };
      }

      final List<dynamic> globalInsights = await _supabaseClient
          .from('saved_insights')
          .select('*')
          .limit(200);

      final prompt = '''
We have a new batch of real-world workshop outcomes (verified fixes) and our current global insights database.
Analyze the real-world fixes and cross-reference them against the existing global insights.
Your task is to update the 'chronic_issue_summary' and probability metrics dynamically based on these real-world workshop outcomes.

Recent Real-World Fixes (resolved_cases):
${jsonEncode(recentCases)}

Current Global Insights (saved_insights):
${jsonEncode(globalInsights)}

Output ONLY a structured JSON array of updated insights to be upserted.
''';

      final rawText = await _invokeAiProxy(prompt);
      final String aiAnalysisText =
          rawText.replaceAll('```json', '').replaceAll('```', '').trim();

      final parsed = _safeJsonDecode(aiAnalysisText);
      if (parsed == null || parsed is! List) {
        return {
          'status': 'Failure',
          'error': 'AI returned non-JSON response',
          'extracted_text': aiAnalysisText,
        };
      }
      final List<dynamic> updatedInsights = parsed;

      if (updatedInsights.isEmpty) {
        debugPrint('No updates generated by the AI.');
        return {
          'status': 'Success (No updates needed)',
          'updated_count': 0,
          'extracted_text': aiAnalysisText,
        };
      }

      final batch = updatedInsights
          .map((insight) => {
                'brand': insight['brand'],
                'model': insight['model'],
                'issue_description': insight['issue_description'],
                'confidence_score': insight['confidence_score'],
                if (insight['id'] != null) 'id': insight['id'],
              })
          .toList();
      await _supabaseClient.from('saved_insights').upsert(batch);

      return {
        'status': 'Success',
        'updated_count': updatedInsights.length,
        'extracted_text': aiAnalysisText,
      };
    } catch (e) {
      debugPrint('Error synchronizing user feedback with insights: $e');
      return {
        'status': 'Failure',
        'error': e.toString(),
      };
    }
  }
}
