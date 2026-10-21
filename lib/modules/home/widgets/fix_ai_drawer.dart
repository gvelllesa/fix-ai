import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/animations/fix_ai_motion.dart';
import '../../../core/theme/fix_ai_tokens.dart';
import '../../../core/theme/theme_controller.dart';
import '../../garage/widgets/add_car_dialog.dart';
import '../../obd/screens/coding_screen.dart';
import '../../obd/screens/ecu_scan_screen.dart';
import '../../obd/screens/flash_tuning_screen.dart';
import '../../obd/screens/live_telemetry_screen.dart';
import '../../obd/screens/service_functions_screen.dart';
import '../../obd/screens/xdrive_control_screen.dart';
import '../../obd/widgets/advanced_connection_dialog.dart';

class FixAiDrawer extends StatefulWidget {
  final String? currentCarId;
  final Function(Map<String, dynamic>)? onObdConnected;
  final Function(Map<String, dynamic>)? onVehicleSelected;

  const FixAiDrawer({
    super.key,
    this.currentCarId,
    this.onObdConnected,
    this.onVehicleSelected,
  });

  @override
  State<FixAiDrawer> createState() => _FixAiDrawerState();
}

class _FixAiDrawerState extends State<FixAiDrawer> {
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = isDark ? FixAiTokens.canvas : theme.scaffoldBackgroundColor;
    final textPrimary = isDark ? FixAiTokens.textPrimary : (theme.textTheme.bodyLarge?.color ?? Colors.black87);
    final textSecondary = isDark ? FixAiTokens.textSecondary : Colors.black54;
    final textTertiary = isDark ? FixAiTokens.textMuted : Colors.black38;

    return Drawer(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // Top Branding & Hero Diagnostic Trigger
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: FixAiTokens.accentCyan.withValues(alpha: 0.12),
                          borderRadius: FixAiTokens.borderRadiusSm,
                          border: Border.all(
                            color: FixAiTokens.accentCyan.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(Icons.speed_rounded, color: FixAiTokens.accentCyan, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FIX AI',
                            style: TextStyle(
                              color: textPrimary,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Text(
                            'FACTORY DIAGNOSTICS & TUNING',
                            style: TextStyle(
                              color: textTertiary,
                              fontSize: 8,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Hero Diagnostic Scan CTA
                  BouncyPressable(
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        SmoothSlidePageRoute(page: const EcuScanScreen()),
                      );
                    },
                    borderRadius: FixAiTokens.borderRadiusMd,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [FixAiTokens.accentCyan, Color(0xFF00B0FF)],
                        ),
                        borderRadius: FixAiTokens.borderRadiusMd,
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.health_and_safety_rounded, color: Color(0xFF090C10), size: 20),
                          SizedBox(width: 10),
                          Text(
                            'Full Diagnostic Scan',
                            style: TextStyle(
                              color: Color(0xFF090C10),
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          Spacer(),
                          Icon(Icons.arrow_forward_rounded, color: Color(0xFF090C10), size: 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: FixAiTokens.borderSubtle, height: 1),

            // Middle Section: Categorized Workshop Navigation & Garage
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                children: [
                  _buildSubHeader('WORKSHOP MODULES', Icons.grid_view_rounded, textTertiary),
                  const SizedBox(height: 6),
                  _buildNavTile(
                    context: context,
                    icon: Icons.hub_rounded,
                    title: 'ECU Topology & DTCs',
                    subtitle: 'Full 32-module scan & freeze frames',
                    color: FixAiTokens.accentEmerald,
                    destination: const EcuScanScreen(),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.speed_rounded,
                    title: 'Live Telemetry & Gauges',
                    subtitle: 'High-speed UDS boost, AFR & temps',
                    color: FixAiTokens.accentCyan,
                    destination: const LiveTelemetryScreen(),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.bolt_rounded,
                    title: 'Tuning & Flash Calibration',
                    subtitle: 'Custom ROM, burbles & TCU options',
                    color: FixAiTokens.accentAmber,
                    destination: const FlashTuningScreen(),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.alt_route_rounded,
                    title: 'xDrive AWD Control',
                    subtitle: 'Dynamic torque split & 100% RWD',
                    color: FixAiTokens.accentCyan,
                    destination: const XDriveControlScreen(),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.home_repair_service_rounded,
                    title: 'Service & Adaptations',
                    subtitle: 'Battery register, brake bleed, VTG reset',
                    color: FixAiTokens.accentAmber,
                    destination: const ServiceFunctionsScreen(),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.terminal_rounded,
                    title: 'Vehicle Coding & FDL',
                    subtitle: 'SALAPA orders & cheat codes',
                    color: FixAiTokens.accentPurple,
                    destination: const CodingScreen(),
                  ),
                  _buildNavTile(
                    context: context,
                    icon: Icons.settings_ethernet_rounded,
                    title: 'Adapter Hardware Setup',
                    subtitle: 'ENET, WiFi, Bluetooth ELM327',
                    color: FixAiTokens.textSecondary,
                    onTapCustom: () async {
                      Navigator.pop(context);
                      await showDialog(
                        context: context,
                        builder: (c) => const AdvancedConnectionDialog(),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // MY GARAGE
                  _buildSubHeader('MY GARAGE', Icons.directions_car_outlined, textTertiary),
                  const SizedBox(height: 6),
                  FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey(_refreshKey),
                    future: Supabase.instance.client
                        .from('garage')
                        .select()
                        .order('created_at', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: FixAiTokens.accentCyan),
                            ),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          child: Text(
                            'Error loading vehicles',
                            style: TextStyle(color: FixAiTokens.accentRose, fontSize: 12),
                          ),
                        );
                      }

                      final cars = snapshot.data ?? [];
                      if (cars.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                          child: Text(
                            'No vehicles registered in garage.',
                            style: TextStyle(color: textTertiary, fontSize: 12),
                          ),
                        );
                      }

                      return Column(
                        children: cars.map((car) {
                          final make = car['make'] ?? '';
                          final model = car['model'] ?? '';
                          final year = car['year']?.toString() ?? '';
                          final title = '$make $model $year'.trim();
                          final isActive = car['id'] == widget.currentCarId;
                          return _buildGarageItem(
                            context,
                            title.isEmpty ? 'Unknown Vehicle' : title,
                            isActive: isActive,
                            accentColor: FixAiTokens.accentCyan,
                            onTap: () {
                              Navigator.pop(context);
                              if (widget.onVehicleSelected != null) {
                                widget.onVehicleSelected!(car);
                              }
                            },
                          );
                        }).toList(),
                      );
                    },
                  ),

                  // Add Car Button
                  Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: TextButton.icon(
                      onPressed: () async {
                        final result = await showDialog<bool>(
                          context: context,
                          builder: (_) => const AddCarDialog(),
                        );
                        if (result == true) {
                          setState(() {
                            _refreshKey++;
                          });
                        }
                      },
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add Vehicle to Garage'),
                      style: TextButton.styleFrom(
                        foregroundColor: FixAiTokens.accentCyan,
                        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // DIAGNOSTIC HISTORY
                  _buildSubHeader('RECENT PROCEDURES', Icons.history_rounded, textTertiary),
                  const SizedBox(height: 6),
                  _buildHistoryItem(
                    context,
                    'N55 Engine Misfire Analysis',
                    isActive: true,
                    accentColor: FixAiTokens.accentCyan,
                  ),
                  _buildHistoryItem(
                    context,
                    'VTG Transfer Case Adaptation Reset',
                    isActive: false,
                    accentColor: FixAiTokens.accentCyan,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Bottom Profile / Settings Section
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: FixAiTokens.surfacePrimary,
                border: const Border(
                  top: BorderSide(color: FixAiTokens.borderSubtle, width: 1),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor: FixAiTokens.surfaceElevated,
                    child: Icon(Icons.person_rounded, color: textSecondary, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ნიკა გველესიანი',
                          style: TextStyle(color: textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: FixAiTokens.accentCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'PRO WORKSHOP',
                            style: TextStyle(
                              color: FixAiTokens.accentCyan,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showSettingsModal(context, theme, textPrimary, FixAiTokens.accentCyan, textTertiary),
                    icon: Icon(Icons.settings_rounded, size: 19, color: textTertiary),
                    tooltip: 'Settings',
                  ),
                  IconButton(
                    onPressed: () async {
                      try {
                        await Supabase.instance.client.auth.signOut();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      } catch (e) {
                        debugPrint('Error signing out: $e');
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                        }
                      }
                    },
                    icon: Icon(Icons.logout_rounded, size: 19, color: textTertiary),
                    tooltip: 'Log Out',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    Widget? destination,
    VoidCallback? onTapCustom,
  }) {
    return BouncyPressable(
      onTap: () {
        if (onTapCustom != null) {
          onTapCustom();
        } else if (destination != null) {
          Navigator.pop(context);
          Navigator.push(context, SmoothSlidePageRoute(page: destination));
        }
      },
      borderRadius: FixAiTokens.borderRadiusMd,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: FixAiTokens.surfaceElevated,
          borderRadius: FixAiTokens.borderRadiusMd,
          border: Border.all(color: FixAiTokens.borderSubtle),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: FixAiTokens.borderRadiusSm,
                border: Border.all(color: color.withValues(alpha: 0.25)),
              ),
              child: Icon(icon, color: color, size: 17),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: FixAiTokens.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: FixAiTokens.textMuted,
                      fontSize: 10.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: FixAiTokens.textMuted, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSubHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 4, top: 6),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 6),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, String title, {required bool isActive, required Color accentColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive ? FixAiTokens.surfaceElevated : Colors.transparent,
        borderRadius: FixAiTokens.borderRadiusSm,
        border: Border.all(
          color: isActive ? FixAiTokens.borderSubtle : Colors.transparent,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? FixAiTokens.textPrimary : FixAiTokens.textSecondary,
              fontSize: 12.5,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Icon(
            Icons.history_rounded,
            size: 16,
            color: isActive ? accentColor : FixAiTokens.textMuted,
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          onTap: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Widget _buildGarageItem(BuildContext context, String title, {required bool isActive, required Color accentColor, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isActive ? FixAiTokens.surfaceElevated : Colors.transparent,
        borderRadius: FixAiTokens.borderRadiusSm,
        border: Border.all(
          color: isActive ? accentColor.withValues(alpha: 0.4) : FixAiTokens.borderSubtle,
          width: 1.0,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? FixAiTokens.textPrimary : FixAiTokens.textSecondary,
              fontSize: 12.5,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: Icon(
            Icons.directions_car_rounded,
            size: 16,
            color: isActive ? accentColor : FixAiTokens.textMuted,
          ),
          trailing: isActive
              ? Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                  ),
                )
              : null,
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          onTap: onTap,
        ),
      ),
    );
  }

  void _showSettingsModal(BuildContext context, ThemeData theme, Color textPrimary, Color accentColor, Color textTertiary) {
    final measurementNotifier = ValueNotifier<String>('Metric');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: FixAiTokens.surfacePrimary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(22.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: FixAiTokens.borderSubtle,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Appearance Theme
                  Text(
                    'Appearance Theme',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 10),
                  AnimatedBuilder(
                    animation: ThemeController(),
                    builder: (context, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<ThemeMode>(
                          segments: const [
                            ButtonSegment(value: ThemeMode.system, label: Text('Auto', style: TextStyle(fontSize: 12))),
                            ButtonSegment(value: ThemeMode.light, label: Text('Light', style: TextStyle(fontSize: 12))),
                            ButtonSegment(value: ThemeMode.dark, label: Text('Dark', style: TextStyle(fontSize: 12))),
                          ],
                          selected: {ThemeController().themeMode},
                          onSelectionChanged: (Set<ThemeMode> newSelection) {
                            ThemeController().setThemeMode(newSelection.first);
                            setState(() {});
                          },
                          style: SegmentedButton.styleFrom(
                            foregroundColor: textPrimary,
                            selectedForegroundColor: Colors.black,
                            selectedBackgroundColor: accentColor,
                            side: const BorderSide(color: FixAiTokens.borderSubtle),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Measurement Units
                  Text(
                    'Measurement Units',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder<String>(
                    valueListenable: measurementNotifier,
                    builder: (context, value, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'Metric', label: Text('Metric (km, °C, Bar)', style: TextStyle(fontSize: 12))),
                            ButtonSegment(value: 'Imperial', label: Text('Imperial (mi, °F, PSI)', style: TextStyle(fontSize: 12))),
                          ],
                          selected: {value},
                          onSelectionChanged: (Set<String> newSelection) {
                            measurementNotifier.value = newSelection.first;
                          },
                          style: SegmentedButton.styleFrom(
                            foregroundColor: textPrimary,
                            selectedForegroundColor: Colors.black,
                            selectedBackgroundColor: accentColor,
                            side: const BorderSide(color: FixAiTokens.borderSubtle),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Divider(color: FixAiTokens.borderSubtle, height: 1),
                  const SizedBox(height: 8),

                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_outline_rounded, color: FixAiTokens.accentRose),
                    title: const Text('Clear Diagnostic History', style: TextStyle(color: FixAiTokens.accentRose, fontWeight: FontWeight.bold)),
                    onTap: () {
                      Navigator.pop(modalContext);
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
