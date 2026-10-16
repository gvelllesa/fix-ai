import 'dart:async';
import 'package:flutter/foundation.dart';
import 'protocols/enet_hsfz_protocol.dart';

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

/// Central Connection Orchestrator for all BMW Diagnostics, Coding, and Flashing.
///
/// Implements ISO 13400/ISO 14229 connection lifecycle:
/// - Single shared [EnetHsfzProtocol] instance across all modules.
/// - Heartbeat monitoring every 2s for [LinkState] verification.
/// - [exclusive] execution mutex to suspend high-frequency telemetry during
///   critical operations (flashing, coding, DTC wiping).
class ConnectionManager {
  static final ConnectionManager instance = ConnectionManager._internal();

  factory ConnectionManager({EnetHsfzProtocol? protocol}) {
    if (protocol != null) {
      instance._protocol = protocol;
    }
    return instance;
  }

  ConnectionManager._internal() {
    _protocol = EnetHsfzProtocol();
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

  final ValueNotifier<bool> isExclusiveLocked = ValueNotifier<bool>(false);

  Timer? _heartbeatTimer;
  bool _isConnecting = false;
  Future<void> _exclusiveChain = Future.value();

  /// Connects to a vehicle adapter endpoint and starts link monitoring
  Future<bool> connect({
    String host = '192.168.16.101',
    int port = 35000,
    bool? useDoip,
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (_isConnecting) return false;
    _isConnecting = true;

    try {
      final success = await _protocol.connect(
        host: host,
        port: port,
        useDoip: useDoip,
        timeout: timeout,
      );

      if (success) {
        _lastEndpoint = AdapterEndpoint(host: host, port: port, isDoip: useDoip ?? (port == 13400));
        _updateSnapshot(
          linkState: LinkState.adapterOnly,
          host: host,
          port: port,
          isDoip: _lastEndpoint!.isDoip,
        );
        _startHeartbeat();
        // Probe ECU identity and active VIN
        await _probeEcuIdentity();
        return true;
      } else {
        _updateSnapshot(linkState: LinkState.disconnected);
        return false;
      }
    } finally {
      _isConnecting = false;
    }
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

  /// Disconnects from the current adapter and cancels heartbeat monitoring
  Future<void> disconnect() async {
    _stopHeartbeat();
    await _protocol.disconnect();
    _updateSnapshot(linkState: LinkState.disconnected);
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

  void _startHeartbeat() {
    _stopHeartbeat();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isExclusiveLocked.value && _protocol.isConnected) {
        _performHeartbeat();
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
        _updateSnapshot(
          linkState: LinkState.ecuResponding,
          latencyMs: sw.elapsedMilliseconds,
        );
      } else {
        _updateSnapshot(linkState: LinkState.adapterOnly);
      }
    } catch (_) {
      _updateSnapshot(linkState: LinkState.adapterOnly);
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
    isExclusiveLocked.dispose();
  }
}
