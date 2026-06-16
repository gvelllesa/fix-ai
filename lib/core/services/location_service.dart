import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class LocationService {
  // Singleton pattern
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  String? _cachedCountry;
  String? get cachedCountry => _cachedCountry;

  /// Requests location permissions, fetches coordinates, and reverse geocodes to a Country name.
  /// Returns 'Unknown' if permission is denied or an error occurs.
  Future<String> fetchUserCountry() async {
    if (_cachedCountry != null) {
      return _cachedCountry!;
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        return 'Unknown';
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied');
          return 'Unknown';
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        return 'Unknown';
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
        timeLimit: const Duration(seconds: 10),
      );

      final placemarks = await placemarkFromCoordinates(position.latitude, position.longitude);
      
      if (placemarks.isNotEmpty) {
        final country = placemarks.first.country;
        if (country != null && country.isNotEmpty) {
          _cachedCountry = country;
          return country;
        }
      }
      
      return 'Unknown';
    } catch (e) {
      debugPrint('Error fetching location: $e');
      return 'Unknown';
    }
  }
}
