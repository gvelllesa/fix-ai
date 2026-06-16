import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/chat_controller.dart';
import '../../home/widgets/fix_ai_drawer.dart';
import '../../multimedia/widgets/media_buttons.dart';
import '../../multimedia/services/media_upload_service.dart';
import '../../../data/local_parts_scraper_service.dart';
import '../../ar_scan/screens/ar_scan_screen.dart';
import '../widgets/typing_indicator.dart';
class ChatScreen extends StatefulWidget {
  final Map<String, dynamic> carProfile;

  const ChatScreen({Key? key, required this.carProfile}) : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with SingleTickerProviderStateMixin {
  final ChatController _controller = ChatController();
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  bool _isAnalyzingMedia = false;
  String _mediaAnalysisStatus = '';
  bool _isFocused = false;
  bool _isRecording = false;
  bool _isRecordingUIActive = false;

  late final AnimationController _pulsateController;
  late final Animation<double> _pulsateAnimation;
  
  final _audioRecorder = AudioRecorder();
  final _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerUpdate);
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });

    _pulsateController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
    _pulsateAnimation = Tween<double>(begin: 0.9, end: 1.15).animate(
      CurvedAnimation(parent: _pulsateController, curve: Curves.easeInOut),
    );

    final vehicleId = widget.carProfile['id'];
    if (vehicleId != null) {
      _controller.loadHistoryForVehicle(vehicleId);
    }
  }

  Future<void> _handleCameraPress() async {
    if (!kIsWeb) {
      final status = await Permission.camera.request();
      if (status != PermissionStatus.granted) return;
    }

    // On Web, image_picker automatically handles browser file/camera permissions.
    final XFile? image = await _imagePicker.pickImage(source: ImageSource.camera);
    if (image == null) return;

    final bytes = await image.readAsBytes();
    await _uploadAndAnalyzeMedia(bytes: bytes, isAudio: false);
  }

  Future<void> _startRecordingFlow() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to record audio.')),
        );
      }
      return;
    }

    if (await _audioRecorder.hasPermission()) {
      setState(() {
        _isRecordingUIActive = true;
        _isRecording = true;
      });

      String? path;
      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        path = '${tempDir.path}/chat_audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      
      try {
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path ?? '',
        );
        debugPrint('Audio recording started at: $path');
      } catch (e) {
        debugPrint('Error starting audio recorder: $e');
        setState(() {
          _isRecordingUIActive = false;
          _isRecording = false;
        });
      }
    }
  }

  Future<void> _cancelRecordingFlow() async {
    if (!_isRecording) return;
    
    setState(() {
      _isRecordingUIActive = false;
      _isRecording = false;
    });

    try {
      final path = await _audioRecorder.stop();
      debugPrint('Audio recording cancelled. Discarded: $path');
      if (path != null && !kIsWeb) {
        final file = File(path);
          try {
            await file.delete();
          } catch (_) {}
      }
    } catch (e) {
      debugPrint('Error cancelling audio recording: $e');
    }
  }

  Future<void> _sendRecordingFlow() async {
    if (!_isRecording) return;
    
    setState(() {
      _isRecordingUIActive = false;
      _isRecording = false;
    });

    try {
      final path = await _audioRecorder.stop();
      debugPrint('Audio recording stopped for send. Path: $path');
      
      if (path != null) {
        Uint8List bytes;
        if (kIsWeb) {
          final response = await http.get(Uri.parse(path));
          bytes = response.bodyBytes;
          await _uploadAndAnalyzeMedia(bytes: bytes, isAudio: true);
        } else {
          final file = File(path);
          if (await file.exists()) {
            bytes = await file.readAsBytes();
            await _uploadAndAnalyzeMedia(bytes: bytes, isAudio: true);
            try {
              await file.delete();
            } catch (_) {}
          } else {
            debugPrint('Recorded file does not exist: $path');
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending audio recording: $e');
    }
  }

  Future<void> _uploadAndAnalyzeMedia({required Uint8List bytes, required bool isAudio}) async {
    setState(() {
      _isAnalyzingMedia = true;
      _mediaAnalysisStatus = isAudio ? 'AI is analyzing engine sound...' : 'AI is analyzing image...';
    });

    try {
      final extension = isAudio ? 'm4a' : 'jpg';
      final uploadService = MediaUploadService();
      final publicUrl = await uploadService.uploadChatMedia(bytes, extension, 'chat-media');

      _controller.messages.add(ChatMessage(
        text: isAudio ? '🎤 Sent an audio clip' : '📸 Sent an image',
        isUser: true,
      ));
      _onControllerUpdate();

      final aiResponse = await _controller.diagnosticService.analyzeMultimedia(
        imageUrl: isAudio ? null : publicUrl,
        audioUrl: isAudio ? publicUrl : null,
        carProfile: widget.carProfile,
      );

      _controller.messages.add(ChatMessage(text: aiResponse, isUser: false));
      _onControllerUpdate();

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Media analysis failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzingMedia = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _pulsateController.dispose();
    _audioRecorder.dispose();
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onControllerUpdate() {
    setState(() {});
    // Auto-scroll to bottom on new messages
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // Reversed list view starts at 0.0 for bottom
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> listItems = [];
    // Quick actions have been removed.
    if (_controller.isLoading) {
      listItems.add(const TypingIndicator());
    }

    for (var msg in _controller.messages.reversed) {
      listItems.add(MessageBubbleWidget(
        msg: msg,
      ));
    }

    // Branding header at the top of the chat (end of the reversed list)
    listItems.add(
      Padding(
        padding: const EdgeInsets.only(top: 40, bottom: 20),
        child: Center(
          child: Text(
            'FIX AI',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).primaryColor,
              letterSpacing: 1.5,
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      resizeToAvoidBottomInset: true,
      drawer: FixAiDrawer(
        currentCarId: widget.carProfile['id'],
        onObdConnected: (payload) {
          Navigator.pop(context); // Close the drawer
          final code = payload['code'];
          final desc = payload['description'];
          _controller.sendMessage(
            "I scanned the car and found OBD-II Code: $code (*$desc*). What should I check, and what parts might need replacing?", 
            widget.carProfile
          );
        },
        onVehicleSelected: (car) {
          final carMap = {
            'id': car['id'],
            'make': car['make'],
            'brand': car['make'],
            'model': car['model'],
            'year': car['year']?.toString(),
            'engine': car['engine_type'],
            'engine_type': car['engine_type'],
          };
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(carProfile: carMap)),
          );
        },
      ),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).textTheme.bodyMedium?.color),

      ),
      body: Stack(
        children: [
          ListView.builder(
            reverse: true,
            controller: _scrollController,
            padding: const EdgeInsets.only(top: 16, left: 16, right: 16, bottom: 24),
            itemCount: listItems.length,
            itemBuilder: (context, index) {
              return listItems[index];
            },
          ),
          if (_isAnalyzingMedia)
            Container(
              color: Colors.black54,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceObsidian,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(color: AppTheme.primaryBlue),
                      const SizedBox(height: 16),
                      Text(
                        _mediaAnalysisStatus,
                        style: const TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: _buildFloatingInputArea(),
        ),
      ),
    );
  }


  // _buildMessageBubble and _buildCopyButton have been extracted into MessageBubbleWidget below

  Widget _buildFloatingInputArea() {
    Widget inputWidget = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.only(left: 4, right: 4, bottom: 16, top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.8), // Glassmorphism
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: _isFocused ? Theme.of(context).primaryColor.withOpacity(0.5) : Theme.of(context).dividerColor.withOpacity(0.3),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _isFocused ? Theme.of(context).primaryColor.withOpacity(0.15) : Colors.black.withOpacity(0.1),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: SafeArea(
            top: false,
            bottom: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              transitionBuilder: (Widget child, Animation<double> animation) {
                return FadeTransition(
                  opacity: animation,
                  child: child,
                );
              },
              child: !_isRecordingUIActive
                  ? Row(
                      key: const ValueKey('text_input_mode'),
                      children: [
                        MediaButtons(
                          onCameraPressed: _handleCameraPress,
                          onMicrophonePressed: _startRecordingFlow,
                        ),
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 16),
                            maxLines: 4,
                            minLines: 1,
                            decoration: InputDecoration(
                              hintText: 'Describe symptoms or ask for a procedure...',
                              hintStyle: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.3), fontSize: 14),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                            ),
                            onSubmitted: (_) => _sendMessage(),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Material(
                            color: Theme.of(context).primaryColor,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.hardEdge,
                            child: InkWell(
                              onTap: _sendMessage,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                child: const Icon(Icons.send, color: Colors.white, size: 18),
                              ),
                            ),
                          ),
                        ),
                      ],
                    )
                  : Row(
                      key: const ValueKey('voice_recording_mode'),
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Cancel button
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Material(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            shape: const CircleBorder(),
                            clipBehavior: Clip.hardEdge,
                            child: InkWell(
                              onTap: _cancelRecordingFlow,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                              ),
                            ),
                          ),
                        ),
                        // Center listening animation
                        Expanded(
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ScaleTransition(
                                  scale: _pulsateAnimation,
                                  child: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.redAccent.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.mic, color: Colors.redAccent, size: 20),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                AnimatedBuilder(
                                  animation: _pulsateAnimation,
                                  builder: (context, child) {
                                    return Opacity(
                                      opacity: 0.6 + (_pulsateAnimation.value - 0.9) * 1.6,
                                      child: child,
                                    );
                                  },
                                  child: const Text(
                                    'Listening...',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Send button
                        Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Material(
                            color: Theme.of(context).primaryColor,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.hardEdge,
                            child: InkWell(
                              onTap: _sendRecordingFlow,
                              child: Container(
                                width: 40,
                                height: 40,
                                alignment: Alignment.center,
                                child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );

    // Apply NeuralFlowGlow during loading
    if (_controller.isLoading || _isAnalyzingMedia) {
      inputWidget = inputWidget.animate(onPlay: (controller) => controller.repeat())
        .shimmer(duration: const Duration(seconds: 2), color: AppTheme.neonEmerald.withValues(alpha: 0.3))
        .boxShadow(
          begin: const BoxShadow(color: Colors.transparent, blurRadius: 0),
          end: BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: 2),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOut,
        ).then().boxShadow(
          begin: BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.5), blurRadius: 15, spreadRadius: 2),
          end: const BoxShadow(color: Colors.transparent, blurRadius: 0),
          duration: const Duration(milliseconds: 1000),
          curve: Curves.easeInOut,
        );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        inputWidget,
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            'FIX AI can make mistakes. Verify critical diagnostic procedures.',
            style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.5), fontSize: 10),
          ),
        ),
      ],
    );
  }

  void _sendMessage() {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    _textController.clear();
    _controller.sendMessage(text, widget.carProfile, onError: (errorMsg) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMsg),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    });
  }

  void _showLocalPrices(String partName) {
    final brand = widget.carProfile['brand']?.toString() ?? 'Unknown';
    final model = widget.carProfile['model']?.toString() ?? 'Model';

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => LocalPriceBottomSheet(
        englishPartName: partName,
        vehicleBrand: brand,
        vehicleModel: model,
      ),
    );
  }
}

class LocalPriceBottomSheet extends StatelessWidget {
  final String englishPartName;
  final String vehicleBrand;
  final String vehicleModel;

  const LocalPriceBottomSheet({
    Key? key,
    required this.englishPartName,
    required this.vehicleBrand,
    required this.vehicleModel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final service = LocalPartsScraperService();

    return Container(
      height: MediaQuery.of(context).size.height * 0.6,
      decoration: const BoxDecoration(
        color: Color(0xFF1E1E1E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Local Parts Pricing: $englishPartName',
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Searching Georgian market for $vehicleBrand $vehicleModel',
            style: const TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: service.fetchLocalPartsPrices(englishPartName, vehicleBrand, vehicleModel),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.green));
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}', style: const TextStyle(color: Colors.redAccent)));
                }

                final results = snapshot.data ?? [];
                if (results.isEmpty) {
                  return const Center(child: Text('No local prices found.', style: TextStyle(color: Colors.white54)));
                }

                return ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final item = results[index];
                    return Card(
                      color: const Color(0xFF2C2C2C),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(item['part_title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6.0),
                          child: Text('Source: ${item['source_site']}\\nStatus: ${item['availability_status']}', style: const TextStyle(color: Colors.white70)),
                        ),
                        trailing: Text('${item['price_gel']} ₾', style: const TextStyle(color: Colors.greenAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class MessageBubbleWidget extends StatefulWidget {
  final ChatMessage msg;

  const MessageBubbleWidget({
    Key? key,
    required this.msg,
  }) : super(key: key);

  @override
  State<MessageBubbleWidget> createState() => _MessageBubbleWidgetState();
}

class _MessageBubbleWidgetState extends State<MessageBubbleWidget> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Widget _buildCopyButton(String textToCopy) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: textToCopy));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Text copied to clipboard!'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.grey.shade800,
          ),
        );
      },
      child: const Icon(
        Icons.copy,
        size: 18,
        color: Colors.white54,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final msg = widget.msg;
    final isUser = msg.isUser;
    
    // Parse message for Technical Note split by '---'
    final parts = msg.text.split('---');
    final mainText = parts.first.trim();
    final technicalNote = parts.length > 1 ? parts.sublist(1).join('---').trim() : null;

    final child = isUser
        ? Align(
            alignment: Alignment.centerRight,
            child: _buildUserBubble(mainText),
          )
        : _buildAiBubble(mainText, technicalNote);

    return child.animate().scale(
      begin: const Offset(0.85, 0.85),
      end: const Offset(1.0, 1.0),
      duration: 250.ms,
      curve: Curves.easeOutBack,
    ).fade(duration: 200.ms);
  }

  Widget _buildUserBubble(String text) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor,
        border: Border.all(color: Theme.of(context).primaryColor),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(12),
          bottomRight: Radius.circular(2),
        ),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 16)),
    );
  }

  Widget _buildAiBubble(String text, String? technicalNote) {
    String? detectedPartForAr;
    final lowerText = text.toLowerCase();
    if (lowerText.contains('spark plug') || lowerText.contains('აალების სანთლები') || lowerText.contains('spark plugs')) {
      detectedPartForAr = 'Spark Plugs';
    } else if (lowerText.contains('air filter') || lowerText.contains('ჰაერის ფილტრი')) {
      detectedPartForAr = 'Air Filter';
    } else if (lowerText.contains('battery') || lowerText.contains('აკუმულატორი')) {
      detectedPartForAr = 'Battery';
    } else if (lowerText.contains('vanos') || lowerText.contains('სოლენოიდი')) {
      detectedPartForAr = 'VANOS Solenoid';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          margin: const EdgeInsets.only(top: 8, right: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).primaryColor.withOpacity(0.2)),
          ),
          child: Center(child: Text('AI', style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold, fontSize: 12))),
        ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: Theme.of(context).primaryColor, shape: BoxShape.circle),
                    ).animate(onPlay: (c) => c.repeat()).fadeIn(duration: 1.seconds).then().fadeOut(duration: 1.seconds),
                    const SizedBox(width: 8),
                    Text('ANALYSIS COMPLETE', style: TextStyle(color: Theme.of(context).primaryColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                  ],
                ),
                const SizedBox(height: 12),
                MarkdownBody(
                  data: text,
                  selectable: true,
                  onTapLink: (text, href, title) async {
                    if (href != null) {
                      final url = Uri.parse(href);
                      if (await canLaunchUrl(url)) {
                        await launchUrl(url, mode: LaunchMode.externalApplication);
                      }
                    }
                  },
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 16, height: 1.5),
                    a: const TextStyle(color: Colors.blueAccent, decoration: TextDecoration.underline),
                    blockquoteDecoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(8),
                      border: const Border(left: BorderSide(color: Colors.blueAccent, width: 4)),
                    ),
                    blockquote: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color, fontSize: 16),
                    code: TextStyle(backgroundColor: Theme.of(context).brightness == Brightness.dark ? Colors.black45 : Colors.black12, color: Theme.of(context).brightness == Brightness.dark ? AppTheme.neonEmerald : Colors.green.shade800, fontFamily: 'monospace'),
                    codeblockDecoration: BoxDecoration(
                      color: Theme.of(context).brightness == Brightness.dark ? Colors.black45 : Colors.black12,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    tableBorder: TableBorder.all(color: Theme.of(context).dividerColor.withOpacity(0.3), width: 1),
                    tableCellsPadding: const EdgeInsets.all(8),
                  ),
                ),
                if (technicalNote != null && technicalNote.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    child: Text(
                      technicalNote,
                      style: const TextStyle(color: AppTheme.neonEmerald, fontSize: 14, fontFamily: 'monospace', height: 1.4),
                    ),
                  ).animate().fadeIn(delay: 300.ms, duration: 400.ms),
                ],
                if (detectedPartForAr != null) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withOpacity(0.2),
                        foregroundColor: Colors.blueAccent,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: Colors.blueAccent.withOpacity(0.5))),
                      ),
                      onPressed: () {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ArScanScreen(partName: detectedPartForAr!)));
                      },
                      icon: const Icon(Icons.visibility),
                      label: Text("მაჩვენე AR-ში ($detectedPartForAr)"),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildCopyButton(widget.msg.text),
                    ],
                  ),
                ),
              ],
            ),
          ).animate(onPlay: (c) => c.repeat(reverse: true))
           .boxShadow(
             begin: BoxShadow(color: AppTheme.primaryBlue.withValues(alpha: 0.2), blurRadius: 10, spreadRadius: 0),
             end: BoxShadow(color: AppTheme.neonEmerald.withValues(alpha: 0.3), blurRadius: 15, spreadRadius: 0),
             duration: const Duration(seconds: 3),
             curve: Curves.easeInOut,
           )
           // Add Animated Border using a Container wrapper technique, but here we just animate boxShadow
           // For borders we'd need AnimatedBuilder, but boxShadow is sufficient for glow.
        ),
      ],
    );
  }
}
