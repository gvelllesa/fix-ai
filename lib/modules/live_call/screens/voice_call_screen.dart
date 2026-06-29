import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/gemini_live_call_service.dart';

class VoiceCallScreen extends StatefulWidget {
  const VoiceCallScreen({Key? key}) : super(key: key);

  @override
  State<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends State<VoiceCallScreen>
    with WidgetsBindingObserver {
  bool _isConnected = false;
  String _currentAiTranscription = "Waiting for AI response...";

  late GeminiLiveCallService _geminiService;
  final _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordStreamSubscription;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    // 3.9 FIX: observe lifecycle so we suspend the mic stream on background.
    WidgetsBinding.instance.addObserver(this);


    _geminiService = GeminiLiveCallService(
      onAudioReceived: _handleAudioPlayback,
      onTextReceived: _updateSubtitles,
      onCallEnded: () => _endCall(),
      onError: (err) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call Error: $err')));
        }
      },
    );

    // Automatically trigger connection sequence upon screen load
    _connectCall();
  }

  void _connectCall() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission required')));
      }
      return;
    }

    // H3 FIX (audit): the Gemini Live WebSocket connect() has no built-in
    // timeout, so a dead endpoint would leave this await pending and the
    // screen spinning. Bound it explicitly.
    try {
      await _geminiService.connect()
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Call connection failed: $e')));
      }
      return;
    }

    // H3 FIX (audit): guard before setState. The awaited connect() can take
    // many seconds; if the user backed out (or the OS suspended the activity)
    // during that window, the widget is disposed and setState would throw
    // "setState() called after dispose()" — and crash the call flow in
    // release. The sibling _updateSubtitles already does this; this was an
    // oversight.
    if (!mounted) return;
    setState(() {
      _isConnected = true;
    });
    _startMicCapture();
  }

  void _startMicCapture() async {
    if (await _audioRecorder.hasPermission()) {
      final stream = await _audioRecorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      _recordStreamSubscription = stream.listen((data) {
        if (_isConnected) {
          _geminiService.sendAudioChunk(Uint8List.fromList(data));
        }
      });
    }
  }

  // M1 FIX (audit): this callback is typed `void Function(Uint8List)?` on the
  // service side, but declared `async` here and awaits _audioPlayer.play().
  // Returning a Future from a `void Function` drops it, so any throw inside
  // (malformed PCM in the hand-built WAV header, a decoder error) becomes an
  // unhandled async error in the root zone instead of routing through
  // onError. We now guard the await with try/catch and a mounted check so
  // playback failures after the screen is gone are swallowed cleanly.
  void _handleAudioPlayback(Uint8List audioBytes) async {
    if (!mounted) return;
    debugPrint('Received ${audioBytes.length} bytes of raw audio from AI');
    int sampleRate = 16000;
    int channels = 1;
    int byteRate = sampleRate * channels * 2;
    var header = ByteData(44);

    header.setUint8(0, 82); header.setUint8(1, 73); header.setUint8(2, 70); header.setUint8(3, 70);
    header.setUint32(4, 36 + audioBytes.length, Endian.little);
    header.setUint8(8, 87); header.setUint8(9, 65); header.setUint8(10, 86); header.setUint8(11, 69);
    header.setUint8(12, 102); header.setUint8(13, 109); header.setUint8(14, 116); header.setUint8(15, 32);
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, channels * 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    header.setUint8(36, 100); header.setUint8(37, 97); header.setUint8(38, 116); header.setUint8(39, 97);
    header.setUint32(40, audioBytes.length, Endian.little);

    var builder = BytesBuilder();
    builder.add(header.buffer.asUint8List());
    builder.add(audioBytes);

    try {
      await _audioPlayer.play(BytesSource(builder.toBytes()));
    } catch (e) {
      // Don't let a bad audio chunk crash the call — route it to the user.
      debugPrint('VoiceCallScreen: audio playback failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Audio playback error: $e')));
      }
    }
  }

  void _updateSubtitles(String text) {
    if (mounted) {
      setState(() {
        _currentAiTranscription = text;
      });
    }
  }

  void _endCall() {
    if (!_isConnected) return;
    setState(() {
      _isConnected = false;
      _currentAiTranscription = "Call Ended";
    });

    // Cancel the mic stream synchronously first so no more audio chunks are
    // piped into a service we are about to tear down.
    _recordStreamSubscription?.cancel();
    _recordStreamSubscription = null;
    // M2 FIX (audit): disconnect() is async (it awaits the WebSocket sink
    // close). Fire-and-forget but swallow errors so a teardown failure can't
    // surface as an uncaught async exception.
    unawaited(_geminiService.disconnect().catchError((Object e) {
      debugPrint('VoiceCallScreen: endCall disconnect error: $e');
    }));

    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  void dispose() {
    // 3.9 FIX: remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);
    _recordStreamSubscription?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    // M2 FIX (audit): disconnect() is async; capture the future and ignore
    // failures rather than letting an in-flight WebSocket close race the
    // widget teardown (which could otherwise invoke onAudioReceived against
    // a disposed player).
    unawaited(_geminiService.disconnect().catchError((Object e) {
      debugPrint('VoiceCallScreen: dispose disconnect error: $e');
    }));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 3.9 FIX: suspend the mic stream immediately when backgrounded — the OS
    // is about to suspend the WebSocket and any buffered PCM chunks leak.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _recordStreamSubscription?.cancel();
      _recordStreamSubscription = null;
      _audioRecorder.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget micIcon = Container(
      width: 160,
      height: 160,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _isConnected 
            ? AppTheme.primaryBlue.withValues(alpha: 0.15) 
            : Colors.grey.withValues(alpha: 0.1),
        border: Border.all(
          color: _isConnected ? AppTheme.primaryBlue : Colors.grey,
          width: 3,
        ),
        boxShadow: _isConnected ? [
          BoxShadow(
            color: AppTheme.primaryBlue.withValues(alpha: 0.5),
            blurRadius: 30,
            spreadRadius: 10,
          )
        ] : [],
      ),
      child: Icon(
        Icons.mic,
        size: 70,
        color: _isConnected ? AppTheme.primaryBlue : Colors.white54,
      ),
    );

    if (_isConnected) {
      micIcon = micIcon.animate(onPlay: (controller) => controller.repeat(reverse: true))
        .scale(begin: const Offset(1.0, 1.0), end: const Offset(1.2, 1.2), curve: Curves.easeInOut, duration: const Duration(milliseconds: 800))
        .tint(color: AppTheme.primaryBlue.withValues(alpha: 0.2), duration: const Duration(milliseconds: 800));
    }

    return Scaffold(
      backgroundColor: AppTheme.deepObsidian, // Dark mode optimized for dark garage environments
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'Live Diagnostic Call',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _endCall,
        ),
      ),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            
            // TachometerPulsation Visualizer
            micIcon,
            
            const SizedBox(height: 60),
            
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: AppTheme.surfaceObsidian,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppTheme.primaryBlue.withValues(alpha: 0.3)),
              ),
              height: 120, // Fixed height for scrolling subtitles
              child: SingleChildScrollView(
                child: Text(
                  _currentAiTranscription,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            
            const Spacer(),
            
            // End Call Action
            Padding(
              padding: const EdgeInsets.only(bottom: 60.0),
              child: FloatingActionButton.extended(
                onPressed: _endCall,
                backgroundColor: AppTheme.dynamicCrimson,
                icon: const Icon(Icons.call_end, color: Colors.white, size: 28),
                label: const Text(
                  'End Call',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                elevation: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
