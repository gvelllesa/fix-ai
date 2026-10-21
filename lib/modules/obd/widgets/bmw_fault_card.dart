import 'package:flutter/material.dart';

import '../services/bmw_fault_diagnostic_engine.dart';

/// Standalone, professional BMW factory fault card widget.
/// Renders authentic factory definitions, English titles, Georgian technical explanations,
/// vehicle symptoms, and step-by-step repair instructions directly inline.
class BmwFaultCard extends StatelessWidget {
  final BmwFaultLookupResult result;
  final String raw;
  final String appLabel;
  final VoidCallback? onClearCode;

  static const Color neonGreen = Color(0xFF1DB954);
  static const Color amber = Color(0xFFFFB300);
  static const Color alertRed = Color(0xFFE53935);
  static const Color cardColor = Color(0xFF181C22);

  const BmwFaultCard({
    super.key,
    required this.result,
    required this.raw,
    required this.appLabel,
    this.onClearCode,
  });

  Color _severityColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL':
        return alertRed;
      case 'HIGH':
        return Colors.orangeAccent;
      case 'MEDIUM':
        return amber;
      case 'LOW':
      default:
        return neonGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final addr = '0x${result.ecuAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    final sevColor = _severityColor(result.severity);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: sevColor.withValues(alpha: 0.35), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: ECU Badge + DTC Hex + Severity Badge + Drivability
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: neonGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: neonGreen.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '$addr · ${result.ecuNameFromKis ?? appLabel}',
                    style: const TextStyle(
                      color: neonGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  result.dtcHex,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: sevColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: sevColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    result.severity,
                    style: TextStyle(color: sevColor, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (result.safeToDrive ? Colors.blueAccent : alertRed).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        result.safeToDrive ? Icons.check_circle_outline : Icons.warning_rounded,
                        size: 11,
                        color: result.safeToDrive ? Colors.blueAccent : alertRed,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        result.safeToDrive ? 'მოძრაობა დასაშვებია' : 'მოძრაობა საშიშია',
                        style: TextStyle(
                          color: result.safeToDrive ? Colors.blueAccent : alertRed,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(raw, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 10),

            if (!result.isKnown)
              Text(result.unknownMessageKa, style: const TextStyle(color: Colors.white70))
            else ...[
              // English Title
              Text(
                result.titleEn,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),

              // Factory German Original
              for (final t in result.factoryTexts) ...[
                Text(
                  '• ${t.text}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              const SizedBox(height: 10),

              // Georgian Explanation
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.cyanAccent, size: 14),
                        SizedBox(width: 6),
                        Text(
                          'ქარხნული განმარტება:',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      result.explanationKa,
                      style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                    ),
                  ],
                ),
              ),

              // Symptoms
              if (result.symptomsKa.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: amber, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'სიმპტომები ავტომობილზე:',
                      style: TextStyle(color: amber, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                for (final sym in result.symptomsKa)
                  Padding(
                    padding: const EdgeInsets.only(left: 6, bottom: 2),
                    child: Text('• $sym', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
              ],

              // Actionable Repair Steps
              if (result.repairStepsKa.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Row(
                  children: [
                    Icon(Icons.build_circle_outlined, color: neonGreen, size: 14),
                    SizedBox(width: 6),
                    Text(
                      'მოგვარების ნაბიჯები (ქარხნული რეგლამენტი):',
                      style: TextStyle(
                        color: neonGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final step in result.repairStepsKa)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      step,
                      style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.35),
                    ),
                  ),
              ],

              // Technical Glossary
              if (result.glossary.isNotEmpty) ...[
                const Divider(color: Colors.white12, height: 18),
                const Text(
                  'ტექნიკური ტერმინები:',
                  style: TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const SizedBox(height: 2),
                for (final g in result.glossary)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '• ${g.term}: ${g.meaningKa}',
                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                    ),
                  ),
              ],
            ],

            if (onClearCode != null) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onClearCode,
                  icon: const Icon(Icons.delete_outline, size: 14, color: alertRed),
                  label: const Text('კოდის წაშლა', style: TextStyle(color: alertRed, fontSize: 11)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
