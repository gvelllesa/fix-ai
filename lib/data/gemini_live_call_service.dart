import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/config/env_config.dart';

/// An isolated service for handling low-latency, bi-directional audio 
/// via the Gemini Multimodal Live API endpoint.
class GeminiLiveCallService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  
  // Callbacks for the Presentation Layer to handle audio playback and UI states
  final void Function(Uint8List audioBytes)? onAudioReceived;
  final void Function(String text)? onTextReceived;
  final void Function()? onCallEnded;
  final void Function(String error)? onError;

  GeminiLiveCallService({
    this.onAudioReceived,
    this.onTextReceived,
    this.onCallEnded,
    this.onError,
  });

  /// Establishes the WebSocket connection and pushes the system setup payload.
  Future<void> connect() async {
    try {
      final apiKey = EnvConfig.geminiApiKey;
      // Target the BidiGenerateContent endpoint explicitly for Live Voice API
      final uri = Uri.parse(
          'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$apiKey');

      _channel = WebSocketChannel.connect(uri);

      _subscription = _channel!.stream.listen(
        _handleServerMessage,
        onError: (error) {
          onError?.call('WebSocket stream error: $error');
          disconnect();
        },
        onDone: () {
          onCallEnded?.call();
          disconnect();
        },
      );

      // Immediately configure the Live session with our Diagnostic System Instruction
      _sendSetupMessage();
    } catch (e) {
      onError?.call('Failed to initialize WebSocket: $e');
    }
  }

  /// Sends the initial configuration payload to mold the AI into the Master Mechanic.
  void _sendSetupMessage() {
    final setupMessage = {
      "setup": {
        // gemini-2.0-flash-exp (or equivalent v1alpha models) supports bidirectional audio
        "model": "models/gemini-2.0-flash-exp", 
        "generationConfig": {
          "responseModalities": ["AUDIO"]
        },
        "systemInstruction": {
          "parts": [
            {
              "text": "You are an advanced AI Car Diagnostics engine operating via hands-free live voice. "
                      "Role 1: OEM Brand-Specific Engineer. Adapt automatically to the vehicle's specific brand. "
                      "Role 2: Diagnostic Detective. Deduce root causes and ask targeted follow-up questions. "
                      "Role 3: Financial & Urgency Advisor. State if issues are immediate safety hazards. "
                      "Role 4: Human-to-Mechanic Translator. Explain in simple terms. "
                      "CRITICAL: Since this is a live audio call, keep responses brief, conversational, and direct."
            }
          ]
        }
      }
    };

    _channel?.sink.add(jsonEncode(setupMessage));
  }

  /// Pipes raw PCM audio chunks from the local device microphone into the Live API.
  /// Note: The Gemini API typically expects 16kHz, 16-bit PCM audio.
  void sendAudioChunk(Uint8List pcmBytes) {
    if (_channel == null) return;

    final base64Audio = base64Encode(pcmBytes);
    final audioMessage = {
      "realtimeInput": {
        "mediaChunks": [
          {
            "mimeType": "audio/pcm;rate=16000",
            "data": base64Audio,
          }
        ]
      }
    };

    _channel!.sink.add(jsonEncode(audioMessage));
  }

  /// Parses incoming binary/JSON streams from Gemini and routes the raw PCM bytes
  /// to the UI for immediate speaker playback.
  void _handleServerMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);

      if (data.containsKey('serverContent')) {
        final serverContent = data['serverContent'];
        final modelTurn = serverContent['modelTurn'];
        
        if (modelTurn != null && modelTurn['parts'] != null) {
          for (var part in modelTurn['parts']) {
            // Intercept Audio Bytes sent from the AI
            if (part['inlineData'] != null && part['inlineData']['mimeType'].startsWith('audio/')) {
              final base64Audio = part['inlineData']['data'];
              final audioBytes = base64Decode(base64Audio);
              onAudioReceived?.call(audioBytes);
            }
            // Intercept Text Transcription of the AI's audio (useful for screen captions)
            if (part['text'] != null) {
              onTextReceived?.call(part['text']);
            }
          }
        }
      }
    } catch (e) {
      onError?.call('Failed to parse incoming WebSocket message: $e');
    }
  }

  /// Terminates the socket gracefully.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
