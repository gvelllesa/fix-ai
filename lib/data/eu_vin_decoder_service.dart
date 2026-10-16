import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'supabase_client.dart';

class EUVinDecoderService {
  /// Decodes a VIN through the server-side `ai-proxy` Supabase Edge Function
  /// so `EU_VIN_API_KEY` is never exposed in the client binary.
  static Future<Map<String, String>?> decodeVin(String vin) async {
    try {
      final client = SupabaseClientManager().client;
      final response = await client.functions.invoke(
        'ai-proxy',
        body: {
          'action': 'eu_vin_decode',
          'vin': vin,
        },
      );

      if (response.status == 200 && response.data != null) {
        final dynamic raw = response.data is String
            ? jsonDecode(response.data as String)
            : response.data;
        if (raw is Map) {
          final data = raw['data'] is Map ? raw['data'] as Map : raw;
          return {
            'make': data['make']?.toString() ?? '',
            'model': data['model']?.toString() ?? '',
            'year': data['year']?.toString() ?? '',
            'market': data['market']?.toString() ?? '',
          };
        }
      } else {
        debugPrint('VIN Decode failed with status: ${response.status}');
      }
      return null;
    } catch (e) {
      debugPrint('Network error during VIN decode: $e');
      return null;
    }
  }
}
