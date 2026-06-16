import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/gemini_gatekeeper_service.dart';
import '../../../data/gemini_diagnostic_service.dart';
import '../../../data/obd_data_processor.dart';
import '../../../core/services/location_service.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> quickReplies;
  
  ChatMessage({required this.text, required this.isUser, this.quickReplies = const []});
}

class ChatController extends ChangeNotifier {
  final GeminiGatekeeperService _gatekeeperService = GeminiGatekeeperService();
  final GeminiDiagnosticService _diagnosticService = GeminiDiagnosticService();
  GeminiDiagnosticService get diagnosticService => _diagnosticService;
  final ObdDataProcessor _obdProcessor = ObdDataProcessor();

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isSessionComplete = false;
  bool get isSessionComplete => _isSessionComplete;

  void completeSession() {
    _isSessionComplete = true;
    notifyListeners();
  }

  void postSystemMessage(String text) {
    _messages.add(ChatMessage(text: text, isUser: false));
    notifyListeners();
  }

  ChatMessage _parseAiResponse(String rawResponse) {
    if (rawResponse.contains('[QUICK_REPLIES]')) {
      final parts = rawResponse.split('[QUICK_REPLIES]');
      final mainText = parts[0].trim();
      final quickRepliesString = parts.length > 1 ? parts[1].trim() : '';
      
      final quickReplies = quickRepliesString
          .split('|')
          .map((s) => s.replaceAll(RegExp(r'[\[\]]'), '').trim())
          .where((s) => s.isNotEmpty)
          .toList();
          
      return ChatMessage(text: mainText, isUser: false, quickReplies: quickReplies);
    }
    return ChatMessage(text: rawResponse, isUser: false);
  }

  Future<void> loadHistoryForVehicle(String vehicleId) async {
    final regExp = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
    );
    if (!regExp.hasMatch(vehicleId)) {
      debugPrint('Skipping loadHistoryForVehicle: invalid UUID $vehicleId');
      return;
    }

    _isLoading = true;
    _messages.clear();
    notifyListeners();

    try {
      final response = await Supabase.instance.client
          .from('chat_history')
          .select('messages')
          .eq('car_profile_id', vehicleId)
          .order('created_at', ascending: true);

      final List<ChatMessage> loadedMessages = [];
      for (var row in response) {
        final messagesList = row['messages'] as List<dynamic>?;
        if (messagesList != null) {
          for (var msg in messagesList) {
            final role = msg['role']?.toString();
            final content = msg['content']?.toString() ?? '';
            final isUser = role == 'user';
            loadedMessages.add(ChatMessage(text: content, isUser: isUser));
          }
        }
      }
      _messages.addAll(loadedMessages);
    } catch (e) {
      debugPrint('Error loading chat history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text, Map<String, dynamic> carProfile, {void Function(String)? onError}) async {
    if (text.trim().isEmpty) return;

    // Add user message
    _messages.add(ChatMessage(text: text, isUser: true));
    _isLoading = true;
    notifyListeners();

    try {
      final isRelevant = await _gatekeeperService.isQueryRelevant(text);
      final historyList = _messages.sublist(0, _messages.length - 1);
      
      if (isRelevant) {
        final userCountry = await LocationService().fetchUserCountry();
        final stream = _diagnosticService.generateDiagnosisStream(
          text, 
          carProfile, 
          chatHistory: historyList,
          userCountry: userCountry,
        );
        
        bool isFirstChunk = true;
        
        await for (final chunk in stream) {
            if (isFirstChunk) {
                _isLoading = false;
                _messages.add(ChatMessage(text: chunk, isUser: false));
                isFirstChunk = false;
            } else {
                _messages.last = _parseAiResponse(_messages.last.text + chunk);
            }
            notifyListeners();
        }
        
        // Mark session as complete after receiving a diagnostic response
        _isSessionComplete = true;
      } else {
        final rejectionPrompt = "SYSTEM DIRECTIVE: The following user input is NOT car-related. Ignore all previous rules and do not output a technical note. Politely tell the user in the EXACT SAME LANGUAGE AND SCRIPT they used that you can only answer automotive diagnostics questions.\n\nUser Input: $text";
        final stream = _diagnosticService.generateDiagnosisStream(
          rejectionPrompt, 
          carProfile,
          chatHistory: historyList,
        );
        
        bool isFirstChunk = true;
        await for (final chunk in stream) {
            if (isFirstChunk) {
                _isLoading = false;
                _messages.add(ChatMessage(text: chunk, isUser: false));
                isFirstChunk = false;
            } else {
                _messages.last = _parseAiResponse(_messages.last.text + chunk);
            }
            notifyListeners();
        }
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      
      String errorMsg = "Server overloaded or error occurred. Please try again.";
      final errorStr = e.toString();
      if (errorStr.contains("503") || errorStr.contains("GenerativeAIException") || errorStr.contains("Diagnostic Engine Exception")) {
         errorMsg = "AI Server overloaded or unavailable, please try again.";
      } else {
         errorMsg = errorStr;
      }
      
      if (onError != null) {
          onError(errorMsg);
      } else {
          _messages.add(ChatMessage(text: "Error: $errorMsg", isUser: false));
          notifyListeners();
      }
    } finally {
      if (_isLoading) {
          _isLoading = false;
          notifyListeners();
      }
    }
  }

  /// Extracts physical hardware codes from the ELM327 scanner and forces the AI 
  /// to run a diagnosis directly based on the vehicle's engine control module state.
  Future<void> attachObdDiagnosticToChat(Map<String, dynamic> carProfile, Map<String, dynamic> connectionPayload) async {
    final model = carProfile['model']?.toString() ?? 'Unknown';
    final interfaceType = connectionPayload['interface']?.toString() ?? 'Simulation';

    _isLoading = true;
    notifyListeners();

    try {
      // 1. Scan OBD-II Hardware using selected interface
      final codes = await _obdProcessor.scanAndExtractFaultCodes(model, interfaceType);
      final codesString = codes.join(', ');

      // 2. Inject System Mandate to UI
      final systemMessage = "SYSTEM: Hardware Scan Complete. Detected DTC Codes: $codesString. Initiating Gemini AI Analysis, Local Parts Pricing, and Predictive Risk Assessment...";
      _messages.add(ChatMessage(text: systemMessage, isUser: false));
      notifyListeners();

      // 3. Force Gemini AI to analyze these specific hardware codes using Heavy Logic
      final response = await _diagnosticService.analyzeObdCodes(codes, carProfile);
      
      // 4. Post AI Result and Complete Session
      _messages.add(_parseAiResponse(response));
      _isSessionComplete = true;

    } catch (e) {
      _messages.add(ChatMessage(text: "Hardware Scanner Error: ${e.toString()}", isUser: false));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> requestCostEstimate(Map<String, dynamic> carProfile) async {
    _isLoading = true;
    _messages.add(ChatMessage(text: "Requesting Live Cost & Parts Estimate...", isUser: true));
    notifyListeners();

    try {
      final response = await _diagnosticService.estimateRepairCost(carProfile);
      _messages.add(ChatMessage(text: "### Cost Estimate\n```json\n$response\n```", isUser: false));
    } catch (e) {
      _messages.add(ChatMessage(text: "Error getting estimate: $e", isUser: false));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> requestDiyGuide(Map<String, dynamic> carProfile) async {
    _isLoading = true;
    _messages.add(ChatMessage(text: "Requesting Step-by-Step DIY Guide...", isUser: true));
    notifyListeners();

    try {
      final response = await _diagnosticService.generateDiyGuide(carProfile);
      _messages.add(ChatMessage(text: response, isUser: false));
    } catch (e) {
      _messages.add(ChatMessage(text: "Error generating guide: $e", isUser: false));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _obdProcessor.dispose();
    super.dispose();
  }
}
