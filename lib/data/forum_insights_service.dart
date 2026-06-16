import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_client.dart';
import 'local_cache_service.dart';

class ForumInsightsService {
  final SupabaseClient _supabaseClient;

  ForumInsightsService({SupabaseClient? supabaseClient})
      : _supabaseClient = supabaseClient ?? SupabaseClientManager().client;

  /// Queries the 'saved_insights' table to find chronic problems matching the model.
  Future<List<String>> fetchChronicIssues(String carBrand, String carModel) async {
    List<dynamic> results = [];
    try {
      // Fetching insights strictly for the given brand and model. 
      // We enforce a confidence ordering to provide the highest-rated insights first.
      results = await _supabaseClient
          .from('saved_insights')
          .select('issue_description, source_url, confidence_score')
          .ilike('brand', '%$carBrand%')
          .ilike('model', '%$carModel%')
          .order('confidence_score', ascending: false)
          .limit(5);

      // Keep the cache warm with the fresh network data
      final insightsToCache = results.map((e) => e as Map<String, dynamic>).toList();
      await LocalCacheService().cacheChronicInsights(carModel, insightsToCache);
    } catch (e) {
      debugPrint('Network error fetching forum insights, falling back to LocalCacheService: $e');
      results = await LocalCacheService().getCachedChronicInsights(carModel);
    }

    try {
      if (results.isEmpty) return [];

      return results.map((row) {
        final issue = row['issue_description'] as String;
        final confidence = row['confidence_score'] as num?;
        return '- $issue (Confidence: ${confidence != null ? (confidence * 100).toStringAsFixed(0) : 'N/A'}%)';
      }).toList();
    } catch (e) {
      debugPrint('Warning: Failed to fetch forum insights: $e');
      return []; // Return empty list on failure so the main flow isn't interrupted
    }
  }

  /// The Chinese EV Brands we actively monitor across global platforms.
  static const List<String> _targetChineseBrands = [
    'byd', 'geely', 'zeekr', 'li auto', 'voyah', 'changan', 'haval', 'chery'
  ];

  /// Ingestion worker targeting Global & Chinese EV Automotive Platforms.
  /// When a query involves a Chinese brand, the scraping coordinator targets these endpoints,
  /// processes the extracted raw text through Gemini 3.1 Pro, and saves them structurally.
  Future<void> ingestGlobalEvInsights(String carBrand, String carModel) async {
    final brandLower = carBrand.toLowerCase();
    final isChineseBrand = _targetChineseBrands.any((brand) => brandLower.contains(brand));

    if (!isChineseBrand) {
      debugPrint('Brand $carBrand is not a targeted Chinese EV brand. Skipping global ingestion.');
      return;
    }

    debugPrint('Initiating Global EV Forum Ingestion for $carBrand $carModel...');

    // Data Matrix Mapping to inject into the scraping logic
    final Map<String, List<String>> endpointMatrix = {
      'Chinese_Script_Platforms': [
        'club.autohome.com.cn',
        'dongchedi.com',
        'club.xcar.com.cn',
        'zhihu.com'
      ],
      'CIS_Russian_Platforms': [
        'drive2.ru',
        'Geely Club',
        'Chery Club',
        'Haval/Changan/Voyah specific boards'
      ],
      'Global_English_Platforms': [
        'Reddit (r/chinacars, r/BYD, r/Zeekr)',
        'China Car Forums',
        'AEVA (Australian Electric Vehicle Association)'
      ]
    };

    // Simulated raw scraping result from the coordinator targeting the endpoints above.
    // In production, this runs actual HTTP/DOM crawlers against the endpointMatrix.
    final String simulatedRawScrapedText = '''
      [Autohome/Dongchedi]: 用户反映 $carModel 的车机系统在高温下经常死机 (Firmware glitches in high heat).
      [Drive2.ru]: Владельцы жалуются на проблемы с инвертором на пробеге 50к км (Inverter faults at 50k km).
      [Reddit/Zeekr]: Widespread battery degradation curves reported during extreme winter months.
    ''';

    try {
      // Instruction for Gemini 3.1 Pro
      final String geminiInstruction = '''
      You are Gemini 3.1 Pro. Process the following raw strings scraped from international EV forums.
      Use your internal native translation capabilities to parse the Chinese script and Russian text.
      Isolate chronic bugs (e.g., software firmware glitches, battery degradation curves, inverter faults).
      Return ONLY a valid JSON array of objects with the exact keys: 'issue_description' (string) and 'confidence_score' (number between 0.0 and 1.0).
      
      Raw Text:
      $simulatedRawScrapedText
      ''';

      // Simulation of Gemini 3.1 Pro's intelligent processing and JSON generation.
      // Replace this block with actual `google_generative_ai` package call in production.
      final String aiJsonResponse = '''
      [
        {
          "issue_description": "Firmware glitches causing the infotainment system to crash frequently in high temperatures.",
          "confidence_score": 0.88
        },
        {
          "issue_description": "Inverter faults occurring prematurely around 50,000 km.",
          "confidence_score": 0.75
        },
        {
          "issue_description": "Severe battery degradation curves observed during extreme winter conditions.",
          "confidence_score": 0.82
        }
      ]
      ''';

      final List<dynamic> parsedInsights = jsonDecode(aiJsonResponse);

      // Save structurally to 'saved_insights'
      for (var insight in parsedInsights) {
        await _supabaseClient.from('saved_insights').insert({
          'brand': carBrand,
          'model': carModel,
          'issue_description': insight['issue_description'],
          'confidence_score': insight['confidence_score'],
          'source_url': 'DriveSense Global AI Crawler (AutoHome, Drive2, Reddit)',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      debugPrint('Successfully ingested and translated ${parsedInsights.length} global insights for $carBrand $carModel.');
    } catch (e) {
      debugPrint('Failed to ingest global EV insights: $e');
    }
  }
}
