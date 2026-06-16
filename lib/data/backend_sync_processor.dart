import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../core/config/env_config.dart';
import 'supabase_client.dart';

/// Isolated Edge Function / Backend Utility for data digestion pipelines.
/// Handles processing of massive text dumps and synchronizing global insights 
/// independently from the Flutter UI layer.
class BackendSyncProcessor {
  static const String liteModel = 'models/gemini-3.1-flash-lite';
  static const String proModel = 'models/gemini-3.1-flash-lite';

  final SupabaseClient _supabaseClient;
  late final GenerativeModel _model;

  BackendSyncProcessor({SupabaseClient? supabaseClient, GenerativeModel? model}) 
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client {
    _model = model ?? _createModel();
  }

  /// Safe JSON decode that returns null instead of throwing on malformed AI output.
  static dynamic _safeJsonDecode(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException catch (e) {
      debugPrint('AI returned non-JSON: ${raw.substring(0, raw.length.clamp(0, 200))}');
      return null;
    }
  }

  static GenerativeModel _createModel() {
    return GenerativeModel(
      // Utilizing the Pro model for heavy text digestion and analysis
      model: liteModel,
      apiKey: EnvConfig.geminiApiKey,
      systemInstruction: Content.system(
        "You are an AI Data Pipeline Analyst for an automotive diagnostic platform. "
        "Your role is to ingest raw forum data, scrape text, and real-world mechanic feedback. "
        "You cross-reference this to extract chronic failures, provide clear descriptions, "
        "and assign confidence scores for specific vehicle brands and models."
      ),
    );
  }

  /// Step 4 Pipeline: Digests raw scraped forum text (from Reddit/Drive2, etc.)
  /// Extracts chronic failures, clear descriptions, and assigns a confidence score.
  /// Inserts the structured data into the 'saved_insights' table.
  Future<Map<String, dynamic>> processRawForumData(String rawScrapedText, String brand, String model) async {
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

Format:
[
  {
    "issue_description": "Clear description of the issue...",
    "confidence_score": 0.85,
    "source_url": "Scraped Forum Data"
  }
]
''';

      final response = await _model.generateContent([Content.text(prompt)]);
      
      final String aiAnalysisText = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '[]';
      
      final parsed = _safeJsonDecode(aiAnalysisText);
      if (parsed == null || parsed is! List) {
        return {'status': 'Failure', 'error': 'AI returned non-JSON response', 'extracted_text': aiAnalysisText};
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

      final List<Map<String, dynamic>> recordsToInsert = extractedInsights.map((insight) {
        return {
          'brand': brand,
          'model': model,
          'issue_description': insight['issue_description'],
          'confidence_score': insight['confidence_score'],
          'source_url': insight['source_url'] ?? 'Scraped Forum Data',
        };
      }).toList();

      // Bulk-insert the parsed chronic issues into saved_insights
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
      // 1. Fetch recent unresolved/unprocessed feedback entries
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

      // 2. Fetch existing global insights for cross-referencing to update probability metrics
      final List<dynamic> globalInsights = await _supabaseClient
          .from('saved_insights')
          .select('*')
          .limit(200);

      // 3. Construct the analytical prompt to update probabilities
      final prompt = '''
We have a new batch of real-world workshop outcomes (verified fixes) and our current global insights database.
Analyze the real-world fixes and cross-reference them against the existing global insights.
Your task is to update the 'chronic_issue_summary' and probability metrics dynamically based on these real-world workshop outcomes.

If a specific symptom leads to a specific fix frequently, update the confidence_score and rewrite the issue_description to reflect the new probability metrics 
(e.g., "Updated: 85% of real-world workshop outcomes point to a faulty transmission module for this symptom.").

Recent Real-World Fixes (resolved_cases):
${jsonEncode(recentCases)}

Current Global Insights (saved_insights):
${jsonEncode(globalInsights)}

Output ONLY a structured JSON array of updated insights to be upserted. Include the database ID if you are modifying an existing insight, 
otherwise ensure brand, model, issue_description, and confidence_score are provided.

Format:
[
  {
    "id": 123, // Omit if this is a completely new insight rather than an update
    "brand": "Brand Name",
    "model": "Model Name",
    "issue_description": "Updated description with new real-world probability metrics...",
    "confidence_score": 0.90
  }
]
''';

      // 4. Send to Gemini for data digestion
      final response = await _model.generateContent([Content.text(prompt)]);
      
      final String aiAnalysisText = response.text?.replaceAll('```json', '').replaceAll('```', '').trim() ?? '[]';
      
      final parsed = _safeJsonDecode(aiAnalysisText);
      if (parsed == null || parsed is! List) {
        return {'status': 'Failure', 'error': 'AI returned non-JSON response', 'extracted_text': aiAnalysisText};
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

      // 5. Batch upsert the updated insights back into the database
      final batch = updatedInsights.map((insight) => {
        'brand': insight['brand'],
        'model': insight['model'],
        'issue_description': insight['issue_description'],
        'confidence_score': insight['confidence_score'],
        if (insight['id'] != null) 'id': insight['id'],
      }).toList();
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
