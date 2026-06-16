import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class ObdApiService {
  /// Fetches the description of an OBD-II code from CarAPI.
  static Future<String?> fetchObdDescription(String obdCode) async {
    try {
      final url = Uri.parse('https://carapi.app/api/obd-codes?code=\$obdCode');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['data'] != null && (json['data'] as List).isNotEmpty) {
          return json['data'][0]['description']?.toString();
        }
      }
      return null;
    } catch (e) {
      debugPrint('ObdApiService Error: \$e');
      return null;
    }
  }
}
