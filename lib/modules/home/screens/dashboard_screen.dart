import 'package:flutter/material.dart';

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
/// Completely replaces the legacy chat with direct automotive workshop tools.
class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic>? carProfile;

  const DashboardScreen({super.key, this.carProfile});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  static const Color neonGreen = Color(0xFF1DB954);
  static const Color darkCard = Color(0xFF161B22);
  static const Color borderLight = Color(0xFF262C36);

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
      MaterialPageRoute(builder: (_) => screen),
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
      backgroundColor: const Color(0xFF0D1117),
      drawer: FixAiDrawer(
        currentCarId: _carProfile['id']?.toString(),
        onVehicleSelected: (car) {
          setState(() => _carProfile = car);
        },
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: neonGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.speed, color: neonGreen, size: 20),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FIX AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                Text(
                  'FACTORY DIAGNOSTICS & TUNING',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Connection Pill Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: InkWell(
              onTap: _showConnectionModal,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isConnected ? neonGreen.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isConnected ? neonGreen : Colors.white24,
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isConnected ? neonGreen : Colors.white38,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isConnected ? 'ENET CONNECTED' : 'OBD CONNECT',
                      style: TextStyle(
                        color: isConnected ? neonGreen : Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
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
        padding: const EdgeInsets.all(16),
        children: [
          // Vehicle Status Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: darkCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderLight),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          vehicleTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          vehicleChassis,
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.directions_car, color: Colors.blueAccent, size: 28),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatusChip(
                      icon: Icons.battery_charging_full,
                      label: '12.4 V',
                      sub: 'KL30 Voltage',
                      color: neonGreen,
                    ),
                    const SizedBox(width: 12),
                    _buildStatusChip(
                      icon: Icons.power,
                      label: isConnected ? 'Terminal 15 ON' : 'Ignition OFF',
                      sub: 'Bus KL15 State',
                      color: isConnected ? Colors.cyanAccent : Colors.white38,
                    ),
                    const SizedBox(width: 12),
                    _buildStatusChip(
                      icon: Icons.verified_user_outlined,
                      label: 'Offline DB',
                      sub: '200k+ Codes Ready',
                      color: Colors.orangeAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // Primary Action: Large Diagnostic Hero Card
          InkWell(
            onTap: () => _openScreen(EcuScanScreen(activeProtocol: _conn.protocol)),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    neonGreen.withValues(alpha: 0.22),
                    const Color(0xFF161B22),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: neonGreen.withValues(alpha: 0.6), width: 1.4),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: neonGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Icon(Icons.health_and_safety, color: Colors.black, size: 30),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'FULL VEHICLE DIAGNOSTICS',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Scan all 32 modules with authentic factory definitions, vehicle symptoms, and step-by-step repair guides.',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.arrow_forward_ios, color: neonGreen, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section Title
          const Row(
            children: [
              Icon(Icons.widgets_outlined, color: Colors.white54, size: 18),
              SizedBox(width: 8),
              Text(
                'WORKSHOP OPERATIONS & CONTROL',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2-Column Grid of Dedicated Modules
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.25,
            children: [
              _buildFeatureCard(
                title: 'Service Functions',
                desc: 'Battery registration, brake bleed, VTG calibration, adaptations',
                icon: Icons.build_circle,
                accentColor: Colors.orangeAccent,
                onTap: () => _openScreen(const ServiceFunctionsScreen()),
              ),
              _buildFeatureCard(
                title: 'Live Telemetry',
                desc: 'Real-time high-speed UDS gauges, boost, AFR, oil temp',
                icon: Icons.speed,
                accentColor: Colors.cyanAccent,
                onTap: () => _openScreen(LiveTelemetryScreen(activeProtocol: _conn.protocol)),
              ),
              _buildFeatureCard(
                title: 'Factory Coding',
                desc: 'SALAPA vehicle orders, FDL cheat codes, module backups',
                icon: Icons.code,
                accentColor: Colors.purpleAccent,
                onTap: () => _openScreen(const CodingScreen()),
              ),
              _buildFeatureCard(
                title: 'Flash & Calibration',
                desc: 'Custom ROM features, TCU transmission calibrations',
                icon: Icons.bolt,
                accentColor: Colors.amberAccent,
                onTap: () => _openScreen(FlashTuningScreen(activeProtocol: _conn.protocol)),
              ),
              _buildFeatureCard(
                title: 'xDrive AWD Control',
                desc: 'Dynamic AWD torque split, 2WD RWD switch, VTG telemetry',
                icon: Icons.all_inclusive,
                accentColor: Colors.tealAccent,
                onTap: () => _openScreen(const XDriveControlScreen()),
              ),
              _buildFeatureCard(
                title: 'ECU Topology Tree',
                desc: 'Inspect all 32 ECUs, identification DIDs, module reset',
                icon: Icons.developer_board,
                accentColor: neonGreen,
                onTap: () => _openScreen(EcuScanScreen(activeProtocol: _conn.protocol)),
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
          color: Colors.black26,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                      fontWeight: FontWeight.bold,
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
              style: const TextStyle(color: Colors.white38, fontSize: 9),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: darkCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderLight),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const Spacer(),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              desc,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white54,
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
