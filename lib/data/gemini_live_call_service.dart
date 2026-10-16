import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../core/config/feature_flags.dart';
import 'supabase_client.dart';

/// Isolated service for handling low-latency, bi-directional audio
/// via an ephemeral session negotiated by the `ai-proxy` Edge Function.
/// Raw `GEMINI_API_KEY` values are never placed in client URLs.
class GeminiLiveCallService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;

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

  /// Requests an ephemeral WebSocket session URL from the server-side `ai-proxy`
  /// Edge Function. Gated by [FeatureFlags.kLiveVoiceCallEnabled].
  Future<void> connect() async {
    if (!FeatureFlags.kLiveVoiceCallEnabled) {
      onError?.call(
        'Live Voice Call დროებით გამორთულია უსაფრთხოების მიზნით (საჭიროებს სერვერულ ეფემერულ სესიას).',
      );
      onCallEnded?.call();
      return;
    }

    try {
      final client = SupabaseClientManager().client;
      final res = await client.functions.invoke(
        'ai-proxy',
        body: {'action': 'live_voice_session'},
      );
      if (res.status != 200 || res.data is! Map || res.data['wsUrl'] == null) {
        onError?.call('Failed to obtain ephemeral voice session from server.');
        onCallEnded?.call();
        return;
      }

      final uri = Uri.parse(res.data['wsUrl'].toString());
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

      _sendSetupMessage();
    } catch (e) {
      onError?.call('Failed to initialize WebSocket: $e');
    }
  }

  void _sendSetupMessage() {
    final setupMessage = {
      'setup': {
        'model': 'models/gemini-2.0-flash-exp',
        'generationConfig': {
          'responseModalities': ['AUDIO'],
        },
        'systemInstruction': {
          'parts': [
            {
              'text':
                  'You are an advanced AI Car Diagnostics engine operating via hands-free live voice. '
                  'Keep responses brief, conversational, and direct.',
            },
          ],
        },
      },
    };

    _channel?.sink.add(jsonEncode(setupMessage));
  }

  void sendAudioChunk(Uint8List pcmBytes) {
    if (_channel == null) return;

    final base64Audio = base64Encode(pcmBytes);
    final audioMessage = {
      'realtimeInput': {
        'mediaChunks': [
          {
            'mimeType': 'audio/pcm;rate=16000',
            'data': base64Audio,
          },
        ],
      },
    };

    _channel!.sink.add(jsonEncode(audioMessage));
  }

  void _handleServerMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);

      if (data.containsKey('serverContent')) {
        final serverContent = data['serverContent'];
        final modelTurn = serverContent['modelTurn'];

        if (modelTurn != null && modelTurn['parts'] != null) {
          for (final part in modelTurn['parts']) {
            if (part['inlineData'] != null &&
                part['inlineData']['mimeType'].toString().startsWith('audio/')) {
              final base64Audio = part['inlineData']['data'] as String;
              final audioBytes = base64Decode(base64Audio);
              onAudioReceived?.call(audioBytes);
            }
            if (part['text'] != null) {
              onTextReceived?.call(part['text'].toString());
            }
          }
        }
      }
    } catch (e) {
      onError?.call('Failed to parse incoming WebSocket message: $e');
    }
  }

  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await _channel?.sink.close();
    _channel = null;
  }
}
