import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'cellular_routing_service.dart';

class ObdApiService {
  /// Fetches the description of an OBD-II code from CarAPI.
  static Future<String?> fetchObdDescription(String obdCode) async {
    try {
      final url = Uri.parse('https://carapi.app/api/obd-codes?code=$obdCode');
      final client = CellularHttpClient();
      // C2 FIX: bounded timeout — a half-open TCP connection or a stalled
      // proxy previously hung this Future forever, freezing any caller that
      // awaited it.
      final response =
          await client.get(url).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['data'] != null && (json['data'] as List).isNotEmpty) {
          return json['data'][0]['description']?.toString();
        }
      }
      return null;
    } catch (e) {
      // C2 FIX: the previous string used '\$e' — a literal escaped dollar
      // sign, NOT interpolation — so the real exception was silently dropped
      // and the log just printed the literal text "$e". Now it interpolates.
      debugPrint('ObdApiService Error: $e');
      return null;
    }
  }
}
