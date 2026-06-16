import 'dart:convert';
import 'package:http/http.dart' as http;

class VinDecoderService {
  static Future<Map<String, String>?> decodeVin(String vin) async {
    final url = Uri.parse('https://vpic.nhtsa.dot.gov/api/vehicles/decodevin/$vin?format=json');

    try {
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final List<dynamic> results = data['Results'];

        // NHTSA აბრუნებს ბევრ ცვლადს, ჩვენ გვჭირდება კონკრეტულები
        String make = '';
        String model = '';
        String year = '';
        String engine = '';

        for (var item in results) {
          if (item['Variable'] == 'Make') make = item['Value'] ?? '';
          if (item['Variable'] == 'Model') model = item['Value'] ?? '';
          if (item['Variable'] == 'Model Year') year = item['Value'] ?? '';
          if (item['Variable'] == 'Displacement (L)') engine = '${item['Value']}L'; 
        }

        return {
          'make': make,
          'model': model,
          'year': year,
          'engine': engine,
        };
      } else {
        // ერორი სერვერიდან
        return null;
      }
    } catch (e) {
      // ქსელის ერორი
      return null;
    }
  }
}
