import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PartPriceResult {
  final String partName;
  final double? price;
  final String currency;
  final String storeName;
  final String? url;
  final bool isOem;

  PartPriceResult({
    required this.partName,
    this.price,
    required this.currency,
    required this.storeName,
    this.url,
    required this.isOem,
  });

  factory PartPriceResult.fromJson(Map<String, dynamic> json) {
    return PartPriceResult(
      partName: json['part_name'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble(),
      currency: json['currency'] as String? ?? 'USD',
      storeName: json['store_name'] as String? ?? '',
      url: json['url'] as String?,
      isOem: json['is_oem'] as bool? ?? false,
    );
  }
}

class PartsFinderService {
  static final _supabase = Supabase.instance.client;

  /// Calls the Supabase Edge Function which checks cache first,
  /// then dispatches to the Python scraper backend if needed.
  static Future<List<PartPriceResult>> getPricesForPart(
    String standardPartName,
    String carMake,
    String carModel,
  ) async {
    try {
      final response = await _supabase.functions.invoke(
        'find-part-prices',
        body: {
          'query': standardPartName,
          'make': carMake,
          'model': carModel,
        },
      );

      final data = response.data;
      if (data == null) return _fallbackLinks(standardPartName, carMake, carModel);

      final results = (data['results'] as List? ?? [])
          .map((e) => PartPriceResult.fromJson(e as Map<String, dynamic>))
          .toList();

      return results.isNotEmpty ? results : _fallbackLinks(standardPartName, carMake, carModel);
    } catch (e) {
      debugPrint('[PartsFinderService] Edge Function error: $e');
      return _fallbackLinks(standardPartName, carMake, carModel);
    }
  }

  /// Generates static search links as a fallback when the scraper is unavailable.
  static List<PartPriceResult> _fallbackLinks(String part, String make, String model) {
    final encoded = Uri.encodeComponent('$make $model $part');
    return [
      PartPriceResult(
        partName: part,
        price: null,
        currency: 'GEL',
        storeName: 'MyParts.ge',
        url: 'https://www.myparts.ge/ka/search/?keyword=$encoded',
        isOem: false,
      ),
      PartPriceResult(
        partName: part,
        price: null,
        currency: 'EUR',
        storeName: 'Autodoc',
        url: 'https://www.autodoc.co.uk/search?query=$encoded',
        isOem: false,
      ),
      PartPriceResult(
        partName: part,
        price: null,
        currency: 'USD',
        storeName: 'eBay Motors',
        url: 'https://www.ebay.com/sch/i.html?_nkw=$encoded&_sacat=6030',
        isOem: false,
      ),
    ];
  }

  /// Formats a list of PartPriceResult into a Markdown table string for Gemini to display.
  static String formatAsMarkdown(List<PartPriceResult> results, String partName, String make, String model) {
    if (results.isEmpty) {
      return 'No prices found for **$partName**.';
    }

    final sb = StringBuffer();
    sb.writeln('Here are the current prices for **$partName** for your $make $model:\n');
    sb.writeln('| Store | Price | OEM? | Link |');
    sb.writeln('|-------|-------|------|------|');

    for (final r in results) {
      final priceStr = r.price != null ? '${r.price!.toStringAsFixed(2)} ${r.currency}' : 'See link';
      final oemStr = r.isOem ? '✅ OEM' : '🔧 Aftermarket';
      final linkStr = r.url != null ? '[View](${r.url})' : '-';
      sb.writeln('| ${r.storeName} | $priceStr | $oemStr | $linkStr |');
    }

    sb.writeln('\n*Prices are fetched in real-time. Click links to confirm availability.*');
    return sb.toString();
  }
}
