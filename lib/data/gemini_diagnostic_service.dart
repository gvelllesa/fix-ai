import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../core/config/env_config.dart';
import 'supabase_client.dart';
import 'forum_insights_service.dart';
import '../core/services/parts_finder_service.dart';

/// Core diagnostic engine utilizing Gemini Pro.
/// Maintains conversational state via ChatSession.
class GeminiDiagnosticService {
  static const String liteModel = 'models/gemini-3.1-flash-lite';
  static const String proModel = 'models/gemini-3.1-flash-lite';

  final SupabaseClient _supabaseClient;
  final ForumInsightsService _insightsService;
  
  // Stateful chat session memory
  ChatSession? _chatSession;
  String? _currentSessionModelName;

  GeminiDiagnosticService({
    SupabaseClient? supabaseClient,
    ForumInsightsService? insightsService,
  })  : _supabaseClient = supabaseClient ?? SupabaseClientManager().client,
        _insightsService = insightsService ?? ForumInsightsService(supabaseClient: supabaseClient ?? SupabaseClientManager().client);

  GenerativeModel _createModel(String modelName, {Map<String, dynamic>? carProfile, String? userCountry}) {
    String countryText = userCountry != null && userCountry != 'Unknown' 
      ? "\\nThe user is currently located in \$userCountry. When they ask to find a car part, you must prioritize and return search links from the most popular local automotive marketplaces in \$userCountry."
      : "";

    String basePrompt = '''You are FIX AI, a premium diagnostic assistant. Always respond STRICTLY in the exact same language the user used in their current prompt. Do not mix languages within a single response.\$countryText

When you successfully identify a likely mechanical issue and recommend replacing a specific part (e.g., 'Spark Plugs', 'VANOS Solenoid'), you MUST seamlessly offer to find the part for the user at the end of your message.

CRITICAL PART NAMING RULE:
Before diagnosing a specific part or recommending a replacement, you MUST call the `search_standard_part` tool with a generic English or Russian name for the part to find the exact standardized name from our local database. Once the tool returns the exact standardized string, you MUST use that exact string in your diagnostic report. Do not guess part names.

After you diagnose an issue and use `search_standard_part` to get the correct part name, you MUST ask the user if they want you to check local prices and availability for that part. If they say yes, execute the `find_part_prices` tool and display the results to the user as a beautiful Markdown table with clickable links.

Behavior Rules:
- Do not ask for parts immediately. First, provide the diagnosis using the standardized part names.
- End your diagnostic message with a friendly, natural question like: "გსურთ, მოგიძებნოთ ეს ნაწილი (მაგალითად: აალების სანთლები) და შევადაროთ ფასები ადგილობრივ ბაზარზე?"
- If the user agrees, ask for their VIN code ONLY if it is not already provided in the carProfile. Mention that the VIN is needed for exact compatibility.
- If the user agrees and you have the VIN, trigger the 'find_part_prices' function.''';

    String systemPrompt = basePrompt;
    
    if (carProfile != null) {
      final make = carProfile['make'] ?? carProfile['brand'] ?? 'Unknown Make';
      final modelStr = carProfile['model'] ?? 'Unknown Model';
      final year = carProfile['year']?.toString() ?? 'Unknown Year';
      final engine = carProfile['engine_type'] ?? carProfile['engine'] ?? 'Unknown Engine';
      final vin = carProfile['vin'] ?? 'Not provided';

      systemPrompt = "The user is asking about their \$year \$make \$modelStr with engine code \$engine. VIN: \$vin. Provide highly specific advice for this exact vehicle. Do not ask them what car they have unless asking for the VIN for part compatibility when it is 'Not provided'.\\n\\n\$basePrompt";
    }

    final searchAutoPartsTool = Tool(
      functionDeclarations: [
        FunctionDeclaration(
          'search_standard_part',
          'Searches the local database for the standardized name of an automotive part. ALWAYS use this before naming a part in your response.',
          Schema(
            SchemaType.object,
            properties: {
              'query': Schema(SchemaType.string, description: 'The generic name of the part to search for (e.g., "spark plug", "свечи зажигания", "масляный фильтр")'),
            },
            requiredProperties: ['query'],
          ),
        ),
        FunctionDeclaration(
          'find_part_prices',
          'Finds local prices and market links for a standardized part.',
          Schema(
            SchemaType.object,
            properties: {
              'standard_part_name': Schema(SchemaType.string, description: 'The exact standardized name returned by search_standard_part.'),
              'car_make': Schema(SchemaType.string, description: 'The make of the car.'),
              'car_model': Schema(SchemaType.string, description: 'The model of the car.'),
            },
            requiredProperties: ['standard_part_name', 'car_make', 'car_model'],
          ),
        ),
      ],
    );

    return GenerativeModel(
      model: modelName,
      apiKey: EnvConfig.geminiApiKey,
      systemInstruction: Content.system(systemPrompt),
      tools: [searchAutoPartsTool],
    );
  }

  /// Evaluates limits, feeds the dynamic context, and yields a stateful AI diagnosis.
  Future<String> generateDiagnosis(
    String userMessage, 
    Map<String, dynamic> carProfile, 
    {List<dynamic> chatHistory = const [], bool useHeavyLogic = false, String? userCountry}
  ) async {
    final stream = generateDiagnosisStream(
      userMessage,
      carProfile,
      chatHistory: chatHistory,
      useHeavyLogic: useHeavyLogic,
      userCountry: userCountry,
    );
    String result = '';
    await for (final chunk in stream) {
      result += chunk;
    }
    return result;
  }

  /// Evaluates limits, feeds the dynamic context, and yields a stateful AI diagnosis stream.
  Stream<String> generateDiagnosisStream(
    String userMessage, 
    Map<String, dynamic> carProfile, 
    {List<dynamic> chatHistory = const [], bool useHeavyLogic = false, String? userCountry}
  ) async* {
    final userId = _supabaseClient.auth.currentUser?.id;
    
    if (userId != null) {
      await _enforceTierLimits(userId);
    }

    final selectedModelName = useHeavyLogic ? proModel : liteModel;
    final model = _createModel(selectedModelName, carProfile: carProfile, userCountry: userCountry);

    if (_chatSession == null) {
      final List<Content> contentHistory = [];
      for (var msg in chatHistory) {
        final text = msg.text as String;
        final isUser = msg.isUser as bool;
        if (isUser) {
          contentHistory.add(Content.text(text));
        } else {
          contentHistory.add(Content.model([TextPart(text)]));
        }
      }
      _chatSession = model.startChat(history: contentHistory);
      _currentSessionModelName = selectedModelName;
    } else if (_currentSessionModelName != selectedModelName) {
      _chatSession = model.startChat(history: _chatSession!.history.toList());
      _currentSessionModelName = selectedModelName;
    }

    final brand = carProfile['brand'] ?? carProfile['make'] ?? 'Unknown';
    final modelString = carProfile['model'] ?? 'Unknown';
    final year = carProfile['year'] ?? 'Unknown';
    final mileage = carProfile['mileage'] ?? 'Unknown';

    final chronicIssues = await _insightsService.fetchChronicIssues(brand, modelString);
    final insightsContext = chronicIssues.isNotEmpty
        ? "\\n\\nCrowd-Sourced Chronic Issues for \$brand \$modelString:\\n\${chronicIssues.join('\\n')}"
        : "";

    final contextualPrompt = '''
[Context: Vehicle is a \$year \$brand \$modelString with \$mileage miles.\$insightsContext]

User Message:
\$userMessage
''';

    try {
      var responseStream = _chatSession!.sendMessageStream(Content.text(contextualPrompt));
      String fullResponse = '';
      
      await for (final chunk in responseStream) {
        final text = chunk.text ?? '';
        if (text.isNotEmpty) {
          fullResponse += text;
          yield text;
        }
        
        if (chunk.functionCalls != null && chunk.functionCalls.isNotEmpty) {
          for (final call in chunk.functionCalls) {
            if (call.name == 'find_part_prices') {
              final standardPartName = call.args['standard_part_name']?.toString() ?? 'the requested part';
              final carMake = call.args['car_make']?.toString() ?? brand;
              final carModel = call.args['car_model']?.toString() ?? modelString;
              
              final priceResults = await PartsFinderService.getPricesForPart(standardPartName, carMake, carModel);
              final pricesMarkdown = PartsFinderService.formatAsMarkdown(priceResults, standardPartName, carMake, carModel);
              
              final functionResponseContent = Content.functionResponse(
                'find_part_prices', 
                {'markdown_table': pricesMarkdown}
              );
              
              final continuationStream = _chatSession!.sendMessageStream(functionResponseContent);
              await for (final contChunk in continuationStream) {
                final contText = contChunk.text ?? '';
                if (contText.isNotEmpty) {
                  fullResponse += contText;
                  yield contText;
                }
              }
            } else if (call.name == 'search_standard_part') {
              final query = call.args['query']?.toString() ?? '';
              List<String> matches = [];
              if (query.isNotEmpty) {
                try {
                  final response = await _supabaseClient
                      .from('car_parts')
                      .select('name')
                      .or('name.ilike.%\$query%,slug.ilike.%\$query%')
                      .limit(5);
                  matches = (response as List).map((e) => e['name'] as String).toList();
                } catch (e) {
                  debugPrint('Supabase search error: \$e');
                }
              }
              
              final functionResponseContent = Content.functionResponse(
                'search_standard_part', 
                {'matches': matches.isNotEmpty ? matches : ['Part not found in standard DB']}
              );
              
              final continuationStream = _chatSession!.sendMessageStream(functionResponseContent);
              await for (final contChunk in continuationStream) {
                final contText = contChunk.text ?? '';
                if (contText.isNotEmpty) {
                  fullResponse += contText;
                  yield contText;
                }
              }
            }
          }
        }
      }
      
      if (userId != null) {
        await _logToChatHistory(userId, carProfile['id'], userMessage, fullResponse, selectedModelName);
      }
      
    } catch (e) {
      throw Exception('Diagnostic Engine Exception: \$e');
    }
  }

  /// Evaluates multimodal inputs (image or audio) securely using Gemini's native capabilities.
  Future<String> analyzeMultimedia({
    String? imageUrl, 
    String? audioUrl, 
    String? userContext,
    required Map<String, dynamic> carProfile,
  }) async {
    final model = _createModel(proModel, carProfile: carProfile);
    
    final prompt = userContext != null && userContext.isNotEmpty 
      ? "User says: '\$userContext'. Analyze this multimedia considering the context and the car profile." 
      : "Analyze this multimedia for any visible or audible car issues based on the car profile.";

    final List<Part> parts = [TextPart(prompt)];

    if (imageUrl != null) {
      try {
        final response = await http.get(Uri.parse(imageUrl));
        if (response.statusCode == 200) {
          parts.add(DataPart('image/jpeg', response.bodyBytes));
        }
      } catch (e) {
        debugPrint('Failed to load image: \$e');
      }
    }

    if (audioUrl != null) {
      try {
        final response = await http.get(Uri.parse(audioUrl));
        if (response.statusCode == 200) {
          parts.add(DataPart('audio/mp4', response.bodyBytes));
        }
      } catch (e) {
        debugPrint('Failed to load audio: \$e');
      }
    }

    try {
      final response = await model.generateContent([Content.multi(parts)]);
      return response.text ?? 'I could not analyze the media properly.';
    } catch (e) {
      throw Exception('Multimedia Analysis Exception: \$e');
    }
  }

  Future<void> _enforceTierLimits(String userId) async {
    final response = await _supabaseClient
        .from('users')
        .select('subscription_tier, current_period_usage')
        .eq('id', userId)
        .single();
        
    final tier = response['subscription_tier'];
    final usage = response['current_period_usage'] ?? 0;

    int maxUsage = 20; // FREE
    if (tier == 'PRO') maxUsage = 150;
    if (tier == 'EXPERT') maxUsage = 500;

    if (usage >= maxUsage) {
      throw Exception('You have reached the limit of your \$tier tier. Please upgrade your subscription for more AI diagnostics.');
    }
    
    await _supabaseClient.rpc('increment_usage', params: {'user_id_param': userId});
  }
  
  Future<void> _logToChatHistory(String userId, String? garageId, String message, String response, String modelUsed) async {
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
      debugPrint('Failed to log chat history: \$e');
    }
  }
  Future<String> analyzeObdCodes(List<String> codes, Map<String, dynamic> carProfile) async {
    final model = _createModel(proModel, carProfile: carProfile);
    final prompt = "I have the following OBD-II fault codes: ${codes.join(', ')}. Please analyze them in the context of my vehicle and provide a detailed diagnostic report, including potential causes and recommended fixes.";
    
    try {
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? 'Unable to analyze OBD codes at this time.';
    } catch (e) {
      throw Exception('OBD Analysis Exception: \$e');
    }
  }

  Future<String> estimateRepairCost(Map<String, dynamic> carProfile) async {
    final model = _createModel(proModel, carProfile: carProfile);
    final prompt = "Based on our recent diagnostic conversation, please provide a detailed estimated repair cost breakdown for the recommended fixes. Include average parts costs and estimated labor hours.";
    
    try {
      if (_chatSession != null) {
        final response = await _chatSession!.sendMessage(Content.text(prompt));
        return response.text ?? 'Unable to generate repair cost estimate.';
      } else {
        final response = await model.generateContent([Content.text(prompt)]);
        return response.text ?? 'Unable to generate repair cost estimate.';
      }
    } catch (e) {
      throw Exception('Repair Cost Estimate Exception: \$e');
    }
  }

  Future<String> generateDiyGuide(Map<String, dynamic> carProfile) async {
    final model = _createModel(proModel, carProfile: carProfile);
    final prompt = "Based on our recent diagnostic conversation, please generate a step-by-step DIY repair guide for the most critical issue. Include required tools, safety warnings, and detailed instructions.";
    
    try {
      if (_chatSession != null) {
        final response = await _chatSession!.sendMessage(Content.text(prompt));
        return response.text ?? 'Unable to generate DIY guide.';
      } else {
        final response = await model.generateContent([Content.text(prompt)]);
        return response.text ?? 'Unable to generate DIY guide.';
      }
    } catch (e) {
      throw Exception('DIY Guide Generation Exception: \$e');
    }
  }
}
