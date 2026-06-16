import 'package:vector_math/vector_math_64.dart';

class N55SpatialMap {
  /// Defines relative Vector3 offsets from the central engine anchor (top of engine cover)
  /// x: left/right
  /// y: up/down
  /// z: forward/backward (depth)
  static final Map<String, Vector3> partOffsets = {
    'spark_plugs': Vector3(0.0, -0.05, -0.2), // Running down the center line under the cover
    'air_filter_box': Vector3(-0.3, 0.1, -0.1), // Typically front-left
    'battery': Vector3(0.4, 0.2, 0.5), // Often in the cowl/trunk, but for bay mapping, assume cowl right
    'vanos_solenoid': Vector3(0.0, -0.1, -0.4), // Front of the cylinder head
    'charge_pipe': Vector3(-0.2, -0.1, -0.3), // Driver side throttle body connection
    'oil_filter_housing': Vector3(0.15, 0.05, -0.35), // Front right of engine block
  };

  /// Helper to match the UI chat name to the internal key
  static String mapChatNameToKey(String partName) {
    final lower = partName.toLowerCase();
    if (lower.contains('spark plug') || lower.contains('აალების სანთლები')) return 'spark_plugs';
    if (lower.contains('air filter') || lower.contains('ფილტრი')) return 'air_filter_box';
    if (lower.contains('battery') || lower.contains('აკუმულატორი')) return 'battery';
    if (lower.contains('vanos') || lower.contains('სოლენოიდი')) return 'vanos_solenoid';
    if (lower.contains('charge pipe')) return 'charge_pipe';
    if (lower.contains('oil filter')) return 'oil_filter_housing';
    return 'spark_plugs'; // fallback
  }

  static Vector3 getOffsetForPart(String partName) {
    final key = mapChatNameToKey(partName);
    return partOffsets[key] ?? Vector3(0.0, 0.0, 0.0);
  }
}
