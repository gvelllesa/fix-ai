import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/animations/fix_ai_motion.dart';
import '../../../core/theme/fix_ai_tokens.dart';
import '../services/bmw_vtg_manager.dart';
import '../services/protocols/enet_hsfz_protocol.dart';

/// BMW xDrive / xDrive AWD Distribution Transfer Case Control Screen
///
/// Provides live VTG multi-disc clutch actuation (RWD, Stock, Sport, Snow, Custom),
/// real-time telemetry readout (DIDs 0xD030 - 0xD033), and clutch wear calibration (Routine 0xA101).
class XDriveControlScreen extends StatefulWidget {
  final EnetHsfzProtocol? activeProtocol;

  const XDriveControlScreen({super.key, this.activeProtocol});

  @override
  State<XDriveControlScreen> createState() => _XDriveControlScreenState();
}

class _XDriveControlScreenState extends State<XDriveControlScreen> {
  late BmwVtgManager _vtgManager;
  StreamSubscription<VtgTelemetryData>? _telemetrySub;
  VtgTelemetryData _telemetry = VtgTelemetryData.initial();

  XDriveMode _selectedMode = XDriveMode.stockAwd;
  double _customClutchValue = 20.0; // 0 to 100%
  bool _isConnected = false;
  bool _isActionRunning = false;
  String _statusText = 'Ready';

  @override
  void initState() {
    super.initState();
    _vtgManager = BmwVtgManager(protocol: widget.activeProtocol);
    _selectedMode = _vtgManager.currentMode;
    _customClutchValue = _vtgManager.customClutchPercent;
    _telemetry = _vtgManager.lastTelemetry;

    _telemetrySub = _vtgManager.telemetryStream.listen((data) {
      if (mounted) {
        setState(() {
          _telemetry = data;
        });
      }
    });

    _initConnection();
  }

  Future<void> _initConnection() async {
    final connected = await _vtgManager.ensureConnected();
    if (mounted) {
      setState(() {
        _isConnected = connected;
        _statusText = connected ? 'Connected to VTG [0x19]' : 'VTG Offline (Check ENET)';
      });
    }
  }

  @override
  void dispose() {
    _telemetrySub?.cancel();
    _vtgManager.dispose();
    super.dispose();
  }

  Future<bool> _showSafetyConfirmationDialog({
    required String title,
    required String description,
    required Color accentColor,
  }) async {
    bool confirmed = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: FixAiTokens.surfaceElevated,
              shape: RoundedRectangleBorder(
                borderRadius: FixAiTokens.borderRadiusLg,
                side: BorderSide(color: accentColor.withValues(alpha: 0.6), width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.warning_amber_rounded, color: accentColor, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        color: FixAiTokens.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    description,
                    style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: FixAiTokens.surfacePrimary,
                      borderRadius: FixAiTokens.borderRadiusSm,
                      border: Border.all(color: FixAiTokens.borderSubtle),
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: confirmed,
                          activeColor: accentColor,
                          checkColor: Colors.black,
                          onChanged: (val) {
                            setDialogState(() {
                              confirmed = val ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            'მე ვაცნობიერებ რისკებს და ვადასტურებ რეჟიმის შეცვლას',
                            style: TextStyle(color: FixAiTokens.textPrimary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('გაუქმება', style: TextStyle(color: FixAiTokens.textMuted)),
                ),
                ElevatedButton(
                  onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: FixAiTokens.surfaceHighlight,
                    shape: RoundedRectangleBorder(borderRadius: FixAiTokens.borderRadiusSm),
                  ),
                  child: const Text('დადასტურება', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  Future<void> _handleModeSelection(XDriveMode mode) async {
    if (_isActionRunning) return;

    if (mode == XDriveMode.rwd) {
      final proceed = await _showSafetyConfirmationDialog(
        title: 'Switch to 100% RWD Mode',
        description:
            'VTG multi-disc clutch will be completely disengaged (0% front torque). Front drive axle will be uncoupled. Vehicle will behave as pure rear-wheel drive.',
        accentColor: FixAiTokens.accentAmber,
      );
      if (!proceed) return;
    }

    final isOnline = _isConnected || (widget.activeProtocol?.isConnected ?? false);
    if (!isOnline) {
      setState(() {
        _selectedMode = mode;
        _statusText = '${mode.title} (PREVIEW)';
        switch (mode) {
          case XDriveMode.rwd:
            _telemetry = _telemetry.copyWith(frontTorquePercent: 0, rearTorquePercent: 100);
            break;
          case XDriveMode.stockAwd:
            _telemetry = _telemetry.copyWith(frontTorquePercent: 40, rearTorquePercent: 60);
            break;
          case XDriveMode.sportAwd:
            _telemetry = _telemetry.copyWith(frontTorquePercent: 30, rearTorquePercent: 70);
            break;
          case XDriveMode.snowAwd:
            _telemetry = _telemetry.copyWith(frontTorquePercent: 50, rearTorquePercent: 50);
            break;
          case XDriveMode.custom:
            _telemetry = _telemetry.copyWith(
              frontTorquePercent: _customClutchValue,
              rearTorquePercent: 100 - _customClutchValue,
            );
            break;
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: FixAiTokens.accentCyan),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preview რეჟიმი: ${mode.title} არჩეულია (მანქანასთან მიერთებისას ჩაიწერება VTG 0x19-ში).',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: FixAiTokens.surfaceElevated,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() {
      _isActionRunning = true;
      _statusText = 'Applying ${mode.title}...';
    });

    final success = await _vtgManager.setMode(
      mode,
      customPercentage: mode == XDriveMode.custom ? _customClutchValue : null,
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        if (success) {
          _selectedMode = mode;
          _statusText = '${mode.title} ACTIVE';
        } else {
          _statusText = 'Failed to apply ${mode.title}. Check VTG.';
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? '${mode.title} successfully configured on VTG' : 'Failed to switch mode on ECU 0x19',
          ),
          backgroundColor: success ? FixAiTokens.accentEmerald : FixAiTokens.accentRose,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleClutchCalibration() async {
    if (_isActionRunning) return;

    final isOnline = _isConnected || (widget.activeProtocol?.isConnected ?? false);
    if (!isOnline) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FixAiTokens.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: FixAiTokens.borderRadiusMd),
          title: const Row(
            children: [
              Icon(Icons.link_off_rounded, color: FixAiTokens.accentAmber),
              SizedBox(width: 10),
              Text('ავტომობილი გამორთულია', style: TextStyle(color: FixAiTokens.textPrimary, fontSize: 16)),
            ],
          ),
          content: Text(
            'VTG გადაბმულობის კალიბრაციისთვის (Routine 0xA101) საჭიროა ENET/OBD ადაპტერის შეერთება და აალების ჩართვა (Ignition ON).',
            style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: FixAiTokens.accentCyan,
                foregroundColor: Colors.black,
              ),
              child: const Text('გასაგებია', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    final proceed = await _showSafetyConfirmationDialog(
      title: 'Transfer Case Clutch Calibration',
      description:
          'Executes UDS RoutineControl 0x31 0x01 A1 01 to reset friction plate wear adaptations (STAT_WORKCLUTCH_WERT) and relearn mechanical clutch zero-point.',
      accentColor: FixAiTokens.accentCyan,
    );
    if (!proceed) return;

    setState(() {
      _isActionRunning = true;
      _statusText = 'Calibrating VTG Clutch Plates (Routine 0xA101)...';
    });

    final result = await _vtgManager.calibrateClutch();

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _statusText = result.success ? 'Clutch Calibration Complete' : 'Calibration Failed';
      });

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: FixAiTokens.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: FixAiTokens.borderRadiusMd),
          title: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle_rounded : Icons.error_rounded,
                color: result.success ? FixAiTokens.accentEmerald : FixAiTokens.accentRose,
              ),
              const SizedBox(width: 10),
              Text(
                result.success ? 'Calibration Successful' : 'Calibration Failed',
                style: const TextStyle(color: FixAiTokens.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(result.message, style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 13)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: result.success ? FixAiTokens.accentEmerald : FixAiTokens.accentRose,
                foregroundColor: Colors.black,
              ),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FixAiTokens.canvas,
      appBar: AppBar(
        backgroundColor: FixAiTokens.surfacePrimary,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: FixAiTokens.accentCyan.withValues(alpha: 0.12),
                borderRadius: FixAiTokens.borderRadiusSm,
              ),
              child: const Icon(Icons.all_inclusive_rounded, color: FixAiTokens.accentCyan, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'xDrive Mode',
                overflow: TextOverflow.ellipsis,
                style: FixAiTokens.titleMedium,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _vtgManager.isPollingTelemetry ? Icons.sensors_rounded : Icons.sensors_off_rounded,
              color: _vtgManager.isPollingTelemetry ? FixAiTokens.accentEmerald : FixAiTokens.textMuted,
            ),
            tooltip: _vtgManager.isPollingTelemetry ? 'Pause Telemetry' : 'Resume Telemetry',
            onPressed: () {
              setState(() {
                if (_vtgManager.isPollingTelemetry) {
                  _vtgManager.stopTelemetryPolling();
                } else {
                  _vtgManager.startTelemetryPolling();
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: FixAiTokens.textSecondary),
            tooltip: 'Re-ping VTG',
            onPressed: _initConnection,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Header
            StaggeredSlideFade(
              index: 0,
              child: _buildStatusHeader(),
            ),
            const SizedBox(height: 16),

            // Fluid Animated Torque Split Visualizer
            StaggeredSlideFade(
              index: 1,
              child: _buildTorqueSplitVisualizer(),
            ),
            const SizedBox(height: 16),

            // Telemetry Grid
            StaggeredSlideFade(
              index: 2,
              child: _buildTelemetryGrid(),
            ),
            const SizedBox(height: 22),

            // Presets Header
            StaggeredSlideFade(
              index: 3,
              child: Text(
                'OPERATING MODE PRESETS',
                style: FixAiTokens.sectionHeader,
              ),
            ),
            const SizedBox(height: 10),

            // Mode Cards
            StaggeredSlideFade(
              index: 4,
              child: _buildModeCard(
                mode: XDriveMode.rwd,
                icon: Icons.electric_bolt_rounded,
                color: FixAiTokens.accentAmber,
                badgeText: '0% FRONT / 100% REAR',
              ),
            ),
            const SizedBox(height: 10),
            StaggeredSlideFade(
              index: 5,
              child: _buildModeCard(
                mode: XDriveMode.stockAwd,
                icon: Icons.tune_rounded,
                color: FixAiTokens.accentBlue,
                badgeText: '40% FRONT / 60% REAR OEM',
              ),
            ),
            const SizedBox(height: 10),
            StaggeredSlideFade(
              index: 6,
              child: _buildModeCard(
                mode: XDriveMode.sportAwd,
                icon: Icons.sports_motorsports_rounded,
                color: FixAiTokens.accentPurple,
                badgeText: '30% FRONT / 70% REAR',
              ),
            ),
            const SizedBox(height: 10),
            StaggeredSlideFade(
              index: 7,
              child: _buildModeCard(
                mode: XDriveMode.snowAwd,
                icon: Icons.ac_unit_rounded,
                color: FixAiTokens.accentEmerald,
                badgeText: '50% FRONT / 50% REAR LOCKED',
              ),
            ),
            const SizedBox(height: 10),
            StaggeredSlideFade(
              index: 8,
              child: _buildCustomModeCard(),
            ),
            const SizedBox(height: 20),
            StaggeredSlideFade(
              index: 9,
              child: _buildClutchCalibrationCard(),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: FixAiTokens.surfacePrimary,
        borderRadius: FixAiTokens.borderRadiusMd,
        border: Border.all(color: FixAiTokens.borderSubtle),
      ),
      child: Row(
        children: [
          PulsingStatusGlow(
            isPulsing: _isConnected,
            glowColor: _isConnected ? FixAiTokens.accentEmerald : FixAiTokens.accentRose,
            maxRadius: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isConnected ? FixAiTokens.accentEmerald : FixAiTokens.accentRose,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? 'VTG / VGSG Active (Address 0x19)' : 'VTG Disconnected',
                  style: TextStyle(
                    color: FixAiTokens.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: _isActionRunning ? FixAiTokens.accentAmber : FixAiTokens.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (_isActionRunning)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: FixAiTokens.accentCyan),
            ),
        ],
      ),
    );
  }

  Widget _buildTorqueSplitVisualizer() {
    final targetFront = _telemetry.frontTorquePercent.clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FixAiTokens.surfacePrimary,
        borderRadius: FixAiTokens.borderRadiusLg,
        border: Border.all(color: FixAiTokens.accentCyan.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: FixAiTokens.accentCyan.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: targetFront, end: targetFront),
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
        builder: (context, animatedFront, _) {
          final front = animatedFront.clamp(0.0, 100.0);
          final rear = (100.0 - front).clamp(0.0, 100.0);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: FixAiTokens.accentCyan,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'DYNAMIC TORQUE SPLIT',
                        style: TextStyle(
                          color: FixAiTokens.accentCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: FixAiTokens.accentCyan.withValues(alpha: 0.12),
                      borderRadius: FixAiTokens.borderRadiusSm,
                      border: Border.all(
                        color: FixAiTokens.accentCyan.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${front.toStringAsFixed(0)}% F / ${rear.toStringAsFixed(0)}% R',
                      style: GoogleFonts.ibmPlexMono(
                        color: FixAiTokens.accentCyan,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // High-tech Split Bar
              ClipRRect(
                borderRadius: FixAiTokens.borderRadiusSm,
                child: SizedBox(
                  height: 28,
                  child: Row(
                    children: [
                      if (front > 0)
                        Flexible(
                          flex: (front * 10).round().clamp(1, 1000),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [FixAiTokens.accentCyan, Color(0xFF0091EA)],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: front >= 14
                                ? Text(
                                    'FRONT ${front.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      color: Color(0xFF090C10),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                      if (rear > 0)
                        Flexible(
                          flex: (rear * 10).round().clamp(1, 1000),
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [Color(0xFFFF9100), FixAiTokens.accentAmber],
                              ),
                            ),
                            alignment: Alignment.center,
                            child: rear >= 14
                                ? Text(
                                    'REAR ${rear.toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      color: Color(0xFF090C10),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Axle distribution indicators
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  _buildAxleIndicator('FRONT AXLE', front, FixAiTokens.accentCyan),
                  const Icon(Icons.sync_alt_rounded, color: FixAiTokens.textMuted, size: 18),
                  _buildAxleIndicator('REAR AXLE', rear, FixAiTokens.accentAmber),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAxleIndicator(String label, double pct, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ${pct.toStringAsFixed(0)}%',
          style: TextStyle(
            color: FixAiTokens.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildTelemetryGrid() {
    final temp = _telemetry.clutchTemperatureC;
    final tempColor = temp > 115
        ? FixAiTokens.accentRose
        : (temp > 90 ? FixAiTokens.accentAmber : FixAiTokens.accentEmerald);

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.1,
      children: [
        _buildTelemetryCard(
          title: 'Front Ratio',
          subTitle: '0xD030',
          value: '${_telemetry.frontTorquePercent.toStringAsFixed(1)} %',
          color: FixAiTokens.accentCyan,
          icon: Icons.front_hand_rounded,
        ),
        _buildTelemetryCard(
          title: 'Rear Ratio',
          subTitle: '0xD031',
          value: '${_telemetry.rearTorquePercent.toStringAsFixed(1)} %',
          color: FixAiTokens.accentAmber,
          icon: Icons.settings_rounded,
        ),
        _buildTelemetryCard(
          title: 'Clutch Temp',
          subTitle: '0xD032',
          value: '${temp.toStringAsFixed(1)} °C',
          color: tempColor,
          icon: Icons.thermostat_rounded,
        ),
        _buildTelemetryCard(
          title: 'Clutch Torque',
          subTitle: '0xD033',
          value: '${_telemetry.clutchTorqueNm.toStringAsFixed(0)} Nm',
          color: FixAiTokens.accentPurple,
          icon: Icons.speed_rounded,
        ),
      ],
    );
  }

  Widget _buildTelemetryCard({
    required String title,
    String? subTitle,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: FixAiTokens.surfacePrimary,
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
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: FixAiTokens.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subTitle != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          subTitle,
                          style: GoogleFonts.ibmPlexMono(
                            color: FixAiTokens.textMuted,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: GoogleFonts.ibmPlexMono(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard({
    required XDriveMode mode,
    required IconData icon,
    required Color color,
    required String badgeText,
  }) {
    final isSelected = _selectedMode == mode;

    return BouncyPressable(
      onTap: () => _handleModeSelection(mode),
      borderRadius: FixAiTokens.borderRadiusLg,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FixAiTokens.surfacePrimary,
          borderRadius: FixAiTokens.borderRadiusLg,
          border: Border.all(
            color: isSelected ? color : FixAiTokens.borderSubtle,
            width: isSelected ? 1.8 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.15),
                    blurRadius: 12,
                    spreadRadius: 1,
                  )
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: isSelected ? 0.25 : 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          mode.title,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: FixAiTokens.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: FixAiTokens.borderRadiusSm,
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Color(0xFF090C10),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.subtitle,
                    style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: FixAiTokens.surfaceElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: FixAiTokens.borderSubtle),
                    ),
                    child: Text(
                      badgeText,
                      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomModeCard() {
    final isSelected = _selectedMode == XDriveMode.custom;
    const color = FixAiTokens.accentAmber;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: FixAiTokens.surfacePrimary,
        borderRadius: FixAiTokens.borderRadiusLg,
        border: Border.all(
          color: isSelected ? color : FixAiTokens.borderSubtle,
          width: isSelected ? 1.8 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isSelected ? 0.25 : 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.tune_rounded, color: color, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            XDriveMode.custom.title,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: FixAiTokens.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isSelected) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: FixAiTokens.borderRadiusSm,
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Color(0xFF090C10),
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      XDriveMode.custom.subtitle,
                      style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Custom Slider
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Front Torque Clamp Ratio:',
                style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 12),
              ),
              Text(
                '${_customClutchValue.toStringAsFixed(0)}% Front / ${(100 - _customClutchValue).toStringAsFixed(0)}% Rear',
                style: GoogleFonts.ibmPlexMono(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: color,
              inactiveTrackColor: FixAiTokens.surfaceHighlight,
              thumbColor: color,
              overlayColor: color.withValues(alpha: 0.15),
            ),
            child: Slider(
              value: _customClutchValue,
              min: 0.0,
              max: 50.0,
              divisions: 50,
              label: '${_customClutchValue.toStringAsFixed(0)}%',
              onChanged: (val) {
                setState(() {
                  _customClutchValue = val;
                });
              },
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: BouncyPressable(
              onTap: () => _handleModeSelection(XDriveMode.custom),
              borderRadius: FixAiTokens.borderRadiusSm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: FixAiTokens.borderRadiusSm,
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: Color(0xFF090C10)),
                    SizedBox(width: 6),
                    Text(
                      'Apply Custom Split',
                      style: TextStyle(
                        color: Color(0xFF090C10),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClutchCalibrationCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: FixAiTokens.surfacePrimary,
        borderRadius: FixAiTokens.borderRadiusLg,
        border: Border.all(color: FixAiTokens.accentCyan.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: FixAiTokens.accentCyan.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.build_circle_outlined, color: FixAiTokens.accentCyan, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VTG Clutch Wear Calibration',
                      style: TextStyle(
                        color: FixAiTokens.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'UDS RoutineControl 0x31 0x01 A1 01',
                      style: GoogleFonts.ibmPlexMono(
                        color: FixAiTokens.accentCyan,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Resets STAT_WORKCLUTCH_WERT and STAT_PRCTMPSTRESSCLUTCH_WERT adaptation registers and runs acoustic zero-point calibration routine. Required after transfer case fluid changes or multi-disc clutch service.',
            style: TextStyle(color: FixAiTokens.textSecondary, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          BouncyPressable(
            onTap: _isActionRunning ? null : _handleClutchCalibration,
            borderRadius: FixAiTokens.borderRadiusMd,
            enabled: !_isActionRunning,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: _isActionRunning ? FixAiTokens.surfaceHighlight : FixAiTokens.accentCyan,
                borderRadius: FixAiTokens.borderRadiusMd,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isActionRunning) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF090C10)),
                    ),
                    const SizedBox(width: 8),
                  ] else ...[
                    const Icon(Icons.play_arrow_rounded, color: Color(0xFF090C10), size: 20),
                    const SizedBox(width: 6),
                  ],
                  const Text(
                    'Calibrate Transfer Case Clutch',
                    style: TextStyle(
                      color: Color(0xFF090C10),
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
