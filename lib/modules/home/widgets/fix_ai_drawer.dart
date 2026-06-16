import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../garage/widgets/add_car_dialog.dart';
import '../../obd/widgets/advanced_connection_dialog.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../core/services/obd_api_service.dart';

class FixAiDrawer extends StatefulWidget {
  final String? currentCarId;
  final Function(Map<String, dynamic>)? onObdConnected;
  final Function(Map<String, dynamic>)? onVehicleSelected;

  const FixAiDrawer({
    Key? key,
    this.currentCarId,
    this.onObdConnected,
    this.onVehicleSelected,
  }) : super(key: key);

  @override
  State<FixAiDrawer> createState() => _FixAiDrawerState();
}

class _FixAiDrawerState extends State<FixAiDrawer> {
  // We use this key to force FutureBuilder to re-fetch when a car is added
  int _refreshKey = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.scaffoldBackgroundColor;
    final accentColor = theme.primaryColor;
    final textPrimary = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final textSecondary = textPrimary.withOpacity(0.7);
    final textTertiary = textPrimary.withOpacity(0.54);

    return Drawer(
      backgroundColor: bgColor,
      child: SafeArea(
        child: Column(
          children: [
            // Top Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FIX AI',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      // In a real app, route to the start of a new chat session
                    },
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text(
                      'New Diagnosis',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: textPrimary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: () async {
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext c) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      );
                      
                      await Future.delayed(const Duration(seconds: 2));
                      
                      const mockCode = 'P0100';
                      final description = await ObdApiService.fetchObdDescription(mockCode);
                      
                      if (context.mounted) {
                        Navigator.pop(context); // Close loading dialog
                      }

                      if (widget.onObdConnected != null) {
                        widget.onObdConnected!({
                          'code': mockCode,
                          'description': description ?? 'Unknown Error',
                        });
                      }
                    },
                    icon: const Icon(Icons.bluetooth_connected, size: 20),
                    label: const Text(
                      'OBD Scanner',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.brightness == Brightness.dark 
                          ? Colors.white.withOpacity(0.05) 
                          : Colors.black.withOpacity(0.05),
                      foregroundColor: textPrimary,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: theme.brightness == Brightness.dark
                              ? Colors.white.withOpacity(0.1)
                              : Colors.black.withOpacity(0.1)
                        ),
                      ),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ),

            // Middle Section (Expanded)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  // HISTORY
                  _buildSubHeader('HISTORY', Icons.history, textTertiary),
                  _buildHistoryItem(context, 'N55 Engine Misfire Analysis', isActive: true, accentColor: accentColor),
                  _buildHistoryItem(context, 'ISTA Steering Rack Calibration', isActive: false, accentColor: accentColor),
                  
                  const SizedBox(height: 24),
                  
                  // MY GARAGE
                  _buildSubHeader('MY GARAGE', Icons.directions_car_outlined, textTertiary),
                  
                  // Fetch cars dynamically from Supabase
                  FutureBuilder<List<Map<String, dynamic>>>(
                    key: ValueKey(_refreshKey),
                    future: Supabase.instance.client.from('garage').select().order('created_at', ascending: false),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Center(
                            child: SizedBox(
                              width: 20, 
                              height: 20, 
                              child: CircularProgressIndicator(strokeWidth: 2, color: accentColor)
                            ),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Padding(
                           padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                           child: Text('Error loading cars', style: TextStyle(color: Colors.red.shade300, fontSize: 12)),
                        );
                      }
                      
                      final cars = snapshot.data ?? [];
                      if (cars.isEmpty) {
                         return const Padding(
                           padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                           child: Text('No cars added yet.', style: TextStyle(color: Colors.white54, fontSize: 12)),
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
                            accentColor: accentColor,
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
                    padding: const EdgeInsets.only(top: 8.0, left: 8.0),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () async {
                          final result = await showDialog<bool>(
                            context: context,
                            builder: (_) => const AddCarDialog(),
                          );
                          // If AddCarDialog returned true (success), refresh the list
                          if (result == true) {
                            setState(() {
                              _refreshKey++;
                            });
                          }
                        },
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Car'),
                        style: TextButton.styleFrom(
                          foregroundColor: textSecondary,
                          textStyle: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            

            // Bottom Section (Profile)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white10 
                        : Colors.black12, 
                    width: 1
                  ),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: Theme.of(context).brightness == Brightness.dark 
                        ? Colors.white12 
                        : Colors.black12,
                    child: Icon(Icons.person, color: textSecondary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ნიკა გველესიანი',
                          style: TextStyle(color: textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F62FE),
                            borderRadius: const BorderRadius.all(Radius.circular(4)),
                          ),
                          child: const Text(
                            'Pro',
                            style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showSettingsModal(context, theme, textPrimary, accentColor, textTertiary),
                    icon: Icon(Icons.settings, size: 20, color: textTertiary),
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
                      }
                    },
                    icon: Icon(Icons.logout, size: 20, color: textTertiary),
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

  void _showSettingsModal(BuildContext context, ThemeData theme, Color textPrimary, Color accentColor, Color textTertiary) {
    // Local state for measurement units toggle
    final measurementNotifier = ValueNotifier<String>('Metric');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext modalContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  
                  // 1. PRO Upgrade Banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1E3A8A), Color(0xFF4C1D95)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.bolt, color: Colors.amber, size: 28),
                            const SizedBox(width: 8),
                            const Text(
                              'Unlock FIX AI PRO',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Unlimited advanced ISTA-level diagnostics & OBD scans',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.8),
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.pop(modalContext);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF1E3A8A),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 0,
                          ),
                          child: const Text('Go Pro', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // 2. Appearance Section
                  Text(
                    'Appearance',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 12),
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
                            selectedForegroundColor: Colors.white,
                            selectedBackgroundColor: accentColor,
                            side: BorderSide(color: textTertiary.withOpacity(0.2)),
                          ),
                        ),
                      );
                    }
                  ),
                  const SizedBox(height: 24),
                  
                  // 3. Measurement Units
                  Text(
                    'Measurement Units',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: textPrimary),
                  ),
                  const SizedBox(height: 12),
                  ValueListenableBuilder<String>(
                    valueListenable: measurementNotifier,
                    builder: (context, value, _) {
                      return SizedBox(
                        width: double.infinity,
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'Metric', label: Text('Metric (km, °C)', style: TextStyle(fontSize: 12))),
                            ButtonSegment(value: 'Imperial', label: Text('Imperial (mi, °F)', style: TextStyle(fontSize: 12))),
                          ],
                          selected: {value},
                          onSelectionChanged: (Set<String> newSelection) {
                            measurementNotifier.value = newSelection.first;
                          },
                          style: SegmentedButton.styleFrom(
                            foregroundColor: textPrimary,
                            selectedForegroundColor: Colors.white,
                            selectedBackgroundColor: accentColor,
                            side: BorderSide(color: textTertiary.withOpacity(0.2)),
                          ),
                        ),
                      );
                    }
                  ),
                  const SizedBox(height: 32),
                  
                  // 4. Danger Zone
                  Divider(color: theme.dividerColor.withOpacity(0.1)),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.delete_forever, color: Colors.red),
                    title: const Text('Clear Chat History', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
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

  Widget _buildSubHeader(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(BuildContext context, String title, {required bool isActive, required Color accentColor}) {
    final theme = Theme.of(context);
    final textPrimary = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final textSecondary = textPrimary.withOpacity(0.7);
    final hoverColor = theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isActive ? hoverColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? textPrimary : textSecondary,
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          onTap: () {
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  Widget _buildGarageItem(BuildContext context, String title, {required bool isActive, required Color accentColor, required VoidCallback onTap}) {
    final theme = Theme.of(context);
    final textPrimary = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final textSecondary = textPrimary.withOpacity(0.7);
    final hoverColor = theme.brightness == Brightness.dark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: isActive ? hoverColor : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isActive ? Border(left: BorderSide(color: accentColor, width: 3)) : null,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          title: Text(
            title,
            style: TextStyle(
              color: isActive ? accentColor : textSecondary,
              fontSize: 14,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          onTap: onTap,
        ),
      ),
    );
  }
}
