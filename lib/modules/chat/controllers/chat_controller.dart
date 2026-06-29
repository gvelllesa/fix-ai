import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../core/services/platform_info_native.dart'
    if (dart.library.html) '../../../core/services/platform_info_web.dart'
    as platform_info;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../data/gemini_gatekeeper_service.dart';
import '../../../data/gemini_diagnostic_service.dart' show GeminiDiagnosticService, TierLimitException;
import '../../../data/offline_dtc_service.dart';
import '../../../data/offline_dtc_summary_builder.dart';
import '../../../data/offline_vehicle_pack_service.dart';
import '../../../data/obd_data_processor.dart';
import '../../obd/services/diagnostic_connection_exception.dart';
import '../../obd/services/obd_scan_exception.dart';
import '../../../data/local_cache_service.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/connectivity_service.dart';
import '../../../core/services/deferred_analysis_outbox.dart';
import '../../../core/services/ai/local_vehicle_ai_pipeline.dart';
import '../../../core/services/ai/ai_agent_event_bus.dart';
import '../../../core/services/ai/ai_dispatch_status.dart';
import '../../obd/services/diagnostic_adapter_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../../multimedia/services/media_upload_service.dart';
import '../../obd/widgets/obd_connection_dialog.dart';
import '../../obd/widgets/obd_connect_auto_dialog.dart';
import 'package:ar_flutter_plugin_2/ar_flutter_plugin.dart';

enum ChatMessageKind { text, agentAction }

enum AgentActionState { inProgress, completed, failed }

class ChatMessage {
  final String text;
  final bool isUser;
  final List<String> quickReplies;
  final ChatMessageKind kind;
  final AgentActionState? agentState;
  final AiDispatchPhase? agentPhase;
  final String? agentTraceId;

  /// 6.25 FIX (Deferred AI UX): when this message was produced offline, this
  /// holds the original prompt (with DTC codes) that should be re-analyzed by
  /// Gemini once the device is back online. Null for normal messages.
  final String? deferredAnalysisPrompt;

  /// The car profile captured at scan time, used when the deferred analysis
  /// is finally run.
  final Map<String, dynamic>? deferredCarProfile;

  /// Stable id used to correlate this bubble with a [PendingAnalysis] in the
  /// persistent outbox. When null, this message is not deferred.
  final String? deferredId;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.quickReplies = const [],
    this.kind = ChatMessageKind.text,
    this.agentState,
    this.agentPhase,
    this.agentTraceId,
    this.deferredAnalysisPrompt,
    this.deferredCarProfile,
    this.deferredId,
  });

  factory ChatMessage.agentAction({
    required String text,
    required String traceId,
    AiDispatchPhase? phase,
    AgentActionState state = AgentActionState.inProgress,
  }) {
    return ChatMessage(
      text: text,
      isUser: false,
      kind: ChatMessageKind.agentAction,
      agentTraceId: traceId,
      agentPhase: phase,
      agentState: state,
    );
  }

  bool get isAgentAction => kind == ChatMessageKind.agentAction;
}

class ChatController extends ChangeNotifier {
  final GeminiGatekeeperService _gatekeeperService = GeminiGatekeeperService();
  final GeminiDiagnosticService _diagnosticService = GeminiDiagnosticService();
  GeminiDiagnosticService get diagnosticService => _diagnosticService;
  final ObdDataProcessor _obdProcessor = ObdDataProcessor();
  final LocalCacheService _cache = LocalCacheService();

  List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => _messages;

  String _loadingText = 'AI is typing';
  String get loadingText => _loadingText;

  String? _activeAgentTraceId;
  StreamSubscription<AiDispatchStatus>? _agentStatusSub;

  bool get hasActiveAgentTrace => _activeAgentTraceId != null;

  bool _isArSupported = false;
  bool get isArSupported => _isArSupported;

  ChatController() {
    initArCheck();
    _wireDeferredAnalysisOutbox();
    _agentStatusSub = AiAgentEventBus.instance.statusStream.listen(
      _onAgentStatusFromBus,
    );
  }

  void _onAgentStatusFromBus(AiDispatchStatus status) {
    if (_activeAgentTraceId == null) return;
    _updateAgentActionBubble(status);
  }

  String _startAgentTrace() {
    final traceId = 'agent_${DateTime.now().millisecondsSinceEpoch}';
    _activeAgentTraceId = traceId;
    _messages.add(
      ChatMessage.agentAction(
        text: 'Thinking…',
        traceId: traceId,
        phase: AiDispatchPhase.parsing,
      ),
    );
    _isLoading = false;
    notifyListeners();
    return traceId;
  }

  void _updateAgentActionBubble(AiDispatchStatus status) {
    final traceId = _activeAgentTraceId;
    if (traceId == null) return;

    final idx = _messages.lastIndexWhere((m) => m.agentTraceId == traceId);
    if (idx < 0) return;

    final failed = status.phase == AiDispatchPhase.failed;
    final completed = status.phase == AiDispatchPhase.completed;
    final state = failed
        ? AgentActionState.failed
        : completed
            ? AgentActionState.completed
            : AgentActionState.inProgress;

    _messages[idx] = ChatMessage.agentAction(
      text: status.message,
      traceId: traceId,
      phase: status.phase,
      state: state,
    );
    _loadingText = status.message;
    notifyListeners();
  }

  void _endAgentTrace() {
    _activeAgentTraceId = null;
    AiAgentEventBus.instance.clear();
  }

  /// Connects the persistent [DeferredAnalysisOutbox] to this controller.
  ///
  ///   * Registers this controller as the outbox `runner` so a reconnect
  ///     flush re-dispatches each pending analysis through the normal
  ///     [sendMessage] path.
  ///   * Registers a reconnect callback with [ConnectivityService] so the
  ///     flush fires automatically the moment the device regains a network.
  ///   * If we are *already* online at registration time and the outbox has
  ///     stranded items (e.g. the user killed the app offline then reopened
  ///     it on mobile data), drain them immediately.
  void _wireDeferredAnalysisOutbox() {
    DeferredAnalysisOutbox.instance.runner = (item) async {
      // Auto-flush on reconnect: route through the same consumer as a manual
      // tap so the source bubble's deferred button is cleared and a duplicate
      // Gemini call is impossible.
      await _runDeferredById(item);
    };
    ConnectivityService.instance.registerOnReconnect(() async {
      await DeferredAnalysisOutbox.instance.flush();
    });
    // Stranded items from a prior offline session that's now online.
    if (ConnectivityService.instance.isOnline) {
      DeferredAnalysisOutbox.instance.flush().catchError((Object e) {
        debugPrint('DeferredAnalysisOutbox initial flush failed: $e');
      });
    }
  }

  /// Set of outbox ids whose analysis is already in-flight. Prevents a race
  /// where a manual tap and the reconnect auto-flush both try to run the same
  /// pending item, which would fire Gemini twice.
  final Set<String> _inFlightDeferred = <String>{};

  Future<void> initArCheck() async {
    try {
      if (kIsWeb) {
        _isArSupported = false;
      } else if (kIsWeb) {
        _isArSupported = false;
      } else {
        // Native non-Web: try AR plugin.
        _isArSupported = false; // AR plugin not loaded on Web; guarded below
        final version = await ArFlutterPlugin.platformVersion;
        _isArSupported = version.isNotEmpty;
      }
    } catch (e) {
      debugPrint('ARCore/ARKit availability check failed: $e');
      _isArSupported = false;
    }
    notifyListeners();
  }

  String get currentLanguage {
    for (var msg in _messages.reversed) {
      if (!msg.isUser) {
        return _detectLanguage(msg.text);
      }
    }
    return _detectSystemLanguage();
  }

  String _detectSystemLanguage() {
    try {
      if (kIsWeb) {
        return 'en';
      }
      final locale = platform_info.localeNameNative.toLowerCase();
      if (locale.startsWith('ka')) {
        return 'ka';
      } else if (locale.startsWith('ru')) {
        return 'ru';
      }
    } catch (e) {
      // Fallback
    }
    return 'en';
  }

  String _detectLanguage(String text) {
    final georRegExp = RegExp(r'[\u10A0-\u10FF]');
    if (georRegExp.hasMatch(text)) {
      return 'ka';
    }
    final cyrRegExp = RegExp(r'[\u0400-\u04FF]');
    if (cyrRegExp.hasMatch(text)) {
      return 'ru';
    }
    return 'en';
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isSessionComplete = false;
  bool get isSessionComplete => _isSessionComplete;

  void completeSession() {
    _isSessionComplete = true;
    notifyListeners();
  }

  void startNewSession() {
    _messages.clear();
    _isSessionComplete = false;
    _isLoading = false;
    _diagnosticService.resetSession();
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
          .select('message, response')
          .eq('car_profile_id', vehicleId) // BUG-06 FIX: standardized column name
          .order('created_at', ascending: true);

      final List<ChatMessage> loadedMessages = [];
      for (var row in response) {
        final userMessage = row['message']?.toString();
        final aiResponse = row['response']?.toString();
        
        if (userMessage != null && userMessage.isNotEmpty) {
          loadedMessages.add(ChatMessage(text: userMessage, isUser: true));
        }
        if (aiResponse != null && aiResponse.isNotEmpty) {
          loadedMessages.add(_parseAiResponse(aiResponse));
        }
      }
      _messages.addAll(loadedMessages);

      // 6.6 FIX: mirror the loaded history into the Hive cache so the next
      // offline launch can show it.
      await _cache.cacheChatHistory(vehicleId,
          _messages.map(_messageToCacheJson).toList());
    } catch (e) {
      debugPrint('Error loading chat history: $e');
      // 6.6 FIX: fall back to cached history when Supabase is unreachable.
      // TRUE OFFLINE-FIRST: restore deferred flags from the persistent
      // outbox so offline bubbles keep their "Deep AI Analysis" button and
      // auto-run on reconnect, even after an app kill.
      try {
        final cached = await _cache.getCachedChatHistory(vehicleId);
        if (cached.isNotEmpty) {
          final pending = await DeferredAnalysisOutbox.instance.pending();
          final byId = {for (final p in pending) p.id: p};
          _messages.addAll(cached.map((m) {
            final text = m['text']?.toString() ?? '';
            final isUser = m['isUser'] == true;
            final did = m['deferredId']?.toString();
            if (!isUser && did != null && byId.containsKey(did)) {
              final p = byId[did]!;
              return ChatMessage(
                text: text,
                isUser: false,
                deferredAnalysisPrompt: p.prompt,
                deferredCarProfile: p.carProfile,
                deferredId: did,
              );
            }
            return ChatMessage(text: text, isUser: isUser);
          }));
          _messages.add(ChatMessage(
            text: '⚠️ Offline mode — couldn\'t reach the server. '
                  'Showing previous chat history from local cache.',
            isUser: false,
          ));
        }
      } catch (_) {}
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void loadHistoryFromMessages(List<dynamic> messageJsonList) {
    _isLoading = true;
    _messages.clear();
    _isSessionComplete = true;
    notifyListeners();

    try {
      final List<ChatMessage> loadedMessages = [];
      for (var item in messageJsonList) {
        if (item is Map) {
          final role = item['role']?.toString();
          final content = item['content'] ?? item['text'] ?? item['message'];
          if (content != null) {
            loadedMessages.add(ChatMessage(
              text: content.toString(),
              isUser: role == 'user',
            ));
          }
        }
      }
      _messages.addAll(loadedMessages);
    } catch (e) {
      debugPrint('Error loading chat history from messages: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> sendMessage(String text, Map<String, dynamic> carProfile, {void Function(String)? onError}) async {
    if (text.trim().isEmpty) return;

    // Clean up placeholder texts like (*Unknown Error*) from the user's message
    String cleanedText = text;
    final unknownErrorRegex = RegExp(r'\s*\(\*(?:Unknown Error|Unknown|No description available|null)\*\)\s*', caseSensitive: false);
    
    if (cleanedText.contains(unknownErrorRegex) || cleanedText.toLowerCase().contains('unknown error')) {
      final scanTemplateRegex = RegExp(
        r'I scanned the car and found OBD-II Code:\s*(\w+)\s*\(\*(?:Unknown Error|Unknown|No description available|null)\*\)\..*',
        caseSensitive: false,
      );
      final match = scanTemplateRegex.firstMatch(cleanedText);
      if (match != null) {
        final code = match.group(1);
        cleanedText = "I scanned the car and found Code: $code.";
      } else {
        cleanedText = cleanedText.replaceAll(unknownErrorRegex, ' ');
        cleanedText = cleanedText.replaceAll(RegExp(r'\s{2,}'), ' ');
        cleanedText = cleanedText.trim();
      }
    }

    // Add user message
    _messages.add(ChatMessage(text: cleanedText, isUser: true));
    
    // Initialize loading text based on language
    final lang = currentLanguage;
    if (lang == 'ka') {
      _loadingText = 'AI ბეჭდავს';
    } else if (lang == 'ru') {
      _loadingText = 'AI печатает';
    } else {
      _loadingText = 'AI is typing';
    }
    
    _isLoading = true;
    notifyListeners();

    try {
      // ENET/offline path: local orchestrator → UDS dispatcher → SLM summary.
      if (await _shouldUseLocalVehicleAi(cleanedText)) {
        final handled =
            await _tryLocalVehicleAiResponse(cleanedText, carProfile);
        if (handled) return;
      }

      // TRUE OFFLINE-FIRST (DNS-verified): the phone may be joined to the
      // ENET/ELM327 adapter's Wi-Fi, which Android reports as a live Wi-Fi
      // link even though it has no internet route. `connectivity_plus`
      // returns `wifi` and would be a false positive — so we rely on an
      // active DNS lookup instead.
      final isOffline = await ConnectivityService.instance.isOffline();
      if (isOffline) {
        _isLoading = false;
        // 6.11 FIX: previously any offline state discarded the message and
        // showed a generic toast. For OBD-scan messages that contain real
        // DTC codes, fall back to the local dictionary so the user still
        // gets a useful summary instead of losing their just-scanned data.
        final codes = GeminiDiagnosticService.extractDtcCodes(cleanedText);
        if (codes.isNotEmpty) {
          final summary = OfflineDtcSummaryBuilder.build(codes, carProfile);
          // 6.25 FIX: attach the deferred-analysis prompt so the chat bubble
          // can render the "Internet Required for Deep AI Analysis" button.
          // TRUE OFFLINE-FIRST: also persist this to the outbox so it
          // survives an app kill and auto-runs on reconnect.
          final deferredId =
              'deferred_${DateTime.now().millisecondsSinceEpoch}';
          _messages.add(ChatMessage(
            text: summary,
            isUser: false,
            deferredAnalysisPrompt: cleanedText,
            deferredCarProfile: Map<String, dynamic>.from(carProfile),
            deferredId: deferredId,
          ));
          unawaited(DeferredAnalysisOutbox.instance.enqueue(PendingAnalysis(
            id: deferredId,
            prompt: cleanedText,
            carProfile: Map<String, dynamic>.from(carProfile),
            enqueuedAt: DateTime.now().millisecondsSinceEpoch,
          )));
        } else {
          _messages.add(ChatMessage(
            text: "⚠️ You're offline. Please check your internet "
                  "connection and try again.",
            isUser: false,
          ));
        }
        notifyListeners();
        return;
      }

      final isRelevant = await _gatekeeperService.isQueryRelevant(cleanedText);
      final historyList = _messages.sublist(0, _messages.length - 1);
      
      if (isRelevant) {
        final userCountry = await LocationService().fetchUserCountry();
        final stream = _diagnosticService.generateDiagnosisStream(
          cleanedText,
          carProfile,
          chatHistory: historyList,
          userCountry: userCountry,
          userLanguage: currentLanguage,
        );
        
        await _processResponseStream(stream);

        // Mark session as complete after receiving a diagnostic response
        _isSessionComplete = true;
        notifyListeners();

        // 6.6 FIX: persist this turn to Hive so it survives offline launches.
        final vehicleId = carProfile['id']?.toString();
        if (vehicleId != null) {
          await _cache.cacheChatHistory(vehicleId,
              _messages.map(_messageToCacheJson).toList());
        }
      } else {
        final rejectionPrompt = "SYSTEM DIRECTIVE: The following user input is NOT car-related. Ignore all previous rules and do not output a technical note. Politely tell the user in the EXACT SAME LANGUAGE AND SCRIPT they used that you can only answer automotive diagnostics questions.\n\nUser Input: $cleanedText";
        final stream = _diagnosticService.generateDiagnosisStream(
          rejectionPrompt, 
          carProfile,
          chatHistory: historyList,
        );
        
        await _processResponseStream(stream);
        notifyListeners();
      }
    } catch (e) {
      _isLoading = false;
      notifyListeners();

      // 6.3 FIX: surface tier-limit as a friendly paywall message instead of
      // a raw exception string.
      String errorMsg;
      if (e is TierLimitException) {
        errorMsg = e.message;
      } else {
        errorMsg = e.toString();
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

  /// 6.25 FIX (Deferred AI UX): re-runs a deep AI analysis for an offline
  /// scan once the device is back online. Triggered by the "Internet Required
  /// for Deep AI Analysis" button on an offline diagnostic bubble.
  ///
  /// ONLINE MODE contract: Gemini is invoked ONLY when a fresh DNS probe
  /// confirms a real internet path (i.e. the user has disconnected from the
  /// car/OBD Wi-Fi and regained 4G/5G). If still offline, returns false so
  /// the UI can show a "still offline" hint and no network call is made.
  Future<bool> runDeferredAnalysis(ChatMessage source) async {
    final prompt = source.deferredAnalysisPrompt;
    if (prompt == null) return false;
    final deferredId = source.deferredId;

    // ONLINE MODE: verify a real internet path before doing anything. The
    // reconnect-aware banner already reflects live state, but the user could
    // tap in the gap between a platform event and the verified probe.
    final online = await ConnectivityService.instance.hasInternet();
    if (!online) {
      return false; // still offline — UI shows a hint, Gemini NOT called
    }

    // Dedupe: if the auto-flush already picked this id up, bail. Also covers
    // a double-tap on the button.
    if (deferredId != null && !_inFlightDeferred.add(deferredId)) {
      debugPrint('runDeferredAnalysis: $deferredId already in-flight, ignoring.');
      return true;
    }

    // Drop the button on the source bubble so it can't be tapped again, and
    // so the auto-flush runner won't find a matching deferred bubble.
    _clearDeferredBubble(deferredId, source);
    if (deferredId != null) {
      unawaited(DeferredAnalysisOutbox.instance.markDone(deferredId));
    }

    final profile = source.deferredCarProfile ??
        {'make': 'BMW', 'model': 'Unknown', 'year': 'Unknown'};
    try {
      // Run the standard ONLINE diagnosis with the cached codes. This is the
      // one and only place Gemini + forum/TSB enrichment fires for a deferred
      // scan.
      await sendMessage(prompt, profile);
    } finally {
      if (deferredId != null) _inFlightDeferred.remove(deferredId);
    }
    return true;
  }

  /// Shared consumer used by BOTH the manual "Tap here" button and the
  /// reconnect auto-flush runner. Guarantees a pending analysis runs at most
  /// once, clears any matching deferred bubble, and only calls Gemini when
  /// verified online.
  Future<void> _runDeferredById(PendingAnalysis item) async {
    // Dedupe across manual-tap vs auto-flush.
    if (!_inFlightDeferred.add(item.id)) {
      debugPrint('_runDeferredById: ${item.id} already in-flight, ignoring.');
      return;
    }
    try {
      // ONLINE MODE: the reconnect callback only fires on a verified
      // offline→online transition, but re-check defensively in case the link
      // dropped again before we got here.
      final online = await ConnectivityService.instance.hasInternet();
      if (!online) {
        debugPrint('_runDeferredById: ${item.id} skipped — back offline.');
        return;
      }
      // Clear the source bubble's deferred button if it's still mounted.
      _clearDeferredBubble(item.id, null);
      await DeferredAnalysisOutbox.instance.markDone(item.id);
      await sendMessage(item.prompt, item.carProfile);
    } finally {
      _inFlightDeferred.remove(item.id);
    }
  }

  /// Strips the deferred flags from the chat bubble matching [deferredId],
  /// replacing it with a plain (non-deferred) copy so the "Tap here" button
  /// disappears. Pass [fallback] to locate by object identity when no id is
  /// available. No-op if the bubble was already consumed.
  void _clearDeferredBubble(String? deferredId, ChatMessage? fallback) {
    if (_messages.isEmpty) return;
    int idx = -1;
    if (deferredId != null) {
      idx = _messages.indexWhere((m) => m.deferredId == deferredId);
    }
    if (idx == -1 && fallback != null) {
      idx = _messages.indexOf(fallback);
    }
    if (idx == -1) return;
    final current = _messages[idx];
    if (current.deferredAnalysisPrompt == null) return; // already cleared
    _messages[idx] = ChatMessage(text: current.text, isUser: false);
    notifyListeners();
  }

  Future<void> sendAudioMessage(Uint8List bytes, Map<String, dynamic> carProfile) async {
    _isLoading = true;
    notifyListeners();

    try {
      // TRUE OFFLINE-FIRST (DNS-verified): audio transcription + classification
      // both need a real internet path. Use the centralized probe so the
      // ENET/ELM327 Wi-Fi false positive can't sneak through here either.
      final hasInternet = await ConnectivityService.instance.hasInternet();

      if (!hasInternet) {
        _isLoading = false;
        _messages.add(ChatMessage(
          text: "Audio analysis requires an active internet connection. Please restore your connection to proceed with voice diagnostics.",
          isUser: false,
        ));
        notifyListeners();
        return;
      }

      // 1. SPEECH-TO-TEXT (STT) FIRST:
      final transcript = await _diagnosticService.transcribeAudio(bytes);
      if (transcript == null) {
        // 4.10 FIX: transcription failed — notify user, don't silently misroute.
        _isLoading = false;
        _messages.add(ChatMessage(
          text: "⚠️ Voice transcription failed. Please check your connection "
                "and try again, or type your question instead.",
          isUser: false,
        ));
        notifyListeners();
        return;
      }
      debugPrint('STT Transcript: $transcript');

      // 2. INTENT CLASSIFICATION LAYER:
      final intent = await _diagnosticService.classifyAudioIntent(transcript);
      if (intent == null) {
        // 4.11 FIX: classification failed — notify user, don't silently misroute.
        _isLoading = false;
        _messages.add(ChatMessage(
          text: "⚠️ Could not classify your voice message. Treating it as a "
                "question. If you intended to record an engine sound, please try again.",
          isUser: false,
        ));
        notifyListeners();
      }
      debugPrint('Audio Intent: $intent');

      // 3. ROUTING EXECUTION:
      if (intent == 'CONVERSATIONAL_INQUIRY') {
        // Display user transcript in the UI
        _messages.add(ChatMessage(text: "🎤 $transcript", isUser: true));
        
        // Initialize loading text based on language
        final lang = currentLanguage;
        if (lang == 'ka') {
          _loadingText = 'AI ბეჭდავს';
        } else if (lang == 'ru') {
          _loadingText = 'AI печатает';
        } else {
          _loadingText = 'AI is typing';
        }
        
        _isLoading = true;
        notifyListeners();

        final historyList = _messages.sublist(0, _messages.length - 1);
        final userCountry = await LocationService().fetchUserCountry();
        
        final stream = _diagnosticService.generateDiagnosisStream(
          transcript, 
          carProfile, 
          chatHistory: historyList,
          userCountry: userCountry,
        );
        
        await _processResponseStream(stream);
        _isSessionComplete = true;
        notifyListeners();
      } else {
        // ACOUSTIC_DIAGNOSTIC
        _messages.add(ChatMessage(text: "🎤 Sent an acoustic recording", isUser: true));
        notifyListeners();

        final uploadService = MediaUploadService();
        final publicUrl = await uploadService.uploadChatMedia(bytes, 'm4a', 'chat-media');

        // 6.8 FIX: previously this prompt was hardcoded for "BMW Group" and
        // only mentioned BMW failure modes (N55/N20). Now it is built from the
        // active car profile so acoustic diagnosis works for any brand.
        final make = (carProfile['make'] ?? carProfile['brand'] ?? 'the vehicle')
            .toString();
        final acousticContext = _buildAcousticContext(make);

        final aiResponse = await _diagnosticService.analyzeMultimedia(
          audioUrl: publicUrl,
          userContext: acousticContext,
          carProfile: carProfile,
        );

        _messages.add(_parseAiResponse(aiResponse));
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Audio analysis failed: ${e.toString()}");
      // BUG-03 FIX: Post a graceful error to the UI instead of rethrowing
      // and causing an unhandled exception crash at the call site.
      _messages.add(ChatMessage(
        text: "⚠️ Audio analysis failed. Please check your connection and try again.",
        isUser: false,
      ));
      notifyListeners();
      // Do NOT rethrow — the finally block handles _isLoading cleanup.
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> startOBDScan(BuildContext context, Map<String, dynamic> carProfile) async {
    final model = carProfile['model']?.toString() ?? 'Unknown';
    final make = (carProfile['make']?.toString() ?? carProfile['brand']?.toString() ?? '')
        .toLowerCase();

    // Detect BMW/MINI chassis code (e.g. "F30", "G20", "F56") from the model
    // string so we can pick the correct ECU map for the ENET scan.
    String? bmwChassis;
    if (make.contains('bmw') || make.contains('mini') || make.contains('бмв') || make.contains('mini')) {
      final match = RegExp(r'\b([FfGUu]\d{2})\b').firstMatch(model);
      if (match != null) {
        bmwChassis = match.group(1)!.toUpperCase();
      }
    }

    // 1. Show the OBDConnectAutoDialog first — one-button auto-detect. The
    // user can fall back to the legacy manual picker via "Manual setup".
    var result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => OBDConnectAutoDialog(preferredChassis: bmwChassis),
    );

    // Manual fallback: the user tapped "Manual setup" in the auto dialog.
    // Open the legacy OBDConnectionDialog so they can pick the interface /
    // enter the IP themselves. OBD Scanner stays available this way until
    // the auto flow is confirmed working on the user's adapters.
    if (result != null && result['status'] == 'manual') {
      result = await showDialog<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const OBDConnectionDialog(),
      );
    }

    if (result != null && result['status'] == 'connected') {
      final interfaceType = result['interface']?.toString() ?? 'Simulation';

      _isLoading = true;
      notifyListeners();

      // 6.24 FIX: ensure the offline DTC database is ready before scanning.
      // This is critical for ENET/Wi-Fi adapters — when the phone joins the
      // adapter's network it loses internet, so Gemini is unreachable and
      // only the offline database can decode the codes.
      await OfflineVehiclePackService().ensureLoaded().catchError((Object e) {
      debugPrint('OfflineVehiclePack pre-scan load failed (non-fatal): $e');
    });
    await OfflineDtcService().ensureDatabase().catchError((Object e) {
        debugPrint('OfflineDtcService pre-scan load failed (non-fatal): $e');
      });

      try {
        // 2. Obtain DTC codes. For Wi-Fi the dialog already connected and read
        // codes during _handleConnect (so we skip a duplicate scan). For other
        // interfaces we scan here. Mock data has been purged — if the scan
        // fails, an ObdScanException is thrown and we report it honestly.
        List<String> codes;
        final preset = result['dtcCodes'];
        if (preset is List) {
          codes = preset.cast<String>();
        } else {
          codes = await _obdProcessor.scanAndExtractFaultCodes(
            model,
            interfaceType,
            bluetoothDevice: result['bluetoothDevice'] as BluetoothDevice?,
            bmwChassisCode: bmwChassis,
          );
        }
        final codesString = codes.isEmpty ? 'No fault codes detected' : codes.join(', ');

        // 3. Inject System Scan complete message into UI (User bubble)
        final userScanMsg = codes.isEmpty
            ? "I scanned the car via OBD-II ($interfaceType) — the ECU reports no stored fault codes. What regular maintenance should I focus on?"
            : "I scanned the car and found OBD-II Code: $codesString. What should I check, and what parts might need replacing?";

        // This will clean and post the message automatically via sendMessage
        await sendMessage(userScanMsg, carProfile);

      } on DiagnosticConnectionException catch (e) {
        // Staged ENET failure surfaced from the chat scan path. Render the
        // structured stage + code + tip inline so the user sees exactly where
        // it died, mirroring the EnetErrorDialog.
        final stageNum = switch (e.stage) {
          DiagnosticStage.socketEstablishment => 1,
          DiagnosticStage.doipRoutingActivation => 2,
          DiagnosticStage.udsCommunication => 3,
        };
        final codePart = <String>[];
        if (e.osError != null) {
          codePart.add('errno ${e.osError!.errorCode} (${e.osError!.message})');
        }
        if (e.negativeResponseCodeHex != null) {
          codePart.add('code ${e.negativeResponseCodeHex}');
        }
        final codeStr = codePart.isEmpty ? '' : '\n**Code:** ${codePart.join(' • ')}';
        _messages.add(ChatMessage(
          text: '❌ **OBD-II scan failed (STAGE $stageNum).**\n\n'
              '${e.message}$codeStr\n\n'
              '**Tip:** ${e.troubleshootingTip}\n\n'
              'No codes were read from the car.',
          isUser: false,
        ));
      } on ObdScanException catch (e) {
        _messages.add(ChatMessage(
          text: "❌ **OBD-II scan failed.**\n\n${e.message}\n\n"
              "No codes were read from the car. Once you resolve the issue, try the OBD Scanner again.",
          isUser: false,
        ));
      } catch (e) {
        _messages.add(ChatMessage(text: "Hardware Scanner Error: ${e.toString()}", isUser: false));
      } finally {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> requestCostEstimate(Map<String, dynamic> carProfile) async {
    _isLoading = true;
    _messages.add(ChatMessage(text: "Requesting Live Cost & Parts Estimate...", isUser: true));
    notifyListeners();

    try {
      final response = await _diagnosticService.estimateRepairCost(carProfile);
      // 6.23 FIX: previously wrapped in ```json fence which broke the table
      // rendering (the AI returns markdown prose + tables, not JSON). Also
      // route through _parseAiResponse so [QUICK_REPLIES] is honoured.
      _messages.add(_parseAiResponse('### Cost Estimate\n\n$response'));
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
      // 6.23 FIX: route through _parseAiResponse for QUICK_REPLIES support.
      _messages.add(_parseAiResponse(response));
    } catch (e) {
      _messages.add(ChatMessage(text: "Error generating guide: $e", isUser: false));
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _processResponseStream(Stream<String> stream) async {
    bool isFirstChunk = true;
    DateTime lastNotify = DateTime.fromMillisecondsSinceEpoch(0);

    // 4.7/5.3/5.4 FIX: stream-level watchdog + throttled notifyListeners +
    // deferred QUICK_REPLIES parse. Prevents infinite spinners on stall,
    // eliminates full-screen rebuild per token, and kills O(n^2) regex.
    await for (final chunk in stream.timeout(
      const Duration(seconds: 60),
      onTimeout: (EventSink<String> sink) {
        sink.add('⚠️ The diagnostic engine took too long to respond. '
                 'Please check your connection and try again.');
        sink.close();
      },
    )) {
      if (chunk.startsWith('[LOADING_STATUS:')) {
        final status = chunk.substring(16, chunk.length - 1);
        _loadingText = status;
        _isLoading = true;
        notifyListeners();
        continue;
      }
      if (isFirstChunk) {
        _isLoading = false;
        _messages.add(ChatMessage(text: chunk, isUser: false));
        isFirstChunk = false;
        notifyListeners();
        lastNotify = DateTime.now();
      } else {
        if (_isLoading) {
          _isLoading = false;
        }
        // Append raw text without full QUICK_REPLIES parse (5.4 fix).
        // Parse runs once on stream completion below.
        _messages.last = ChatMessage(
          text: _messages.last.text + chunk,
          isUser: false,
        );
        // Throttle rebuilds to at most every 50ms (5.3 fix).
        final now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 50) {
          notifyListeners();
          lastNotify = now;
        }
      }
    }

    // Final flush: run QUICK_REPLIES parse once and notify.
    if (_messages.isNotEmpty && !_messages.last.isUser) {
      _messages.last = _parseAiResponse(_messages.last.text);
    }
    notifyListeners();
  }

  /// Safely suspends active OBD hardware connections without destroying stream controllers.
  Future<void> suspendObdConnection() async {
    await _obdProcessor.suspendConnection();
  }

  @override
  void dispose() {
    _agentStatusSub?.cancel();
    _obdProcessor.dispose(); // H1 FIX: release lifecycle callback + hardware
    super.dispose();
  }

  /// Builds a brand-aware acoustic-analysis prompt. Previously this was
  /// hardcoded for BMW only (6.8 FIX).

  Future<bool> _shouldUseLocalVehicleAi(String text) async {
    if (!DiagnosticAdapterManager.instance.isConnected) return false;
    if (await ConnectivityService.instance.isOffline()) return true;
    return _looksLikeVehicleCommand(text);
  }

  bool _looksLikeVehicleCommand(String text) {
    final t = text.toLowerCase();
    return RegExp(
      r'\b(scan|fault|dtc|error code|live data|coolant|rpm|speed|clear|'
      r'coding|routine|adaptation|register battery|ecu|module|dme|dsc|egs|'
      r'frm|cas|brake|engine)\b',
    ).hasMatch(t);
  }

  Future<bool> _tryLocalVehicleAiResponse(
    String text,
    Map<String, dynamic> carProfile,
  ) async {
    _startAgentTrace();
    try {
      final pipeline = LocalVehicleAiPipeline();
      final summary = await pipeline.run(text);
      // H4 FIX (audit): on success, resolve the agent-action bubble to
      // `completed` BEFORE clearing the trace id. The previous code cleared
      // the trace and appended the answer but never mutated the "Thinking…"
      // bubble, so its agentState stayed `inProgress` forever — a permanent
      // spinner above the real response.
      if (_activeAgentTraceId != null) {
        _updateAgentActionBubble(
          AiDispatchStatus(AiDispatchPhase.completed, summary),
        );
      }
      _endAgentTrace();
      _isLoading = false;
      _messages.add(ChatMessage(text: summary, isUser: false));
      notifyListeners();

      final vehicleId = carProfile['id']?.toString();
      if (vehicleId != null) {
        await _cache.cacheChatHistory(
          vehicleId,
          _messages.map(_messageToCacheJson).toList(),
        );
      }
      return true;
    } catch (e) {
      debugPrint('ChatController: local vehicle AI pipeline failed — $e');
      if (_activeAgentTraceId != null) {
        _updateAgentActionBubble(
          AiDispatchStatus(
            AiDispatchPhase.failed,
            'Action failed: $e',
          ),
        );
      }
      _endAgentTrace();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Builds an offline DTC summary from the local dictionaries. Used when the
  /// user scanned real codes but lost connectivity before the AI could respond.
  /// 6.11 FIX.
  /// Serializes a [ChatMessage] for the Hive chat-history cache, including
  /// the deferred-analysis fields so offline bubbles can be restored with
  /// their retry button intact after an app kill.
  static Map<String, dynamic> _messageToCacheJson(ChatMessage m) {
    final json = <String, dynamic>{'text': m.text, 'isUser': m.isUser};
    if (m.deferredId != null) json['deferredId'] = m.deferredId;
    return json;
  }

  static String _buildAcousticContext(String make) {
    final m = make.toLowerCase();
    final buffer = StringBuffer(
        '[User has provided an acoustic recording of their $make engine/vehicle for sound analysis.');
    if (m.contains('bmw') || m.contains('mini')) {
      buffer.write(' Cross-reference this with known BMW Group failure modes '
          'like N55 wastegate rattle, N20 timing chain whine, S55 rod bearings, '
          'or belt tensioner squeaks.');
    } else if (m.contains('mercedes') || m.contains('amg')) {
      buffer.write(' Cross-reference with known Mercedes failure modes like '
          'M156/M157 lifters, OM642 glow plugs, balance shaft whine, or '
          'intercooler leak hiss.');
    } else if (m.contains('audi') || m.contains('volkswagen') || m.contains('vw')) {
      buffer.write(' Cross-reference with known VAG failure modes like EA888 '
          'timing chain tensioner, TSI water pump failure, or carbon buildup on '
          'direct-injection intake valves.');
    } else if (m.contains('toyota') || m.contains('lexus')) {
      buffer.write(' Cross-reference with known Toyota/Lexus failure modes like '
          '2AZ-FE oil consumption, Tacoma tailpipe whistle, or hybrid inverter '
          'buzz.');
    } else if (m.contains('honda') || m.contains('acura')) {
      buffer.write(' Cross-reference with known Honda failure modes like '
          'K-series VTC rattle, Earth Dreams direct-inject tick, or V6 '
          'cylinder deactivation shudder.');
    } else if (m.contains('ford')) {
      buffer.write(' Cross-reference with known Ford failure modes like EcoBoost '
          'wastegate rattle, 5.4L V8 cam phaser knock, or PowerShift '
          'transmission shudder.');
    } else if (m.contains('chevrolet') || m.contains('chevy') || m.contains('gm')) {
      buffer.write(' Cross-reference with known GM failure modes like LS '
          'lifter tick, 3.6L V6 timing chain, or Active Fuel Management '
          'lifter collapse.');
    } else {
      buffer.write(' Cross-reference this with the most common audible failure '
          'modes for this vehicle according to the active vehicle profile.');
    }
    buffer.write(']');
    return buffer.toString();
  }
}
