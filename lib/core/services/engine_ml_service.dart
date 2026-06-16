import 'package:flutter/foundation.dart';

class EngineMLService {
  // Singleton pattern
  static final EngineMLService _instance = EngineMLService._internal();
  factory EngineMLService() => _instance;
  EngineMLService._internal();

  /// Simulates a 3-second delay while the 'camera' scans the engine bay.
  Future<bool> detectEngineBay() async {
    debugPrint("EngineMLService: Scanning for 'car_engine_bay' class...");
    await Future.delayed(const Duration(seconds: 3));
    debugPrint("EngineMLService: 'car_engine_bay' detected with 94% confidence.");
    return true; // Mock success
  }

  /// Maps generic part names to 3D local coordinates (x, y, z) for the AR Node placement.
  /// Coordinates are mocked based on a generic front-engine layout.
  Map<String, double>? getPartCoordinates(String partName) {
    final searchName = partName.toLowerCase();
    
    if (searchName.contains('spark plug') || searchName.contains('აალების სანთლები')) {
      return {'x': 0.0, 'y': -0.1, 'z': -0.8}; // Center top of engine
    } else if (searchName.contains('air filter') || searchName.contains('ჰაერის ფილტრი')) {
      return {'x': -0.3, 'y': 0.1, 'z': -0.6}; // Front left
    } else if (searchName.contains('battery') || searchName.contains('აკუმულატორი')) {
      return {'x': 0.4, 'y': 0.2, 'z': -0.5}; // Front right / cowl
    } else if (searchName.contains('vanos') || searchName.contains('სოლენოიდი')) {
      return {'x': 0.0, 'y': -0.2, 'z': -0.4}; // Very front of engine block
    }
    
    // Default fallback roughly in the middle
    return {'x': 0.0, 'y': 0.0, 'z': -1.0};
  }
}
