import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'supabase_client.dart';
import 'forum_insights_service.dart';
import '../core/services/parts_finder_service.dart';

/// Core diagnostic engine routing all AI requests through the server-side
/// `ai-proxy` Supabase Edge Function.
///
/// Quota enforcement is handled atomically inside `ai-proxy` via the
/// `consume_ai_quota` Postgres SECURITY DEFINER RPC.
class GeminiDiagnosticService {
  static const String liteModel = 'gemini-2.5-flash';
  static const String proModel = 'gemini-2.5-flash';

  final SupabaseClient _supabaseClient;
  final ForumInsightsService _insightsService;

  final List<String> _sessionTranscript = [];

  GeminiDiagnosticService({
    SupabaseClient? supabaseClient,
    ForumInsightsService? insightsService,
  })  : _supabaseClient = supabaseClient ?? SupabaseClientManager().client,
        _insightsService = insightsService ??
            ForumInsightsService(
              supabaseClient: supabaseClient ?? SupabaseClientManager().client,
            );

  String _buildSystemPrompt({
    Map<String, dynamic>? carProfile,
    String? userCountry,
  }) {
    final countryText = userCountry != null && userCountry != 'Unknown'
        ? '\nThe user is currently located in $userCountry. When they ask to find a car part, you must prioritize and return search links from the most popular local automotive marketplaces in $userCountry.'
        : '';

    final basePrompt =
        '''You are FIX AI, a premium diagnostic assistant. Always respond STRICTLY in the exact same language the user used in their current prompt. Do not mix languages within a single response.$countryText

When you successfully identify a likely mechanical issue and recommend replacing a specific part (e.g., 'Spark Plugs', 'VANOS Solenoid'), you MUST seamlessly offer to find the part for the user at the end of your message.

Behavior Rules:
- Do not ask for parts immediately. First, provide the diagnosis using standardized part names.
- End your diagnostic message with a friendly, natural question like: "გსურთ, მოგიძებნოთ ეს ნაწილი (მაგალითად: აალების სანთლები) და შევადაროთ ფასები ადგილობრივ ბაზარზე?"
- If the user agrees, ask for their VIN code ONLY if it is not already provided in the carProfile. Mention that the VIN is needed for exact compatibility.''';

    if (carProfile != null) {
      final make = carProfile['make'] ?? carProfile['brand'] ?? 'Unknown Make';
      final modelStr = carProfile['model'] ?? 'Unknown Model';
      final year = carProfile['year']?.toString() ?? 'Unknown Year';
      final engine =
          carProfile['engine_type'] ?? carProfile['engine'] ?? 'Unknown Engine';
      final vin = carProfile['vin'] ?? 'Not provided';

      return "The user is asking about their $year $make $modelStr with engine code $engine. VIN: $vin. Provide highly specific advice for this exact vehicle. Do not ask them what car they have unless asking for the VIN for part compatibility when it is 'Not provided'.\n\n$basePrompt";
    }
    return basePrompt;
  }

  Future<String> _invokeAiProxy({
    required String model,
    required String prompt,
    String? systemInstruction,
    List<Map<String, String>>? mediaParts,
  }) async {
    final res = await _supabaseClient.functions.invoke(
      'ai-proxy',
      body: {
        'action': 'generate_content',
        'model': model,
        'prompt': prompt,
        if (systemInstruction != null) 'systemInstruction': systemInstruction,
        if (mediaParts != null && mediaParts.isNotEmpty) 'mediaParts': mediaParts,
      },
    );

    if (res.status == 429) {
      throw Exception(
        'თქვენ ამოწურეთ თქვენი პაკეტის ლიმიტი. გთხოვთ განაახლოთ გამოწერა მეტი AI დიაგნოსტიკისთვის.',
      );
    }
    if (res.status != 200) {
      throw Exception('Diagnostic proxy error (${res.status}): ${res.data}');
    }

    if (res.data is Map && res.data['text'] != null) {
      return res.data['text'].toString();
    }
    if (res.data is String) {
      final decoded = jsonDecode(res.data as String);
      if (decoded is Map && decoded['text'] != null) {
        return decoded['text'].toString();
      }
    }
    return '';
  }

  /// Evaluates limits on the server, feeds the dynamic context, and returns an AI diagnosis.
  Future<String> generateDiagnosis(
    String userMessage,
    Map<String, dynamic> carProfile, {
    List<dynamic> chatHistory = const [],
    bool useHeavyLogic = false,
    String? userCountry,
  }) async {
    final stream = generateDiagnosisStream(
      userMessage,
      carProfile,
      chatHistory: chatHistory,
      useHeavyLogic: useHeavyLogic,
      userCountry: userCountry,
    );
    final buffer = StringBuffer();
    await for (final chunk in stream) {
      buffer.write(chunk);
    }
    return buffer.toString();
  }

  /// Yields an AI diagnosis response routed through the `ai-proxy` Edge Function.
  Stream<String> generateDiagnosisStream(
    String userMessage,
    Map<String, dynamic> carProfile, {
    List<dynamic> chatHistory = const [],
    bool useHeavyLogic = false,
    String? userCountry,
  }) async* {
    final userId = _supabaseClient.auth.currentUser?.id;
    final selectedModelName = useHeavyLogic ? proModel : liteModel;
    final systemPrompt = _buildSystemPrompt(
      carProfile: carProfile,
      userCountry: userCountry,
    );

    final brand = carProfile['brand'] ?? carProfile['make'] ?? 'Unknown';
    final modelString = carProfile['model'] ?? 'Unknown';
    final year = carProfile['year'] ?? 'Unknown';
    final mileage = carProfile['mileage'] ?? 'Unknown';

    final chronicIssues =
        await _insightsService.fetchChronicIssues(brand.toString(), modelString.toString());
    final insightsContext = chronicIssues.isNotEmpty
        ? '\n\nCrowd-Sourced Chronic Issues for $brand $modelString:\n${chronicIssues.join('\n')}'
        : '';

    if (_sessionTranscript.isEmpty && chatHistory.isNotEmpty) {
      for (final msg in chatHistory) {
        try {
          final text = (msg as dynamic).text as String;
          final isUser = (msg as dynamic).isUser as bool;
          _sessionTranscript.add('${isUser ? "User" : "Assistant"}: $text');
        } catch (_) {}
      }
    }

    final historyBlock = _sessionTranscript.isNotEmpty
        ? 'Conversation History:\n${_sessionTranscript.skipMax(10).join('\n')}\n\n'
        : '';

    final contextualPrompt = '''
[Context: Vehicle is a $year $brand $modelString with $mileage miles.$insightsContext]

$historyBlock
User Message:
$userMessage
''';

    try {
      final responseText = await _invokeAiProxy(
        model: selectedModelName,
        prompt: contextualPrompt,
        systemInstruction: systemPrompt,
      );

      _sessionTranscript.add('User: $userMessage');
      _sessionTranscript.add('Assistant: $responseText');

      if (responseText.isNotEmpty) {
        yield responseText;
      }

      // Check if user explicitly asked for local part prices
      final lower = userMessage.toLowerCase();
      if (lower.contains('ფას') || lower.contains('price') || lower.contains('ნაწილ')) {
        try {
          final prices = await PartsFinderService.getPricesForPart(
            userMessage,
            brand.toString(),
            modelString.toString(),
          );
          if (prices.isNotEmpty) {
            final table = PartsFinderService.formatAsMarkdown(
              prices,
              userMessage,
              brand.toString(),
              modelString.toString(),
            );
            yield '\n\n$table';
          }
        } catch (_) {}
      }

      if (userId != null) {
        await _logToChatHistory(
          userId,
          carProfile['id']?.toString(),
          userMessage,
          responseText,
          selectedModelName,
        );
      }
    } catch (e) {
      throw Exception('Diagnostic Engine Exception: $e');
    }
  }

  /// Evaluates multimodal inputs (image or audio) securely via the `ai-proxy` Edge Function.
  Future<String> analyzeMultimedia({
    String? imageUrl,
    String? audioUrl,
    String? userContext,
    required Map<String, dynamic> carProfile,
  }) async {
    final systemPrompt = _buildSystemPrompt(carProfile: carProfile);
    final prompt = userContext != null && userContext.isNotEmpty
        ? "User says: '$userContext'. Analyze this multimedia considering the context and the car profile."
        : 'Analyze this multimedia for any visible or audible car issues based on the car profile.';

    final mediaParts = <Map<String, String>>[];

    if (imageUrl != null) {
      try {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          mediaParts.add({
            'mimeType': 'image/jpeg',
            'dataBase64': base64Encode(response.bodyBytes),
          });
        }
      } catch (e) {
        debugPrint('Failed to load image: $e');
      }
    }

    if (audioUrl != null) {
      try {
        final response = await http.get(Uri.parse(audioUrl));
        if (response.statusCode == 200) {
          mediaParts.add({
            'mimeType': 'audio/mp4',
            'dataBase64': base64Encode(response.bodyBytes),
          });
        }
      } catch (e) {
        debugPrint('Failed to load audio: $e');
      }
    }

    try {
      final text = await _invokeAiProxy(
        model: proModel,
        prompt: prompt,
        systemInstruction: systemPrompt,
        mediaParts: mediaParts,
      );
      return text.isNotEmpty ? text : 'I could not analyze the media properly.';
    } catch (e) {
      throw Exception('Multimedia Analysis Exception: $e');
    }
  }

  Future<void> _logToChatHistory(
    String userId,
    String? garageId,
    String message,
    String response,
    String modelUsed,
  ) async {
    if (garageId == null) return;
    try {
      await _supabaseClient.from('chat_history').insert({
        'user_id': userId,
        'garage_id': garageId,
        'message': message,
        'response': response,
        'model_used': modelUsed,
      });
    } catch (e) {
      debugPrint('Failed to log chat history: $e');
    }
  }

  Future<String> analyzeObdCodes(
    List<String> codes,
    Map<String, dynamic> carProfile,
  ) async {
    final systemPrompt = _buildSystemPrompt(carProfile: carProfile);
    final prompt =
        'I have the following OBD-II fault codes: ${codes.join(', ')}. Please analyze them in the context of my vehicle and provide a detailed diagnostic report, including potential causes and recommended fixes.';

    try {
      final text = await _invokeAiProxy(
        model: proModel,
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      return text.isNotEmpty ? text : 'Unable to analyze OBD codes at this time.';
    } catch (e) {
      throw Exception('OBD Analysis Exception: $e');
    }
  }

  Future<String> estimateRepairCost(Map<String, dynamic> carProfile) async {
    final systemPrompt = _buildSystemPrompt(carProfile: carProfile);
    final prompt =
        'Based on our recent diagnostic conversation, please provide a detailed estimated repair cost breakdown for the recommended fixes. Include average parts costs and estimated labor hours.';

    try {
      final text = await _invokeAiProxy(
        model: proModel,
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      return text.isNotEmpty ? text : 'Unable to generate repair cost estimate.';
    } catch (e) {
      throw Exception('Repair Cost Estimate Exception: $e');
    }
  }

  Future<String> generateDiyGuide(Map<String, dynamic> carProfile) async {
    final systemPrompt = _buildSystemPrompt(carProfile: carProfile);
    final prompt =
        'Based on our recent diagnostic conversation, please generate a step-by-step DIY repair guide for the most critical issue. Include required tools, safety warnings, and detailed instructions.';

    try {
      final text = await _invokeAiProxy(
        model: proModel,
        prompt: prompt,
        systemInstruction: systemPrompt,
      );
      return text.isNotEmpty ? text : 'Unable to generate DIY guide.';
    } catch (e) {
      throw Exception('DIY Guide Generation Exception: $e');
    }
  }

  /// Clears the active chat session memory.
  void clearSession() {
    _sessionTranscript.clear();
  }
}

extension _ListTailExt<T> on List<T> {
  Iterable<T> skipMax(int maxCount) =>
      length <= maxCount ? this : skip(length - maxCount);
}
