import 'package:flutter/material.dart';
import '../../../core/theme/fix_ai_tokens.dart';
import '../services/connection_manager.dart';

/// Automotive Link Status Bar (EvoCare inspired).
///
/// Clearly communicates connection status across the entire application:
/// 1. Disconnected (Red) - No adapter connection detected
/// 2. Adapter Connected (Amber) - Link established, waiting for DME ignition
/// 3. DME Online (Green) - Diagnostic session active with live voltage & latency
///
/// Sub-screens do NOT show reconnect buttons — status is pure and non-intrusive.
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
        final progress = ConnectionManager.instance.progress;

        final Color statusColor;
        final String title;
        final String subtitle;
        final IconData icon;

        switch (linkState) {
          case LinkState.disconnected:
            statusColor = FixAiTokens.accentRose;
            title = 'DISCONNECTED';
            subtitle = progress.failureStage != null
                ? 'შეფერხება: ${progress.failureStage}'
                : 'No adapter connection detected';
            icon = Icons.link_off_rounded;
            break;
          case LinkState.adapterOnly:
            statusColor = FixAiTokens.accentAmber;
            title = 'ADAPTER LINKED';
            subtitle = '${activeSnapshot.host ?? "ENET"}:${activeSnapshot.port ?? 35000} • Ignition OFF or DME unreachable';
            icon = Icons.warning_amber_rounded;
            break;
          case LinkState.ecuResponding:
            statusColor = FixAiTokens.accentEmerald;
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
            color: FixAiTokens.surfacePrimary,
            borderRadius: FixAiTokens.borderRadiusMd,
            border: Border.all(
              color: statusColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: statusColor.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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
                          color: statusColor.withValues(alpha: 0.7),
                          blurRadius: 8,
                          spreadRadius: 1.5,
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
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: FixAiTokens.textSecondary,
                            fontSize: 11,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
                        style: TextStyle(
                          color: FixAiTokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${(flashProgress! * 100).toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: FixAiTokens.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: flashProgress!.clamp(0.0, 1.0),
                    backgroundColor: FixAiTokens.surfaceElevated,
                    valueColor: const AlwaysStoppedAnimation<Color>(FixAiTokens.accentCyan),
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
