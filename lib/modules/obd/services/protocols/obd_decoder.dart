/// ELM327 Protocol Decoder
/// Based on standard open-source OBD-II dictionaries (e.g., python-OBD, obd_metrics).

class ObdDecoder {
  // Standard OBD-II PIDs (Mode 01)
  static const String pidRpm = '010C';
  static const String pidSpeed = '010D';
  static const String pidCoolantTemp = '0105';
  
  // Diagnostic Trouble Codes (Modes 03 and 07)
  static const String pidDtcStored = '03';
  static const String pidDtcPending = '07';

  /// Converts a raw hexadecimal payload from the ELM327 into a human-readable metric string.
  /// 
  /// Example hexData formats:
  /// - RPM (010C): "41 0C 1A F8" -> (A*256 + B) / 4
  /// - Speed (010D): "41 0D 32" -> A
  /// - Coolant (0105): "41 05 7B" -> A - 40
  String parseHexResponse(String hexData, String pid) {
    // Sanitize input
    final cleanHex = hexData.replaceAll(RegExp(r'\s+'), '').toUpperCase();

    // Check if the response matches the requested PID (usually starts with 41 for mode 01)
    if (pid.startsWith('01') && cleanHex.startsWith('41${pid.substring(2)}')) {
      final payloadHex = cleanHex.substring(4); // Remove Mode + PID bytes (e.g., "410C")

      if (payloadHex.isEmpty) return 'Invalid payload';

      try {
        switch (pid) {
          case pidRpm:
            if (payloadHex.length >= 4) {
              final a = int.parse(payloadHex.substring(0, 2), radix: 16);
              final b = int.parse(payloadHex.substring(2, 4), radix: 16);
              final rpm = ((a * 256) + b) / 4.0;
              return '${rpm.toStringAsFixed(0)} RPM';
            }
            break;

          case pidSpeed:
            if (payloadHex.length >= 2) {
              final a = int.parse(payloadHex.substring(0, 2), radix: 16);
              return '$a km/h';
            }
            break;

          case pidCoolantTemp:
            if (payloadHex.length >= 2) {
              final a = int.parse(payloadHex.substring(0, 2), radix: 16);
              final temp = a - 40;
              return '$temp °C';
            }
            break;
        }
      } catch (e) {
        return 'Error parsing hex: $e';
      }
    } else if (pid == pidDtcStored || pid == pidDtcPending) {
      // Basic DTC parsing logic (e.g., 43 01 33 00 00 00 00)
      // Actual DTC bitwise parsing is more complex (P, C, B, U prefixes)
      if (cleanHex.startsWith('43') || cleanHex.startsWith('47')) {
         return 'DTC Codes Detected (Hex: $cleanHex)';
      }
    }

    return 'Unknown or unparseable response: $cleanHex';
  }
}
