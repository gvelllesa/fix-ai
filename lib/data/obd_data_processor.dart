import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../modules/obd/services/protocols/bluetooth_strategy.dart';
import '../modules/obd/services/protocols/wifi_strategy.dart';
import '../modules/obd/services/protocols/enet_strategy.dart';
import '../modules/obd/services/adapter_connection_constants.dart';
import '../modules/obd/services/diagnostic_connection_exception.dart';
import '../modules/obd/services/obd_scan_exception.dart';
import '../core/services/vehicle_protocol_service.dart';
import '../core/services/app_lifecycle_manager.dart';

/// Architectural bridge for ELM327 Bluetooth/Wi-Fi and ENET Hardware.
///
/// PURGED: this class previously contained a `_generateMockObdData()` helper
/// and a `lastScanWasMock` flag that fabricated fake DTCs whenever a real
/// adapter was unreachable. That behaviour misled users — they saw "real"
/// codes for a car the app had never talked to. It has been removed. Now,
/// if a scan fails, [ObdScanException] is thrown and the caller must show
/// the error honestly.
class ObdDataProcessor {
  final VehicleProtocolService _protocolService = VehicleProtocolService();

  // Strategies
  final BluetoothStrategy _bluetoothStrategy = BluetoothStrategy();
  final WifiStrategy _wifiStrategy = WifiStrategy();

  // H1 FIX (audit): this processor is NOT a singleton — it is constructed
  // fresh per ChatController. Its constructor used to register a pause
  // callback with AppLifecycleManager and never unregister it, so every new
  // owner leaked a closure (retaining this processor + its strategies) into
  // the singleton's list for app lifetime. We now hold the deregister handle
  // and invoke it in dispose().
  VoidCallback? _deregisterPause;

  ObdDataProcessor() {
    // 3.6 FIX: auto-suspend hardware on background regardless of which
    // screen is mounted.
    _deregisterPause =
        AppLifecycleManager().registerOnPause(suspendConnection);
  }

  /// Initiates hardware scan using the specified interface.
  ///
  /// Throws [ObdScanException] on any failure (no adapter, no ECU response,
  /// unsupported interface, ...). Never returns fabricated / mock codes.
  Future<List<String>> scanAndExtractFaultCodes(
    String carModel,
    String interfaceType, {
    BluetoothDevice? bluetoothDevice,
    String wifiIp = WifiStrategy.defaultIp,
    int wifiPort = WifiStrategy.defaultPort,
    String? bmwChassisCode,
  }) async {
    debugPrint('OBD-II: Initiating hardware scan via $interfaceType...');

    try {
      if (interfaceType == 'Wi-Fi') {
        return await _scanWifi(wifiIp, wifiPort);
      } else if (interfaceType == 'Bluetooth') {
        return await _scanBluetooth(bluetoothDevice);
      } else if (interfaceType == 'ENET') {
        return await _scanEnet(
          bmwChassisCode,
          wifiIp: wifiIp,
          wifiPort: wifiPort,
        );
      } else {
        throw ObdScanException(
          ObdScanFailureReason.interfaceUnsupported,
          '$interfaceType interface is not supported. Use Wi-Fi, Bluetooth, or ENET.',
        );
      }
    } finally {
      // Always release hardware — no lingering sockets / GATT connections.
      await _wifiStrategy.disconnect();
      await _bluetoothStrategy.disconnect();
    }
  }

  // ------------------------------------------------------------------
  // Per-interface scan paths
  // ------------------------------------------------------------------

  Future<List<String>> _scanWifi(String ip, int port) async {
    final connected = await _wifiStrategy.connect(ip: ip, port: port);
    if (!connected) {
      throw ObdScanException(
        ObdScanFailureReason.adapterUnreachable,
        _wifiStrategy.lastConnectionError ??
            'Could not reach the Wi-Fi OBD-II adapter at $ip:$port. '
            'Check that your phone is joined to the adapter\'s Wi-Fi network '
            'and that the IP/port match.',
      );
    }
    return await _readDtcsViaStream(_wifiStrategy);
  }

  Future<List<String>> _scanBluetooth(BluetoothDevice? device) async {
    if (device == null) {
      throw const ObdScanException(
        ObdScanFailureReason.noDeviceSelected,
        'No Bluetooth adapter selected. Pick your OBD-II adapter first.',
      );
    }
    debugPrint('OBD-II: Connecting to ${device.platformName} (${device.remoteId})...');
    final connected = await _bluetoothStrategy.connect(device);
    if (!connected) {
      throw ObdScanException(
        ObdScanFailureReason.adapterUnreachable,
        _bluetoothStrategy.lastConnectionError ??
            'Could not connect to the Bluetooth adapter "${device.platformName}". '
            'Make sure it is powered and paired to this phone.',
      );
    }
    return await _readDtcsViaStream(_bluetoothStrategy);
  }

  Future<List<String>> _scanEnet(
    String? bmwChassisCode, {
    required String wifiIp,
    required int wifiPort,
  }) async {
    debugPrint('OBD-II: ENET DoIP requested. Connecting via EnetStrategy...');
    final enet = EnetStrategy();
    try {
      final ip =
          wifiIp == WifiStrategy.defaultIp ? EnetStrategy.defaultEnetIp : wifiIp;
      final ports = wifiPort == WifiStrategy.defaultPort ||
              wifiPort == EnetStrategy.doipPort
          ? AdapterConnectionConstants.portSweepOrder
          : [wifiPort, ...AdapterConnectionConstants.portSweepOrder
              .where((p) => p != wifiPort)];

      DiagnosticConnectionException? lastDce;
      var connected = false;
      for (final port in ports) {
        try {
          debugPrint('OBD-II: ENET trying $ip:$port…');
          if (bmwChassisCode != null && bmwChassisCode.isNotEmpty) {
            await enet.connectForChassisCode(bmwChassisCode, ip: ip, port: port);
          } else {
            await enet.connect(ip: ip, port: port);
          }
          connected = true;
          break;
        } on DiagnosticConnectionException catch (e) {
          lastDce = e;
          await enet.disconnect();
        }
      }
      if (!connected) {
        throw lastDce ??
            DiagnosticConnectionException(
              stage: DiagnosticStage.socketEstablishment,
              message: 'All diagnostic ports closed on $ip '
                  '(${ports.join(', ')}).',
              troubleshootingTip: kCriticalMobileDataWarning,
            );
      }

      // Full-vehicle scan across all known ECUs if we have a chassis profile,
      // otherwise gateway-only. Both read paths throw on socket timeout or
      // malformed response; they only return a list when the ECU positively
      // answered.
      List<String> codes;
      if (enet.chassisProfile != null) {
        debugPrint('OBD-II: ENET full-vehicle scan across '
            '${enet.chassisProfile!.ecus.length} ECUs...');
        final byEcu = await enet.readDtcsFromAllEcus();
        codes = byEcu.values.expand((c) => c).toSet().toList();
        debugPrint('OBD-II: ENET full-vehicle scan returned ${codes.length} unique DTC(s) '
            'from ${byEcu.length} ECU(s).');
      } else {
        codes = await enet.readDtcs();
        debugPrint('OBD-II: ENET gateway-only returned ${codes.length} DTCs: $codes');
      }
      return codes;
    } finally {
      await enet.disconnect();
      enet.dispose();
    }
  }

  /// Reads stored DTCs (Mode 03) from a connected ELM327-class strategy.
  Future<List<String>> _readDtcsViaStream(
    dynamic strategy, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    debugPrint('OBD-II: Physical hardware connected! Requesting DTCs (Mode 03)...');

    final completer = Completer<List<String>>();
    StreamSubscription? subscription;
    final buffer = StringBuffer();

    subscription = (strategy.dataStream as Stream<String>).listen((data) {
      buffer.write(data);
      final bufferStr = buffer.toString();

      // ELM327 responses end with a '>' character.
      if (bufferStr.contains('>')) {
        // 3.3 FIX: guard against double-completion.
        if (completer.isCompleted) return;

        final parsedCodes =
            _protocolService.parseObdDtcResponse(bufferStr, DtcType.stored);
        if (parsedCodes.isNotEmpty) {
          completer.complete(parsedCodes.map((e) => e.code).toList());
        } else if (bufferStr.contains('NO DATA') ||
            bufferStr.contains('UNABLE TO CONNECT') ||
            bufferStr.contains('OK')) {
          // "NO DATA" / "UNABLE TO CONNECT" means the adapter answered but
          // the car didn't — treat as empty, not as an error.
          completer.complete([]);
        }
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    try {
      final command = _protocolService.buildElm327Command('03');
      await (strategy.send(command.trim()) as Future<void>);

      final resultCodes = await completer.future.timeout(timeout);
      debugPrint('OBD-II: Received real DTC response: $resultCodes');
      return resultCodes;
    } catch (e) {
      debugPrint('OBD-II: Real stream request failed or timed out: $e');
      throw ObdScanException(
        ObdScanFailureReason.noEcuResponse,
        'The adapter connected but the vehicle ECU did not respond within '
        '${timeout.inSeconds}s. Check that the car is running (or in ACC with '
        'terminal 15 on) and that the adapter matches the car\'s protocol '
        '(CAN / ISO-15765 / KWP).',
        cause: e,
      );
    } finally {
      await subscription.cancel();
    }
  }

  /// Cleanly suspends active connections (for app lifecycle transitions)
  /// without destroying controllers.
  Future<void> suspendConnection() async {
    await _bluetoothStrategy.disconnect();
    await _wifiStrategy.disconnect();
  }

  /// Releases any resources held by this processor. Safe to call multiple
  /// times. Kept for backwards compatibility with callers that previously
  /// relied on the old (mock-capable) processor owning its own streams.
  void dispose() {
    // H1 FIX: drop the lifecycle callback so it stops firing against this
    // (now-disposed) processor and stops retaining it in memory.
    _deregisterPause?.call();
    _deregisterPause = null;
    // Strategies manage their own lifecycle; we just ensure hardware is
    // released synchronously.
    _bluetoothStrategy.disconnect();
    _wifiStrategy.disconnect();
  }

  /// Reads a single live Mode 01 PID from the currently connected adapter.
  /// Returns null when no adapter is connected (no auto-connect — the user
  /// must have established the connection via the OBD Scanner flow first).
  /// Used by GeminiDiagnosticService._fetchLiveVehicleParameter.
  Future<String?> readLivePid(String pidHex) async {
    final bool connected;
    dynamic activeStrategy;
    if (_bluetoothStrategy.isConnected) {
      connected = true;
      activeStrategy = _bluetoothStrategy;
    } else if (_wifiStrategy.isConnected) {
      connected = true;
      activeStrategy = _wifiStrategy;
    } else {
      connected = false;
    }
    if (!connected || activeStrategy == null) return null;

    final completer = Completer<String?>();
    StreamSubscription? subscription;
    final buffer = StringBuffer();

    subscription = (activeStrategy.dataStream as Stream<String>).listen((data) {
      buffer.write(data);
      final bufferStr = buffer.toString();
      if (bufferStr.contains('>')) {
        if (!completer.isCompleted) {
          completer.complete(bufferStr);
        }
      }
    }, onError: (e) {
      if (!completer.isCompleted) completer.completeError(e);
    });

    try {
      final command = _protocolService.buildElm327Command('01 $pidHex');
      await (activeStrategy.send(command.trim()) as Future<void>);

      final raw = await completer.future.timeout(const Duration(seconds: 5));
      await subscription.cancel();
      return raw;
    } catch (e) {
      debugPrint('readLivePid($pidHex) failed: $e');
      await subscription.cancel();
      return null;
    }
    // NOTE: no disconnect here — live reads are expected to be repeated.
  }
}
