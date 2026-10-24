import 'dart:async';
import 'package:flutter/foundation.dart';
import 'bmw_ecu_scanner.dart';
import 'protocols/bluetooth_strategy.dart';
import 'protocols/enet_hsfz_protocol.dart';
import 'protocols/kdcan_protocol.dart';

enum LinkState {
  disconnected,
  adapterOnly,
  ecuResponding,
}

class ConnectionSnapshot {
  final LinkState linkState;
  final String? host;
  final int? port;
  final bool isDoip;
  final String? activeVin;
  final String? dmeType;
  final int latencyMs;
  final double? batteryVoltage;

  const ConnectionSnapshot({
    required this.linkState,
    this.host,
    this.port,
    this.isDoip = false,
    this.activeVin,
    this.dmeType,
    this.latencyMs = 0,
    this.batteryVoltage,
  });

  ConnectionSnapshot copyWith({
    LinkState? linkState,
    String? host,
    int? port,
    bool? isDoip,
    String? activeVin,
    String? dmeType,
    int? latencyMs,
    double? batteryVoltage,
  }) {
    return ConnectionSnapshot(
      linkState: linkState ?? this.linkState,
      host: host ?? this.host,
      port: port ?? this.port,
      isDoip: isDoip ?? this.isDoip,
      activeVin: activeVin ?? this.activeVin,
      dmeType: dmeType ?? this.dmeType,
      latencyMs: latencyMs ?? this.latencyMs,
      batteryVoltage: batteryVoltage ?? this.batteryVoltage,
    );
  }
}

/// Lifecycle phase of the single, app-wide vehicle session.
enum ConnectionPhase {
  idle,
  searchingAdapter,
  handshaking,
  readingVin,
  probingModules,
  connected,
  reconnecting,
  lost,
  failed,
}

enum ModuleProbeState { pending, probing, online, silent }

/// Discovery state of a single ECU while the session is being established.
class ModuleProbe {
  final int address;
  final String name;
  final String description;
  final ModuleProbeState state;
  final int? latencyMs;

  const ModuleProbe({
    required this.address,
    required this.name,
    required this.description,
    this.state = ModuleProbeState.pending,
    this.latencyMs,
  });

  String get hexAddress =>
      '0x${address.toRadixString(16).toUpperCase().padLeft(2, '0')}';

  ModuleProbe copyWith({ModuleProbeState? state, int? latencyMs}) => ModuleProbe(
        address: address,
        name: name,
        description: description,
        state: state ?? this.state,
        latencyMs: latencyMs ?? this.latencyMs,
      );
}

/// Observable progress of connection establishment and link health.
/// All user-facing strings are Georgian.
class ConnectionProgress {
  final ConnectionPhase phase;
  final String message;
  final List<ModuleProbe> modules;

  /// Where the link broke (e.g. "Wi-Fi ადაპტერი 192.168.16.101:35000").
  final String? failureStage;

  /// Human readable explanation of the failure and what to check.
  final String? failureDetail;
  final DateTime? failureAt;
  final int reconnectAttempt;

  const ConnectionProgress({
    this.phase = ConnectionPhase.idle,
    this.message = '',
    this.modules = const [],
    this.failureStage,
    this.failureDetail,
    this.failureAt,
    this.reconnectAttempt = 0,
  });

  bool get isBusy =>
      phase == ConnectionPhase.searchingAdapter ||
      phase == ConnectionPhase.handshaking ||
      phase == ConnectionPhase.readingVin ||
      phase == ConnectionPhase.probingModules ||
      phase == ConnectionPhase.reconnecting;

  int get onlineCount => modules.where((m) => m.state == ModuleProbeState.online).length;
  int get probedCount => modules
      .where((m) => m.state == ModuleProbeState.online || m.state == ModuleProbeState.silent)
      .length;

  /// Overall 0..1 progress for the connect animation.
  double get progress {
    switch (phase) {
      case ConnectionPhase.idle:
      case ConnectionPhase.failed:
      case ConnectionPhase.lost:
        return 0;
      case ConnectionPhase.searchingAdapter:
        return 0.08;
      case ConnectionPhase.handshaking:
        return 0.18;
      case ConnectionPhase.readingVin:
        return 0.26;
      case ConnectionPhase.probingModules:
        if (modules.isEmpty) return 0.3;
        return 0.3 + 0.7 * (probedCount / modules.length);
      case ConnectionPhase.reconnecting:
        return 0.5;
      case ConnectionPhase.connected:
        return 1;
    }
  }

  ConnectionProgress copyWith({
    ConnectionPhase? phase,
    String? message,
    List<ModuleProbe>? modules,
    String? failureStage,
    String? failureDetail,
    DateTime? failureAt,
    int? reconnectAttempt,
    bool clearFailure = false,
  }) {
    return ConnectionProgress(
      phase: phase ?? this.phase,
      message: message ?? this.message,
      modules: modules ?? this.modules,
      failureStage: clearFailure ? null : (failureStage ?? this.failureStage),
      failureDetail: clearFailure ? null : (failureDetail ?? this.failureDetail),
      failureAt: clearFailure ? null : (failureAt ?? this.failureAt),
      reconnectAttempt: reconnectAttempt ?? this.reconnectAttempt,
    );
  }
}

/// Central Connection Orchestrator for all BMW Diagnostics, Coding, and Flashing.
///
/// Implements ISO 13400/ISO 14229 connection lifecycle:
/// - Single shared [EnetHsfzProtocol] instance across all modules.
/// - Heartbeat monitoring every 2s for [LinkState] verification.
/// - [exclusive] execution mutex to suspend high-frequency telemetry during
///   critical operations (flashing, coding, DTC wiping).
/// - One-time session establishment ([connectVehicle]) with animated module
///   discovery, link-loss detection, and silent automatic re-connection, so no
///   screen ever has to ask the user to connect again.
class ConnectionManager {
  static final ConnectionManager instance = ConnectionManager._internal();

  factory ConnectionManager({EnetHsfzProtocol? protocol}) {
    if (protocol != null) {
      instance._attachProtocol(protocol);
    }
    return instance;
  }

  ConnectionManager._internal() {
    _attachProtocol(EnetHsfzProtocol());
  }

  late EnetHsfzProtocol _protocol;
  EnetHsfzProtocol get protocol => _protocol;

  AdapterEndpoint? _lastEndpoint;
  AdapterEndpoint? get lastEndpoint => _lastEndpoint;

  final ValueNotifier<LinkState> linkStateNotifier = ValueNotifier<LinkState>(LinkState.disconnected);
  LinkState get linkState => linkStateNotifier.value;

  final ValueNotifier<ConnectionSnapshot> snapshotNotifier = ValueNotifier<ConnectionSnapshot>(
    const ConnectionSnapshot(linkState: LinkState.disconnected),
  );
  ConnectionSnapshot get snapshot => snapshotNotifier.value;

  final ValueNotifier<ConnectionProgress> progressNotifier =
      ValueNotifier<ConnectionProgress>(const ConnectionProgress());
  ConnectionProgress get progress => progressNotifier.value;

  final ValueNotifier<bool> isExclusiveLocked = ValueNotifier<bool>(false);
  bool get isExclusiveActive => isExclusiveLocked.value;

  /// True while the shared link to the adapter is up.
  bool get isLinked => _protocol.isConnected;

  /// Addresses of ECUs that answered during the last module discovery.
  Set<int> get onlineModules => progress.modules
      .where((m) => m.state == ModuleProbeState.online)
      .map((m) => m.address)
      .toSet();

  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  Future<bool>? _inFlightConnect;
  bool _userDisconnected = false;
  int _heartbeatMisses = 0;
  Future<void> _exclusiveChain = Future.value();

  static const List<Duration> _reconnectBackoff = [
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 5),
    Duration(seconds: 8),
    Duration(seconds: 13),
  ];

  void _attachProtocol(EnetHsfzProtocol p) {
    _protocol = p;
    _protocol.onLinkLost = _handleLinkLost;
  }

  String _endpointLabel([AdapterEndpoint? ep]) {
    final e = ep ?? _lastEndpoint;
    if (e == null) return 'ადაპტერი';
    if (e.host.startsWith('BLE')) return 'Bluetooth ადაპტერი';
    if (e.host.startsWith('USB')) return 'USB K+DCAN კაბელი';
    return 'Wi-Fi ადაპტერი ${e.host}:${e.port}';
  }

  void _setProgress(ConnectionProgress p) {
    progressNotifier.value = p;
  }

  List<ModuleProbe> _freshModuleList() => BmwEcuScanner.getDefaultFSeriesTopology()
      .map((e) => ModuleProbe(address: e.address, name: e.name, description: e.description))
      .toList();

  // ---------------------------------------------------------------------------
  // One-time session establishment (used by the single connect UI)
  // ---------------------------------------------------------------------------

  /// Establishes the app-wide vehicle session: finds the adapter, opens the
  /// HSFZ/DoIP link, reads the VIN and discovers every responding ECU while
  /// publishing step-by-step [progressNotifier] updates for the UI animation.
  ///
  /// When [kdcan] is supplied the USB K+DCAN cable is used instead of Wi-Fi.
  Future<bool> connectVehicle({
    String? host,
    int? port,
    bool autoDetect = true,
    KdcanProtocol? kdcan,
    DcanMode kdcanMode = DcanMode.dCan,
    bool probeModules = true,
  }) {
    final existing = _inFlightConnect;
    if (existing != null) return existing;
    final f = _connectVehicleImpl(
      host: host,
      port: port,
      autoDetect: autoDetect,
      kdcan: kdcan,
      kdcanMode: kdcanMode,
      probeModules: probeModules,
    );
    _inFlightConnect = f;
    return f.whenComplete(() => _inFlightConnect = null);
  }

  Future<bool> _connectVehicleImpl({
    String? host,
    int? port,
    required bool autoDetect,
    KdcanProtocol? kdcan,
    required DcanMode kdcanMode,
    required bool probeModules,
  }) async {
    _userDisconnected = false;
    _reconnectTimer?.cancel();
    final modules = _freshModuleList();

    // 1. Adapter discovery
    bool linked = false;
    if (kdcan != null) {
      _setProgress(ConnectionProgress(
        phase: ConnectionPhase.handshaking,
        message: 'USB K+DCAN კაბელის ინიციალიზაცია (${kdcanMode.description})...',
        modules: modules,
      ));
      linked = await connectKdcanAdapter(kdcan, mode: kdcanMode, probeIdentity: false);
      if (!linked) {
        return _fail(
          modules,
          stage: 'USB K+DCAN კაბელი',
          detail: 'კაბელი ვერ მოიძებნა ან USB ნებართვა არ არის მიცემული. შეამოწმეთ OTG ადაპტერი.',
        );
      }
    } else {
      String targetHost = (host == null || host.trim().isEmpty) ? '192.168.16.101' : host.trim();
      int targetPort = port ?? 35000;
      bool? useDoip;

      if (autoDetect) {
        _setProgress(ConnectionProgress(
          phase: ConnectionPhase.searchingAdapter,
          message: 'Wi-Fi ადაპტერის ძებნა ქსელში...',
          modules: modules,
        ));
        AdapterEndpoint? found;
        try {
          found = await _protocol.detectAdapter(preferredHost: host);
        } catch (_) {
          found = null;
        }
        if (found == null) {
          return _fail(
            modules,
            stage: 'Wi-Fi ადაპტერი',
            detail: 'ქსელში ადაპტერი ვერ მოიძებნა. დარწმუნდით, რომ ტელეფონი ადაპტერის Wi-Fi ქსელზეა მიერთებული და ადაპტერი OBD პორტშია ჩართული.',
          );
        }
        targetHost = found.host;
        targetPort = found.port;
        useDoip = found.isDoip;
      }

      final ep = AdapterEndpoint(host: targetHost, port: targetPort, isDoip: useDoip ?? targetPort == 13400);
      _setProgress(ConnectionProgress(
        phase: ConnectionPhase.handshaking,
        message: 'კავშირის დამყარება: $targetHost:$targetPort ${ep.isDoip ? '(DoIP)' : '(HSFZ)'}...',
        modules: modules,
      ));
      linked = await connect(
        host: targetHost,
        port: targetPort,
        useDoip: useDoip,
        probeIdentity: false,
      );
      if (!linked) {
        return _fail(
          modules,
          stage: _endpointLabel(ep),
          detail: 'ადაპტერმა TCP კავშირი უარყო ან არ უპასუხა. გადატვირთეთ ადაპტერი და სცადეთ თავიდან.',
        );
      }
    }

    // 2. Vehicle identity
    _setProgress(ConnectionProgress(
      phase: ConnectionPhase.readingVin,
      message: 'VIN-ის წაკითხვა (DME 0x12 / ZGW 0x10)...',
      modules: modules,
    ));
    String? vin;
    try {
      vin = await _readVinFast(0x12) ?? await _readVinFast(0x10);
    } catch (_) {}
    if (vin != null && vin.isNotEmpty) {
      _updateSnapshot(linkState: LinkState.ecuResponding, activeVin: vin);
    }

    // 3. Module discovery
    var current = modules;
    if (probeModules) {
      isExclusiveLocked.value = true;
      try {
        for (var i = 0; i < current.length; i++) {
          if (!_protocol.isConnected) {
            return _fail(
              current,
              stage: '${_endpointLabel()} — ${current[i].name} (${current[i].hexAddress}) ბლოკის გამოკითხვისას',
              detail: 'ადაპტერთან კავშირი გაწყდა ბლოკების გამოკითხვის დროს. შეამოწმეთ ადაპტერის კვება და Wi-Fi სიგნალი.',
            );
          }
          current = List.of(current)..[i] = current[i].copyWith(state: ModuleProbeState.probing);
          _setProgress(progress.copyWith(
            phase: ConnectionPhase.probingModules,
            message: '${current[i].name} (${current[i].hexAddress}) ბლოკთან დაკავშირება...',
            modules: current,
          ));
          final sw = Stopwatch()..start();
          final ok = await _probeModule(current[i].address);
          sw.stop();
          current = List.of(current)
            ..[i] = current[i].copyWith(
              state: ok ? ModuleProbeState.online : ModuleProbeState.silent,
              latencyMs: ok ? sw.elapsedMilliseconds : null,
            );
          _setProgress(progress.copyWith(modules: current));
        }
      } finally {
        isExclusiveLocked.value = false;
      }
    }

    final online = current.where((m) => m.state == ModuleProbeState.online).length;
    if (probeModules && online == 0 && (vin == null || vin.isEmpty)) {
      // Adapter is reachable but the vehicle bus is silent: keep the link but
      // tell the user precisely where the chain stops.
      _updateSnapshot(linkState: LinkState.adapterOnly);
      _setProgress(ConnectionProgress(
        phase: ConnectionPhase.connected,
        message: 'ადაპტერი დაკავშირებულია, მაგრამ ბლოკები არ პასუხობენ',
        modules: current,
        failureStage: 'მანქანის შიდა ქსელი (ZGW 0x10)',
        failureDetail: 'ადაპტერთან კავშირი არის, თუმცა არც ერთი ბლოკი არ პასუხობს. ჩართეთ ანთება (KL15) და გადაამოწმეთ ადაპტერის OBD შეერთება.',
        failureAt: DateTime.now(),
      ));
    } else {
      if (online > 0) _updateSnapshot(linkState: LinkState.ecuResponding);
      _setProgress(ConnectionProgress(
        phase: ConnectionPhase.connected,
        message: probeModules
            ? 'დაკავშირებულია: $online / ${current.length} ბლოკი პასუხობს'
            : 'დაკავშირებულია',
        modules: current,
      ));
    }
    _heartbeatMisses = 0;
    _startHeartbeat();
    return true;
  }

  bool _fail(List<ModuleProbe> modules, {required String stage, required String detail}) {
    _setProgress(ConnectionProgress(
      phase: ConnectionPhase.failed,
      message: 'დაკავშირება ვერ მოხერხდა',
      modules: modules,
      failureStage: stage,
      failureDetail: detail,
      failureAt: DateTime.now(),
    ));
    if (_protocol.isConnected) {
      _protocol.onLinkLost = null;
      _protocol.disconnect().whenComplete(() => _protocol.onLinkLost = _handleLinkLost);
    }
    _stopHeartbeat();
    _updateSnapshot(linkState: LinkState.disconnected);
    return false;
  }

  Future<String?> _readVinFast(int ecu) async {
    final rsp = await _protocol.sendUdsAndAwait(
      ecu,
      const [0x22, 0xF1, 0x90],
      timeout: const Duration(milliseconds: 1500),
      p2Star: const Duration(seconds: 2),
      maxPending: 3,
    );
    if (rsp == null || rsp.length < 4 || rsp[0] != 0x62) return null;
    final vin = String.fromCharCodes(rsp.sublist(3).where((b) => b >= 0x20 && b <= 0x7E)).trim();
    if (vin.isEmpty) return null;
    return vin.length >= 17 ? vin.substring(0, 17) : vin;
  }

  /// TesterPresent probe. Any reply (positive or negative) means the ECU is alive.
  Future<bool> _probeModule(int address) async {
    try {
      final rsp = await _protocol.sendUdsAndAwait(
        address,
        const [0x3E, 0x00],
        timeout: const Duration(milliseconds: 300),
        p2Star: const Duration(milliseconds: 600),
        maxPending: 1,
      );
      return rsp != null && rsp.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // Low-level link API (kept for services / tests)
  // ---------------------------------------------------------------------------

  /// Connects to a vehicle adapter endpoint and starts link monitoring
  Future<bool> connect({
    String host = '192.168.16.101',
    int port = 35000,
    bool? useDoip,
    Duration timeout = const Duration(seconds: 4),
    bool probeIdentity = true,
  }) async {
    _userDisconnected = false;
    // Suppress link-lost notifications caused by the protocol's own
    // disconnect-before-connect step.
    _protocol.onLinkLost = null;
    bool success;
    try {
      success = await _protocol.connect(
        host: host,
        port: port,
        useDoip: useDoip,
        timeout: timeout,
      );
    } finally {
      _protocol.onLinkLost = _handleLinkLost;
    }

    if (success) {
      _lastEndpoint = AdapterEndpoint(host: host, port: port, isDoip: useDoip ?? (port == 13400));
      _updateSnapshot(
        linkState: LinkState.adapterOnly,
        host: host,
        port: port,
        isDoip: _lastEndpoint!.isDoip,
      );
      _startHeartbeat();
      if (probeIdentity) {
        await _probeEcuIdentity();
        if (progress.phase != ConnectionPhase.connected) {
          _setProgress(progress.copyWith(
            phase: ConnectionPhase.connected,
            message: 'დაკავშირებულია',
            clearFailure: true,
          ));
        }
      }
      return true;
    } else {
      _updateSnapshot(linkState: LinkState.disconnected);
      return false;
    }
  }

  /// Automatically detects and connects to any active BMW ENET/DoIP gateway
  /// using UDP broadcast port 6811 discovery first, then candidate IP scan.
  Future<bool> autoConnect({Duration timeout = const Duration(seconds: 4)}) async {
    final detected = await _protocol.detectAdapter();
    if (detected == null) return false;
    return connect(
      host: detected.host,
      port: detected.port,
      useDoip: detected.isDoip,
      timeout: timeout,
    );
  }

  /// Attaches an active BLE ISO-TP adapter ([BluetoothStrategy]) so all BMW
  /// services (Scanner, Coding, Service Functions, Telemetry) work over Bluetooth.
  Future<bool> connectBleAdapter(BluetoothStrategy bleStrategy) async {
    if (!bleStrategy.isConnected) return false;
    final isoOk = await bleStrategy.initializeBmwIsoTpCan();
    if (!isoOk) return false;

    _userDisconnected = false;
    _protocol.attachBleStrategy(bleStrategy);
    _lastEndpoint = null;
    _updateSnapshot(
      linkState: LinkState.adapterOnly,
      host: 'BLE-ISO-TP',
      port: 0,
      isDoip: false,
    );
    _startHeartbeat();
    await _probeEcuIdentity();
    _setProgress(progress.copyWith(phase: ConnectionPhase.connected, message: 'დაკავშირებულია', clearFailure: true));
    return true;
  }

  /// Attaches an active USB INPA K+DCAN cable ([KdcanProtocol]) so all BMW
  /// E-Series and F-Series services work over FTDI USB-Serial K-Line / D-CAN.
  Future<bool> connectKdcanAdapter(
    KdcanProtocol kdcanProtocol, {
    DcanMode mode = DcanMode.dCan,
    bool probeIdentity = true,
  }) async {
    if (!kdcanProtocol.isConnected) {
      final initOk = await kdcanProtocol.initialize(mode: mode);
      if (!initOk) return false;
    }

    _userDisconnected = false;
    _protocol.attachKdcanProtocol(kdcanProtocol);
    _lastEndpoint = null;
    _updateSnapshot(
      linkState: LinkState.adapterOnly,
      host: 'USB-KDCAN-${mode.name.toUpperCase()}',
      port: kdcanProtocol.baudrate,
      isDoip: false,
    );
    _startHeartbeat();
    if (probeIdentity) {
      await _probeEcuIdentity();
      _setProgress(progress.copyWith(phase: ConnectionPhase.connected, message: 'დაკავშირებულია', clearFailure: true));
    }
    return true;
  }

  /// Reconnects to the last known successfully connected endpoint
  Future<bool> reconnectToLastEndpoint({Duration timeout = const Duration(seconds: 3)}) async {
    final ep = _lastEndpoint;
    if (ep == null) return false;
    return connect(
      host: ep.host,
      port: ep.port,
      useDoip: ep.isDoip,
      timeout: timeout,
    );
  }

  /// Shared "is the vehicle reachable?" check for every service and screen.
  ///
  /// - For the shared protocol: returns `true` when linked. If a session was
  ///   established earlier and dropped, re-opens it silently on the same
  ///   endpoint. It never launches adapter discovery on its own, so screens
  ///   never trigger a second connection or a connect prompt.
  /// - For an explicitly injected protocol (tests, custom transports) the
  ///   previous behaviour is preserved.
  Future<bool> ensureLinked([EnetHsfzProtocol? injected]) async {
    if (injected != null && !identical(injected, _protocol)) {
      if (injected.isConnected) return true;
      return injected.connect();
    }
    if (_protocol.isConnected) return true;
    if (_inFlightConnect != null) return _inFlightConnect!;
    if (_lastEndpoint != null && !_userDisconnected) {
      return reconnectToLastEndpoint();
    }
    return false;
  }

  /// Disconnects from the current adapter and cancels heartbeat monitoring
  Future<void> disconnect() async {
    _userDisconnected = true;
    _reconnectTimer?.cancel();
    _stopHeartbeat();
    _protocol.onLinkLost = null;
    try {
      await _protocol.disconnect();
    } finally {
      _protocol.onLinkLost = _handleLinkLost;
    }
    _updateSnapshot(linkState: LinkState.disconnected);
    _setProgress(const ConnectionProgress());
  }

  /// Executes an operation with exclusive bus ownership.
  ///
  /// Automatically suspends background telemetry and polling to prevent
  /// bus contention, packet collisions, or safety interlock drops during
  /// DME flashing, ECU coding, or actuator tests.
  Future<T> exclusive<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _exclusiveChain = _exclusiveChain.then((_) async {
      isExclusiveLocked.value = true;
      try {
        final result = await operation();
        completer.complete(result);
      } catch (err, stack) {
        completer.completeError(err, stack);
      } finally {
        isExclusiveLocked.value = false;
      }
    });
    return completer.future;
  }

  // ---------------------------------------------------------------------------
  // Link health: heartbeat, loss detection, silent re-connection
  // ---------------------------------------------------------------------------

  void _handleLinkLost(String reason) {
    if (_userDisconnected) return;
    _stopHeartbeat();
    _updateSnapshot(linkState: LinkState.disconnected);
    final label = _endpointLabel();
    final detail = reason.startsWith('socket_error')
        ? 'ადაპტერთან TCP კავშირი შეცდომით დაიხურა. შესაძლოა სუსტია Wi-Fi სიგნალი ან ადაპტერს კვება მოეხსნა.'
        : 'ადაპტერმა კავშირი დახურა. შესაძლოა ანთება გამოირთო ან ადაპტერი გადაიტვირთა.';
    _setProgress(progress.copyWith(
      phase: ConnectionPhase.lost,
      message: 'კავშირი გაწყდა',
      failureStage: label,
      failureDetail: detail,
      failureAt: DateTime.now(),
      reconnectAttempt: 0,
    ));
    _scheduleReconnect(0);
  }

  void _scheduleReconnect(int attempt) {
    _reconnectTimer?.cancel();
    if (_userDisconnected || _lastEndpoint == null) return;
    if (attempt >= _reconnectBackoff.length) {
      _setProgress(progress.copyWith(
        phase: ConnectionPhase.failed,
        message: 'ავტომატური აღდგენა ვერ მოხერხდა',
      ));
      return;
    }
    _reconnectTimer = Timer(_reconnectBackoff[attempt], () async {
      if (_userDisconnected || _protocol.isConnected) return;
      _setProgress(progress.copyWith(
        phase: ConnectionPhase.reconnecting,
        message: 'კავშირის აღდგენა (ცდა ${attempt + 1}/${_reconnectBackoff.length})...',
        reconnectAttempt: attempt + 1,
      ));
      final ok = await reconnectToLastEndpoint();
      if (ok) {
        _setProgress(progress.copyWith(
          phase: ConnectionPhase.connected,
          message: 'კავშირი აღდგენილია',
          clearFailure: true,
          reconnectAttempt: 0,
        ));
      } else {
        _setProgress(progress.copyWith(phase: ConnectionPhase.lost, message: 'კავშირი გაწყდა'));
        _scheduleReconnect(attempt + 1);
      }
    });
  }

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (isExclusiveLocked.value) return;
      if (_protocol.isConnected) {
        _performHeartbeat();
      } else if (!_userDisconnected && progress.phase == ConnectionPhase.connected) {
        // Transport dropped without a socket callback (e.g. BLE / USB).
        _handleLinkLost('transport_down');
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  Future<void> _performHeartbeat() async {
    final sw = Stopwatch()..start();
    try {
      // Non-intrusive read of Active Diagnostic Session (DID 0xF186) on DME 0x12
      final resp = await _protocol.sendUdsAndAwait(
        0x12,
        [0x22, 0xF1, 0x86],
        timeout: const Duration(milliseconds: 600),
      );
      sw.stop();

      if (resp != null && resp.isNotEmpty) {
        final hadWarning = _heartbeatMisses >= 3;
        _heartbeatMisses = 0;
        _updateSnapshot(
          linkState: LinkState.ecuResponding,
          latencyMs: sw.elapsedMilliseconds,
        );
        if (hadWarning && progress.phase == ConnectionPhase.connected) {
          _setProgress(progress.copyWith(message: 'DME კვლავ პასუხობს', clearFailure: true));
        }
      } else {
        _registerHeartbeatMiss();
      }
    } catch (_) {
      _registerHeartbeatMiss();
    }
  }

  void _registerHeartbeatMiss() {
    _heartbeatMisses++;
    _updateSnapshot(linkState: LinkState.adapterOnly);
    if (_heartbeatMisses == 3 && progress.phase == ConnectionPhase.connected) {
      _setProgress(progress.copyWith(
        failureStage: 'DME (0x12) — ძრავის მართვის ბლოკი',
        failureDetail: 'ადაპტერთან კავშირი არის, მაგრამ DME აღარ პასუხობს. სავარაუდოდ ანთება გამოირთო (KL15).',
        failureAt: DateTime.now(),
      ));
    }
  }

  Future<void> _probeEcuIdentity() async {
    try {
      final vin = await _protocol.readVin(0x12);
      if (vin != null && vin.isNotEmpty) {
        _updateSnapshot(
          linkState: LinkState.ecuResponding,
          activeVin: vin,
        );
      }
    } catch (_) {}
  }

  void _updateSnapshot({
    LinkState? linkState,
    String? host,
    int? port,
    bool? isDoip,
    String? activeVin,
    String? dmeType,
    int? latencyMs,
    double? batteryVoltage,
  }) {
    if (linkState != null && linkState != linkStateNotifier.value) {
      linkStateNotifier.value = linkState;
    }
    snapshotNotifier.value = snapshotNotifier.value.copyWith(
      linkState: linkState,
      host: host,
      port: port,
      isDoip: isDoip,
      activeVin: activeVin,
      dmeType: dmeType,
      latencyMs: latencyMs,
      batteryVoltage: batteryVoltage,
    );
  }

  void updateBatteryVoltage(double volts) {
    _updateSnapshot(batteryVoltage: volts);
  }

  void dispose() {
    disconnect();
    linkStateNotifier.dispose();
    snapshotNotifier.dispose();
    progressNotifier.dispose();
    isExclusiveLocked.dispose();
  }
}
