import 'package:flutter/material.dart';

import '../services/bmw_fault_diagnostic_engine.dart';
import '../services/offline_database_manager.dart';

/// One scanned ECU with its raw fault strings (address is the UDS diag address).
class ScannedEcuFaults {
  final int address;
  final String appLabel;
  final List<String> faultCodes;
  const ScannedEcuFaults(this.address, this.appLabel, this.faultCodes);
}

/// Fully offline fault results: shows ONLY official BMW factory texts
/// (ISTA/EDIABAS SGBD) and honest "not found" messages. No network, no AI.
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
            const Text(
              'ქარხნული დიაგნოსტიკა (ოფლაინ)',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            const Text(
              'წყარო: BMW ISTA+ 4.59.30 / EDIABAS SGBD. ტექსტები უცვლელი ოფიციალური ქარხნული ჩანაწერებია; '
              'ბაზაში არარსებულ კოდზე აპლიკაცია განმარტებას არ იგონებს.',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
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

  @override
  Widget build(BuildContext context) {
    final addr = '0x${result.ecuAddress.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    final families = result.factoryTexts.map((t) => t.family.toUpperCase()).toSet().join(', ');
    return Card(
      color: _BmwDiagnosticResultsSheetState.cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$addr · ${result.ecuNameFromKis ?? appLabel} · ${result.dtcHex}',
                style: const TextStyle(
                    color: _BmwDiagnosticResultsSheetState.neonGreen,
                    fontWeight: FontWeight.bold)),
            Text(raw, style: const TextStyle(color: Colors.white38, fontSize: 11)),
            const SizedBox(height: 8),
            if (!result.isKnown)
              Text(result.unknownMessageKa, style: const TextStyle(color: Colors.white70))
            else ...[
              Text(
                result.variantsAgree
                    ? 'ოფიციალური ქარხნული ტექსტი ($families):'
                    : 'ქარხნული ტექსტი განსხვავდება SGBD ვარიანტების მიხედვით — '
                        'ზუსტი ვარიანტი დამოკიდებულია თქვენი ბლოკის მოდიფიკაციაზე:',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              for (final t in result.factoryTexts) ...[
                Text(t.text, style: const TextStyle(color: Colors.white, fontSize: 15)),
                Text('SGBD: ${t.variants.take(6).join(', ')}${t.variants.length > 6 ? ', …' : ''}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11)),
                const SizedBox(height: 6),
              ],
              if (result.glossary.isNotEmpty) ...[
                const Divider(color: Colors.white12),
                const Text('ტერმინების განმარტება:',
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                for (final g in result.glossary)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text('• ${g.term} — ${g.meaningKa}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
