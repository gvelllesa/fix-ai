import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Service to scrape/fetch local Georgian auto parts prices.
class LocalPartsScraperService {
  
  // English to Georgian Automotive Translation Dictionary
  final Map<String, String> _dictionary = {
    'water pump': 'წყლის ტუმბო (პომპა)',
    'brake pads': 'სამუხრუჭე ხუნდები (კალოდკები)',
    'timing chain': 'ძრავის ჯაჭვი (ცეპი)',
    'transmission': 'გადაცემათა კოლოფი (კარობკა)',
    'engine': 'ძრავი (მატორი)',
    'ignition coil': 'ანთების კოჭა (ბაბინა)',
    'spark plug': 'სანთელი (სვეჩი)',
    'battery': 'აკუმულატორი',
    'oil filter': 'ზეთის ფილტრი',
    'air filter': 'ჰაერის ფილტრი',
    'alternator': 'გენერატორი (დინამო)',
    'radiator': 'რადიატორი',
    'thermostat': 'თერმოსტატი',
    'shock absorber': 'ამორტიზატორი',
  };

  /// Translates common english part names to local Georgian terminology
  String _translatePart(String englishName) {
    final lower = englishName.toLowerCase();
    for (final key in _dictionary.keys) {
      if (lower.contains(key)) {
        return _dictionary[key]!;
      }
    }
    return englishName; // fallback
  }

  /// Extracts a recognized part name from a larger text block (e.g. AI diagnosis)
  String? extractRecognizedPart(String text) {
    final lower = text.toLowerCase();
    for (final key in _dictionary.keys) {
      if (lower.contains(key)) {
        return key;
      }
    }
    return null;
  }

  /// Fetches local parts prices from placeholders for Myparts, Tegeta, Amboli
  Future<List<Map<String, dynamic>>> fetchLocalPartsPrices(
      String englishPartName, String vehicleBrand, String vehicleModel) async {
    
    final georgianQuery = _translatePart(englishPartName);
    
    try {
      // Simulate HTTP request delay
      await Future.delayed(const Duration(milliseconds: 800));
      
      // In a real scenario, we'd use http.get to scrape or hit APIs:
      // final response = await http.get(Uri.parse('https://api.myparts.ge/search?q=$georgianQuery'));

      // Mocked realistic data based on the query
      final mockResults = [
        {
          'source_site': 'Myparts.ge',
          'part_title': '$vehicleBrand $vehicleModel - $georgianQuery (მეორადი)',
          'price_gel': 150.0,
          'availability_status': 'In Stock',
        },
        {
          'source_site': 'Tegeta Motors',
          'part_title': '$vehicleBrand $vehicleModel - $georgianQuery (BOSCH ახალი)',
          'price_gel': 320.0,
          'availability_status': 'Available in 2 branches',
        },
        {
          'source_site': 'Amboli',
          'part_title': '$vehicleBrand $vehicleModel - $georgianQuery (OEM)',
          'price_gel': 280.0,
          'availability_status': 'Out of Stock (Pre-order)',
        }
      ];

      return mockResults;

    } catch (e) {
      debugPrint('Error fetching local parts: $e');
      return [];
    }
  }
}
