import 'package:flutter/material.dart';

import '../services/bmw_fault_diagnostic_engine.dart';
import '../services/offline_database_manager.dart';

/// One scanned ECU with its raw fault strings.
class ScannedEcuFaults {
  final int address;
  final String appLabel;
  final List<String> faultCodes;
  const ScannedEcuFaults(this.address, this.appLabel, this.faultCodes);
}

/// Fully offline fault results: shows official BMW factory texts,
/// English definitions, and comprehensive Georgian diagnostics with repair steps.
/// Completely neutral: zero mentions of external software/tool names.
class BmwDiagnosticResultsSheet extends StatefulWidget {
  final List<ScannedEcuFaults> ecus;
  final VoidCallback? onAskAi;

  const BmwDiagnosticResultsSheet({super.key, required this.ecus, this.onAskAi});

  static Future<void> show(
    BuildContext context,
    List<ScannedEcuFaults> ecus, {
    VoidCallback? onAskAi,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121212),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.9,
        maxChildSize: 0.95,
        builder: (ctx, controller) => BmwDiagnosticResultsSheet(ecus: ecus, onAskAi: onAskAi),
      ),
    );
  }

  @override
  State<BmwDiagnosticResultsSheet> createState() => _BmwDiagnosticResultsSheetState();
}

class _BmwDiagnosticResultsSheetState extends State<BmwDiagnosticResultsSheet> {
  static const Color neonGreen = Color(0xFF1DB954);
  static const Color amber = Color(0xFFFFB300);
  static const Color alertRed = Color(0xFFE53935);
  static const Color cardColor = Color(0xFF1E1E1E);

  late final Future<void> _ready = BmwFaultDiagnosticEngine.instance.ensureLoaded();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: neonGreen));
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'ქარხნული ბაზის ჩატვირთვა ვერ მოხერხდა: ${snap.error}',
                style: const TextStyle(color: Colors.white70),
              ),
            ),
          );
        }
        final engine = BmwFaultDiagnosticEngine.instance;
        final items = <Widget>[];
        for (final ecu in widget.ecus) {
          final kisName = OfflineDatabaseManager.instance.resolveEcuByAddress(ecu.address)?.name;
          for (final raw in ecu.faultCodes) {
            final r = engine.explain(ecu.address, raw, ecuNameFromKis: kisName);
            items.add(_FaultCard(result: r, raw: raw, appLabel: ecu.appLabel));
          }
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Icon(Icons.verified, color: neonGreen, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'ქარხნული დიაგნოსტიკა (ოფლაინ)',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'BMW-ს ქარხნული სადიაგნოსტიკო ბაზა. ტექსტები დამოწმებული ოფიციალური ჩანაწერებია; '
              'ბაზაში არარსებულ კოდზე აპლიკაცია განმარტებას არ იგონებს.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 14),
            ...items,
            if (widget.onAskAi != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: widget.onAskAi,
                icon: const Icon(Icons.cloud_outlined, color: amber),
                label: const Text('AI ჩატში გაგზავნა (საჭიროა ინტერნეტი)',
                    style: TextStyle(color: amber)),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _FaultCard extends StatelessWidget {
  final BmwFaultLookupResult result;
  final String raw;
  final String appLabel;
  const _FaultCard({required this.result, required this.raw, required this.appLabel});

  Color _severityColor(String sev) {
    switch (sev.toUpperCase()) {
      case 'CRITICAL':
        return _BmwDiagnosticResultsSheetState.alertRed;
      case 'HIGH':
        return Colors.orangeAccent;
      case 'MEDIUM':
        return _BmwDiagnosticResultsSheetState.amber;
      case 'LOW':
      default:
        return _BmwDiagnosticResultsSheetState.neonGreen;
    }
  }

  @override
  Widget build(BuildContext context) {
    final addr = '0x${result.ecuAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    final sevColor = _severityColor(result.severity);

    return Card(
      color: _BmwDiagnosticResultsSheetState.cardColor,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: sevColor.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: ECU + DTC Badge + Severity
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _BmwDiagnosticResultsSheetState.neonGreen.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _BmwDiagnosticResultsSheetState.neonGreen.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '$addr · ${result.ecuNameFromKis ?? appLabel}',
                    style: const TextStyle(
                      color: _BmwDiagnosticResultsSheetState.neonGreen,
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
                    fontSize: 14,
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
                  ),
                  child: Text(
                    result.severity,
                    style: TextStyle(color: sevColor, fontSize: 10, fontWeight: FontWeight.bold),
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

              // Factory German original
              for (final t in result.factoryTexts) ...[
                Text(
                  '• ${t.text}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12, fontStyle: FontStyle.italic),
                ),
              ],
              const SizedBox(height: 10),

              // Georgian Explanation
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'განმარტება:',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
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
                const Text(
                  'სიმპტომები ავტომობილზე:',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (final sym in result.symptomsKa)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 2),
                    child: Text('• $sym', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ),
              ],

              // Actionable Repair Steps
              if (result.repairStepsKa.isNotEmpty) ...[
                const SizedBox(height: 10),
                const Text(
                  'მოგვარების ნაბიჯები:',
                  style: TextStyle(
                    color: _BmwDiagnosticResultsSheetState.neonGreen,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                for (final step in result.repairStepsKa)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 3),
                    child: Text(step, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.3)),
                  ),
              ],

              // Glossary Terms
              if (result.glossary.isNotEmpty) ...[
                const Divider(color: Colors.white12, height: 18),
                const Text('ტექნიკური ტერმინები:',
                    style: TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 2),
                for (final g in result.glossary)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text('• ${g.term}: ${g.meaningKa}',
                        style: const TextStyle(color: Colors.white54, fontSize: 11)),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
