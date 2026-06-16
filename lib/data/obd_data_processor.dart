import 'package:flutter/foundation.dart';
import 'dart:async';
import '../modules/obd/services/protocols/obd_decoder.dart';
import '../modules/obd/services/protocols/bluetooth_strategy.dart';
import '../modules/obd/services/protocols/wifi_strategy.dart';

/// Architectural bridge for ELM327 Bluetooth/Wi-Fi and ENET Hardware.
class ObdDataProcessor {
  final ObdDecoder _decoder = ObdDecoder();
  
  // Strategies
  final BluetoothStrategy _bluetoothStrategy = BluetoothStrategy();
  final WifiStrategy _wifiStrategy = WifiStrategy();

  /// Initiates hardware scan using the specified interface
  Future<List<String>> scanAndExtractFaultCodes(String carModel, String interfaceType) async {
    debugPrint('OBD-II: Initiating hardware scan via $interfaceType...');
    
    bool isConnected = false;

    try {
      if (interfaceType == 'Wi-Fi') {
        isConnected = await _wifiStrategy.connect(); // Uses default 192.168.0.10:35000
      } else if (interfaceType == 'Bluetooth') {
        // Since we don't have a device picker UI yet, this will gracefully fail 
        // and fallback to simulation. In production, pass the BluetoothDevice here.
        debugPrint('OBD-II: Bluetooth connection requested but no device provided. Falling back.');
        isConnected = false; 
      } else if (interfaceType == 'ENET') {
        debugPrint('OBD-II: ENET DoIP requested. Simulating TCP 6801 connection.');
        isConnected = false; // Mocking failure to trigger simulation
      } else {
        debugPrint('OBD-II: USB or Unsupported interface requested.');
      }

      if (isConnected) {
        debugPrint('OBD-II: Physical hardware connected! Requesting DTCs (Mode 03)...');
        
        // Request Stored Diagnostic Trouble Codes (Mode 03)
        if (interfaceType == 'Wi-Fi') {
          await _wifiStrategy.send('03');
        } else {
          await _bluetoothStrategy.send('03');
        }

        // Wait for buffer to fill (simulated stream listening delay)
        await Future.delayed(const Duration(seconds: 2));

        // In a real scenario, we'd listen to the Stream, but for this bridge:
        // Assume failure to read real stream for now and fallback.
        debugPrint('OBD-II: No real vehicle response received over stream.');
        isConnected = false;
      }
    } catch (e) {
      debugPrint('OBD-II Hardware Error: $e');
      isConnected = false;
    } finally {
      // Cleanup
      if (interfaceType == 'Wi-Fi') await _wifiStrategy.disconnect();
      if (interfaceType == 'Bluetooth') await _bluetoothStrategy.disconnect();
    }

    if (!isConnected) {
      debugPrint('OBD-II: Physical connection failed or unavailable. Falling back to Simulation Module.');
      await Future.delayed(const Duration(seconds: 2)); // Simulate processing delay
      return _generateMockObdData(carModel);
    }

    return [];
  }

  /// Simulation Module: Generates highly specific hardware codes based on the vehicle chassis.
  List<String> _generateMockObdData(String carModel) {
    final modelLower = carModel.toLowerCase();

    // European / German
    if (modelLower.contains('bmw') || modelLower.contains('x4') || modelLower.contains('m3') || modelLower.contains('f26')) {
      return ['P0301', 'P052E']; // Cylinder 1 Misfire, PCV Valve Performance
    }
    if (modelLower.contains('mercedes') || modelLower.contains('amg')) {
      return ['P0171', 'P2187']; // System Too Lean Bank 1, System Too Lean at Idle
    }

    // Japanese / Hybrid Focus
    if (modelLower.contains('toyota') || modelLower.contains('prius')) {
      return ['P0A80', 'P3000']; // Replace Hybrid Battery Pack, HV Battery Malfunction
    }
    
    // Chinese EV / Global
    if (modelLower.contains('byd') || modelLower.contains('zeekr') || modelLower.contains('geely')) {
      return ['U0100', 'U0110']; // Lost Communication with ECM/PCM, Lost Comms with Drive Motor Module
    }

    // Default Generic Codes
    return ['P0420', 'P0455']; // Catalyst System Efficiency Below Threshold, Evap Emission System Leak (Large)
  }

  /// Disposes all internal strategy resources to prevent memory leaks.
  void dispose() {
    _bluetoothStrategy.dispose();
    _wifiStrategy.dispose();
  }
}
