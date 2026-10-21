import 'package:flutter/material.dart';
import '../services/connection_manager.dart';

/// Automotive Link Status Bar & Operation Progress Monitor (P3.6).
///
/// Clearly communicates connection lifecycle to driver/tuner:
/// 1. Disconnected (Red) - No physical connection
/// 2. Adapter Connected (Amber) - Link to ENET/Wi-Fi/BLE established, waiting for ignition/ECU
/// 3. DME Online (Green) - Diagnostic session active, displaying VIN, Software ID, and Voltage.
class LinkStatusBar extends StatelessWidget {
  final ConnectionSnapshot? customSnapshot;
  final double? flashProgress; // 0.0 to 1.0
  final String? flashStage; // e.g. "Erasing Flash (0x31)", "Writing Blocks (0x36)"
  final VoidCallback? onConnectPressed;

  const LinkStatusBar({
    super.key,
    this.customSnapshot,
    this.flashProgress,
    this.flashStage,
    this.onConnectPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectionSnapshot>(
      valueListenable: ConnectionManager.instance.snapshotNotifier,
      builder: (context, snapshot, _) {
        final activeSnapshot = customSnapshot ?? snapshot;
        final linkState = activeSnapshot.linkState;

        final Color statusColor;
        final String title;
        final String subtitle;
        final IconData icon;

        switch (linkState) {
          case LinkState.disconnected:
            statusColor = const Color(0xFFE53935);
            title = 'DISCONNECTED';
            subtitle = 'No adapter connection detected';
            icon = Icons.link_off_rounded;
            break;
          case LinkState.adapterOnly:
            statusColor = const Color(0xFFFFA000);
            title = 'ADAPTER LINKED';
            subtitle = '${activeSnapshot.host ?? "ENET"}:${activeSnapshot.port ?? 35000} • Ignition OFF or DME unreachable';
            icon = Icons.warning_amber_rounded;
            break;
          case LinkState.ecuResponding:
            statusColor = const Color(0xFF1DB954);
            final vin = activeSnapshot.activeVin ?? 'VIN: OK';
            final volt = activeSnapshot.batteryVoltage != null
                ? '${activeSnapshot.batteryVoltage!.toStringAsFixed(1)}V'
                : '12.6V';
            title = 'DME ONLINE • $volt';
            subtitle = '$vin • Latency: ${activeSnapshot.latencyMs}ms';
            icon = Icons.check_circle_rounded;
            break;
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: statusColor.withValues(alpha: 0.35)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor,
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withValues(alpha: 0.6),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(icon, color: statusColor, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 10,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (linkState == LinkState.disconnected && onConnectPressed != null)
                    TextButton(
                      onPressed: onConnectPressed,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('CONNECT', style: TextStyle(color: Color(0xFF1DB954), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),

              // Real-Time Flashing / Programming Progress Bar
              if (flashProgress != null) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        flashStage ?? 'Flashing in progress...',
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(flashProgress! * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(color: Color(0xFF29B6F6), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: flashProgress!.clamp(0.0, 1.0),
                    backgroundColor: Colors.white12,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF29B6F6)),
                    minHeight: 6,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
