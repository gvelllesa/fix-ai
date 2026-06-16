import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../core/config/env_config.dart';

class EUVinDecoderService {
  static String get _apiKey => EnvConfig.euVinApiKey;
  static const String _apiUrl = 'https://gxvtafqbraaifsnthsyj.supabase.co/functions/v1/api-vin-decode';

  static Future<Map<String, String>?> decodeVin(String vin) async {
    try {
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': _apiKey, // უსაფრთხოების ჰედერი OpenAPI-დან
        },
        body: jsonEncode({
          'vin': vin,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        return {
          'make': data['make']?.toString() ?? '',
          'model': data['model']?.toString() ?? '',
          'year': data['year']?.toString() ?? '',
          'market': data['market']?.toString() ?? '', // ამატებს ბაზრის ინფორმაციასაც (მაგ: EU)
        };
      } else {
        // აქ შეგვიძლია ლოგებში დავბეჭდოთ 401 (API Key ერორი) ან 402 (ლიმიტის ამოწურვა)
        debugPrint('VIN Decode failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('Network error during VIN decode: $e');
      return null;
    }
  }
}
