import 'package:flutter/material.dart';

enum ActuationRisk {
  /// Exhaust flap, KOMBI needle sweep — RPM >= 0, speed == 0
  safeParked,

  /// Coolant bleeding (12 min), VANOS full stroke, Wastegate PWM — RPM == 0, speed == 0, V >= 12.2V
  requiresEngineOff,

  /// Cylinder selective cutoff — 550 <= RPM <= 1100, speed == 0, max 1 cylinder at a time
  requiresIdleOnly,
}

class InterlockViolation implements Exception {
  final String messageKa;
  InterlockViolation(this.messageKa);

  @override
  String toString() => messageKa;
}

class ActuationGuard {
  const ActuationGuard._();

  /// Maximum duration a UDS 0x2F ShortTermAdjustment may stay active before
  /// automatically returning control (`0x00`) to the ECU.
  static const Duration maxShortTermActuationDuration = Duration(seconds: 30);

  static void verify({
    required ActuationRisk risk,
    required double? rpm,
    required double? speedKmh,
    required double? voltage,
    int activeCutCylinders = 0,
  }) {
    if (speedKmh == null || speedKmh > 0.5) {
      throw InterlockViolation(
        'აქტუაცია დაბლოკილია: ავტომობილი მოძრაობს ან სიჩქარე უცნობია.',
      );
    }

    switch (risk) {
      case ActuationRisk.safeParked:
        break;
      case ActuationRisk.requiresEngineOff:
        if (rpm == null || rpm > 0) {
          throw InterlockViolation('ეს ტესტი მოითხოვს გამორთულ ძრავს (KOEO).');
        }
        if (voltage == null || voltage < 12.2) {
          throw InterlockViolation('აკუმულატორის ძაბვა < 12.2V — შეაერთეთ დამტენი.');
        }
        break;
      case ActuationRisk.requiresIdleOnly:
        if (rpm == null || rpm < 550 || rpm > 1100) {
          throw InterlockViolation(
            'ცილინდრის გათიშვა დასაშვებია მხოლოდ თბილ უქმ სვლაზე (550–1100 RPM).',
          );
        }
        if (activeCutCylinders >= 1) {
          throw InterlockViolation(
            'ერთდროულად მხოლოდ 1 ცილინდრის გათიშვაა დასაშვები.',
          );
        }
        break;
    }
  }

  /// Displays a mandatory safety confirmation dialog before triggering high-risk
  /// physical component actuations.
  static Future<bool> confirmActuation(
    BuildContext context, {
    required String title,
    required String descriptionKa,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          descriptionKa,
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('გაუქმება', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'დადასტურება',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }
}
