import 'package:flutter/foundation.dart';
import 'dart:async';
import '../modules/obd/services/protocols/enet_hsfz_protocol.dart';
import '../modules/obd/services/bmw_ecu_scanner.dart';
import '../modules/obd/services/protocols/bluetooth_strategy.dart';
import '../modules/obd/services/protocols/wifi_strategy.dart';

class ObdDataProcessor {
  // Traditional ELM327 strategies for fallback
  final BluetoothStrategy _bluetoothStrategy = BluetoothStrategy();
  final WifiStrategy _wifiStrategy = WifiStrategy();

  // Real BMW ENET / DoIP protocol engine
  EnetHsfzProtocol? _enetProtocol;
  BmwEcuScanner? _ecuScanner;

  EnetHsfzProtocol get enetProtocol {
    _enetProtocol ??= EnetHsfzProtocol();
    return _enetProtocol!;
  }

  BmwEcuScanner get ecuScanner {
    _ecuScanner ??= BmwEcuScanner(protocol: enetProtocol);
    return _ecuScanner!;
  }

  /// Initiates genuine hardware scan using the specified interface.
  /// Probes real adapter ports [35000, 6801, 13400, 50160] with zero mock fallback.
  Future<List<String>> scanAndExtractFaultCodes(
    String carModel, 
    String interfaceType, {
    String? preferredHost,
    int? preferredPort,
    void Function(String status, double progress)? onProgress,
  }) async {
    debugPrint('[ObdDataProcessor] Initiating genuine hardware scan via $interfaceType...');
    onProgress?.call('Probing hardware adapter...', 0.05);

    final protocol = enetProtocol;
    
    // Attempt real connection
    bool isConnected = false;
    try {
      if (interfaceType == 'ENET' || interfaceType == 'Wi-Fi' || interfaceType == 'Auto') {
        if (preferredHost != null && preferredPort != null) {
          isConnected = await protocol.connect(
            host: preferredHost, 
            port: preferredPort,
            useDoip: preferredPort == 13400,
          );
        } else {
          // Automatic multi-port detection: fast path 192.168.16.101, fallback 192.168.0.10, 169.254.1.1
          final target = await protocol.detectAdapter();
          if (target != null) {
            isConnected = await protocol.connect(
              host: target.host, 
              port: target.port,
              useDoip: target.isDoip,
            );
          }
        }
      } else if (interfaceType == 'Bluetooth') {
        debugPrint('[ObdDataProcessor] Bluetooth interface requires paired BLE OBD adapter.');
        isConnected = false;
      }
    } catch (e) {
      debugPrint('[ObdDataProcessor] Connection error: $e');
      isConnected = false;
    }

    if (!isConnected) {
      debugPrint('[ObdDataProcessor] Physical vehicle connection failed. No simulation fallback.');
      onProgress?.call('Connection failed: Vehicle/adapter not detected', 1.0);
      return [];
    }

    try {
      onProgress?.call('Vehicle connected! Starting ECU topology scan...', 0.2);
      final scanner = BmwEcuScanner(protocol: protocol);
      final scanResult = await scanner.performFullDiagnosticScan(
        onProgress: (stage, prog) => onProgress?.call(stage, prog),
      );

      final codes = scanResult.getAllFaultCodes();
      debugPrint('[ObdDataProcessor] Scan completed. Found ${codes.length} real DTCs across topology.');
      return codes;
    } catch (e) {
      debugPrint('[ObdDataProcessor] Error during diagnostic scan: $e');
      return [];
    } finally {
      // Disconnect cleanly to release sockets
      await protocol.disconnect();
    }
  }

  /// Clears DTCs across all responding ECUs (UDS 0x14 0xFF 0xFF 0xFF)
  Future<int> clearAllFaultCodes({String? host, int? port}) async {
    final protocol = enetProtocol;
    final isConnected = await protocol.connect(
      host: host ?? '192.168.16.101',
      port: port ?? 35000,
    );
    if (!isConnected) return 0;

    try {
      final scanner = BmwEcuScanner(protocol: protocol);
      final topology = BmwEcuScanner.getDefaultFSeriesTopology();
      return await scanner.clearAllFaultCodes(topology);
    } finally {
      await protocol.disconnect();
    }
  }

  /// Reads true vehicle VIN from DME / ZGW (UDS 0x22 0xF1 0x90)
  Future<String?> readVehicleVin({String? host, int? port}) async {
    final protocol = enetProtocol;
    final isConnected = await protocol.connect(
      host: host ?? '192.168.16.101',
      port: port ?? 35000,
    );
    if (!isConnected) return null;

    try {
      return await protocol.readVin(0x12) ?? await protocol.readVin(0x10);
    } finally {
      await protocol.disconnect();
    }
  }

  /// Disposes all internal resources
  void dispose() {
    _enetProtocol?.disconnect();
    _bluetoothStrategy.dispose();
    _wifiStrategy.dispose();
  }
}
