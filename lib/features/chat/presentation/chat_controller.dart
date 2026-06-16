import 'package:flutter/foundation.dart';
import '../../../data/gemini_diagnostic_service.dart';

/// Represents a suggested replacement part with mock local and international pricing.
class SuggestedPart {
  final String partName;
  final double localPriceGEL;
  final double internationalPriceUSD;
  final String localSupplier;
  final String internationalSupplier;

  SuggestedPart({
    required this.partName,
    required this.localPriceGEL,
    required this.internationalPriceUSD,
    required this.localSupplier,
    required this.internationalSupplier,
  });
}

/// Represents a single message in the chat feed
class ChatMessage {
  final String role; // e.g., 'User', 'AI', 'System'
  final String text;

  ChatMessage({required this.role, required this.text});
}

/// The main state controller for the diagnostic chat screen.
class ChatController extends ChangeNotifier {
  final GeminiDiagnosticService _diagnosticService;
  
  bool _isLoading = false;
  bool get isLoading => _isLoading;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  final List<SuggestedPart> _detectedParts = [];
  List<SuggestedPart> get detectedParts => List.unmodifiable(_detectedParts);

  ChatController({GeminiDiagnosticService? diagnosticService})
      : _diagnosticService = diagnosticService ?? GeminiDiagnosticService();

  /// Sends a user message to the diagnostic engine and processes the AI's response.
  Future<void> sendMessage(String text, Map<String, dynamic> carProfile) async {
    if (text.trim().isEmpty) return;

    _messages.add(ChatMessage(role: 'User', text: text));
    _isLoading = true;
    notifyListeners();

    try {
      final aiResponse = await _diagnosticService.generateDiagnosis(text, carProfile);
      _messages.add(ChatMessage(role: 'AI', text: aiResponse));
      
      // Extract parts and mock pricing for the UI
      _extractAndMockPrices(aiResponse);
      
    } catch (e) {
      _messages.add(ChatMessage(role: 'System', text: 'Error: ${e.toString()}'));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears the chat history and resets the AI session context.
  void clearChat() {
    _messages.clear();
    _detectedParts.clear();
    _diagnosticService.clearSession();
    notifyListeners();
  }

  /// Mock utility to detect if AI mentioned certain parts and generate pricing maps
  void _extractAndMockPrices(String aiResponse) {
    _detectedParts.clear();
    final lowerResponse = aiResponse.toLowerCase();

    // A mock database of common components mapped to local vs international pricing
    final mockDatabase = <String, SuggestedPart>{
      'ignition coil': SuggestedPart(
        partName: 'Ignition Coil',
        localPriceGEL: 120.0,
        internationalPriceUSD: 25.0,
        localSupplier: 'MyParts.ge',
        internationalSupplier: 'Amazon',
      ),
      'abs sensor': SuggestedPart(
        partName: 'ABS Speed Sensor',
        localPriceGEL: 85.0,
        internationalPriceUSD: 15.0,
        localSupplier: 'Tegeta Motors',
        internationalSupplier: 'AliExpress',
      ),
      'spark plug': SuggestedPart(
        partName: 'Spark Plugs (Set of 4)',
        localPriceGEL: 150.0,
        internationalPriceUSD: 35.0,
        localSupplier: 'Eliava Market',
        internationalSupplier: 'eBay',
      ),
      'water pump': SuggestedPart(
        partName: 'Engine Water Pump',
        localPriceGEL: 250.0,
        internationalPriceUSD: 60.0,
        localSupplier: 'AutoBaza',
        internationalSupplier: 'Amazon',
      ),
      'gearbox sensor': SuggestedPart(
        partName: 'Transmission Sensor',
        localPriceGEL: 300.0,
        internationalPriceUSD: 80.0,
        localSupplier: 'MyParts.ge',
        internationalSupplier: 'AliExpress',
      ),
    };

    // Scan response text and append detected parts to UI state
    mockDatabase.forEach((keyword, partInfo) {
      if (lowerResponse.contains(keyword)) {
        _detectedParts.add(partInfo);
      }
    });
  }
}
