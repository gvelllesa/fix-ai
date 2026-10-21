import 'package:flutter/material.dart';

import '../../../core/animations/fix_ai_motion.dart';
import '../../../core/theme/fix_ai_tokens.dart';
import '../../obd/screens/coding_screen.dart';
import '../../obd/screens/ecu_scan_screen.dart';
import '../../obd/screens/flash_tuning_screen.dart';
import '../../obd/screens/live_telemetry_screen.dart';
import '../../obd/screens/service_functions_screen.dart';
import '../../obd/screens/xdrive_control_screen.dart';
import '../../obd/services/bmw_fault_diagnostic_engine.dart';
import '../../obd/services/connection_manager.dart';
import '../../obd/widgets/advanced_connection_dialog.dart';
import '../widgets/fix_ai_drawer.dart';

/// Primary landing screen for FIX AI: professional BMW diagnostic and tuning hub.
/// Designed with Dark-Tech aesthetics, fluid staggered motion, and tactile feedback.
class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic>? carProfile;

  const DashboardScreen({super.key, this.carProfile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late Map<String, dynamic> _carProfile;
  final ConnectionManager _conn = ConnectionManager.instance;

  @override
  void initState() {
    super.initState();
    _carProfile = widget.carProfile ?? {
      'brand': 'BMW',
      'model': 'X4 xDrive28i',
      'chassis': 'F26',
      'engine': 'N20B20A',
      'year': '2016',
      'id': 'primary-vehicle',
    };

    // Preload offline factory database
    BmwFaultDiagnosticEngine.instance.ensureLoaded();
  }

  void _showConnectionModal() {
    showDialog(
      context: context,
      builder: (_) => const AdvancedConnectionDialog(),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openScreen(Widget screen) {
    Navigator.push(
      context,
      SmoothSlidePageRoute(page: screen),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _conn.protocol.isConnected;
    final vehicleTitle = '${_carProfile['brand'] ?? 'BMW'} ${_carProfile['model'] ?? 'F-Series'}';
    final vehicleChassis = '${_carProfile['chassis'] ?? 'F26'} • ${_carProfile['engine'] ?? 'N20'} • ${_carProfile['year'] ?? '2016'}';

    return Scaffold(
      backgroundColor: FixAiTokens.canvas,
      drawer: FixAiDrawer(
        currentCarId: _carProfile['id']?.toString(),
        onVehicleSelected: (car) {
          setState(() => _carProfile = car);
        },
      ),
      appBar: AppBar(
        backgroundColor: FixAiTokens.surfacePrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: FixAiTokens.accentCyan.withValues(alpha: 0.12),
                borderRadius: FixAiTokens.borderRadiusSm,
                border: Border.all(
                  color: FixAiTokens.accentCyan.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: const Icon(Icons.speed, color: FixAiTokens.accentCyan, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FIX AI',
                  style: TextStyle(
                    color: FixAiTokens.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'FACTORY DIAGNOSTICS & TUNING',
                  style: TextStyle(
                    color: FixAiTokens.textMuted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Connection Pill Button with Pulse Indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: BouncyPressable(
              onTap: _showConnectionModal,
              borderRadius: BorderRadius.circular(FixAiTokens.radiusPill),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: isConnected
                      ? FixAiTokens.accentEmerald.withValues(alpha: 0.12)
                      : FixAiTokens.surfaceHighlight,
                  borderRadius: BorderRadius.circular(FixAiTokens.radiusPill),
                  border: Border.all(
                    color: isConnected
                        ? FixAiTokens.accentEmerald.withValues(alpha: 0.5)
                        : FixAiTokens.borderSubtle,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PulsingStatusGlow(
                      isPulsing: isConnected,
                      glowColor: FixAiTokens.accentEmerald,
                      maxRadius: 6,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isConnected ? FixAiTokens.accentEmerald : FixAiTokens.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      isConnected ? 'ENET CONNECTED' : 'OBD CONNECT',
                      style: TextStyle(
                        color: isConnected ? FixAiTokens.accentEmerald : FixAiTokens.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        children: [
          // 1. Vehicle Status HUD Card (Staggered 0)
          StaggeredSlideFade(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: FixAiTokens.surfacePrimary,
                borderRadius: FixAiTokens.borderRadiusLg,
                border: Border.all(color: FixAiTokens.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicleTitle,
                              style: FixAiTokens.titleLarge,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              vehicleChassis,
                              style: TextStyle(
                                color: FixAiTokens.textSecondary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: FixAiTokens.accentBlue.withValues(alpha: 0.12),
                          borderRadius: FixAiTokens.borderRadiusMd,
                          border: Border.all(
                            color: FixAiTokens.accentBlue.withValues(alpha: 0.25),
                          ),
                        ),
                        child: const Icon(
                          Icons.directions_car_filled,
                          color: FixAiTokens.accentBlue,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: FixAiTokens.borderSubtle, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatusChip(
                        icon: Icons.battery_charging_full_rounded,
                        label: '12.4 V',
                        sub: 'KL30 Battery',
                        color: FixAiTokens.accentEmerald,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(
                        icon: Icons.power_settings_new_rounded,
                        label: isConnected ? 'KL15 Active' : 'Ignition OFF',
                        sub: 'Bus Terminal',
                        color: isConnected ? FixAiTokens.accentCyan : FixAiTokens.textMuted,
                      ),
                      const SizedBox(width: 8),
                      _buildStatusChip(
                        icon: Icons.offline_bolt_rounded,
                        label: '200k+ Codes',
                        sub: 'Offline DB',
                        color: FixAiTokens.accentAmber,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // 2. Primary Hero Diagnostic Scanner Card (Staggered 1 - One Thing Leads)
          StaggeredSlideFade(
            index: 1,
            child: ShimmerGlowBorder(
              borderRadius: FixAiTokens.borderRadiusLg,
              primaryColor: FixAiTokens.accentEmerald,
              secondaryColor: FixAiTokens.accentCyan,
              borderWidth: 1.5,
              child: BouncyPressable(
                onTap: () => _openScreen(EcuScanScreen(activeProtocol: _conn.protocol)),
                borderRadius: FixAiTokens.borderRadiusLg,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        FixAiTokens.surfaceElevated,
                        FixAiTokens.surfacePrimary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [FixAiTokens.accentEmerald, FixAiTokens.accentCyan],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: FixAiTokens.borderRadiusMd,
                              boxShadow: [
                                BoxShadow(
                                  color: FixAiTokens.accentEmerald.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.health_and_safety_rounded,
                                color: Color(0xFF090C10),
                                size: 28,
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'FULL VEHICLE DIAGNOSTICS',
                                      style: TextStyle(
                                        color: FixAiTokens.textPrimary,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.6,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: FixAiTokens.accentEmerald.withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'FAST',
                                        style: TextStyle(
                                          color: FixAiTokens.accentEmerald,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  'Scan all 32 ECUs with authentic factory definitions, freeze frames, and clear step-by-step repair guides.',
                                  style: TextStyle(
                                    color: FixAiTokens.textSecondary,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Icon(
                            Icons.arrow_forward_ios_rounded,
                            color: FixAiTokens.accentEmerald,
                            size: 16,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // 3. Section Title (Staggered 2)
          StaggeredSlideFade(
            index: 2,
            child: Row(
              children: [
                Icon(
                  Icons.dashboard_customize_rounded,
                  color: FixAiTokens.textSecondary,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  'WORKSHOP OPERATIONS & CONTROL',
                  style: FixAiTokens.sectionHeader,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. Staggered Grid of Dedicated Modules (Staggered 3-8)
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              StaggeredSlideFade(
                index: 3,
                child: _buildFeatureCard(
                  title: 'Service Routines',
                  desc: 'Battery register, brake bleed, adaptations',
                  icon: Icons.home_repair_service_rounded,
                  accentColor: FixAiTokens.accentAmber,
                  onTap: () => _openScreen(const ServiceFunctionsScreen()),
                ),
              ),
              StaggeredSlideFade(
                index: 4,
                child: _buildFeatureCard(
                  title: 'Live Telemetry',
                  desc: 'High-speed UDS gauges, boost, AFR, temps',
                  icon: Icons.speed_rounded,
                  accentColor: FixAiTokens.accentCyan,
                  onTap: () => _openScreen(LiveTelemetryScreen(activeProtocol: _conn.protocol)),
                ),
              ),
              StaggeredSlideFade(
                index: 5,
                child: _buildFeatureCard(
                  title: 'Factory Coding',
                  desc: 'SALAPA orders, FDL cheat codes, backups',
                  icon: Icons.terminal_rounded,
                  accentColor: FixAiTokens.accentPurple,
                  onTap: () => _openScreen(const CodingScreen()),
                ),
              ),
              StaggeredSlideFade(
                index: 6,
                child: _buildFeatureCard(
                  title: 'Flash & Calibrate',
                  desc: 'Custom ROM features, TCU transmissions',
                  icon: Icons.bolt_rounded,
                  accentColor: FixAiTokens.accentAmber,
                  onTap: () => _openScreen(FlashTuningScreen(activeProtocol: _conn.protocol)),
                ),
              ),
              StaggeredSlideFade(
                index: 7,
                child: _buildFeatureCard(
                  title: 'xDrive AWD Control',
                  desc: 'Dynamic AWD torque split, 100% RWD drift',
                  icon: Icons.alt_route_rounded,
                  accentColor: FixAiTokens.accentCyan,
                  onTap: () => _openScreen(const XDriveControlScreen()),
                ),
              ),
              StaggeredSlideFade(
                index: 8,
                child: _buildFeatureCard(
                  title: 'ECU Topology Tree',
                  desc: 'Scan 32 ECUs, module identification DIDs',
                  icon: Icons.hub_rounded,
                  accentColor: FixAiTokens.accentEmerald,
                  onTap: () => _openScreen(EcuScanScreen(activeProtocol: _conn.protocol)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String label,
    required String sub,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: FixAiTokens.surfaceElevated,
          borderRadius: FixAiTokens.borderRadiusSm,
          border: Border.all(color: FixAiTokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: FixAiTokens.textMuted, fontSize: 9),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required String title,
    required String desc,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return BouncyPressable(
      onTap: onTap,
      borderRadius: FixAiTokens.borderRadiusMd,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: FixAiTokens.surfacePrimary,
          borderRadius: FixAiTokens.borderRadiusMd,
          border: Border.all(color: FixAiTokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: FixAiTokens.borderRadiusSm,
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: FixAiTokens.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: FixAiTokens.textSecondary,
                fontSize: 10,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
