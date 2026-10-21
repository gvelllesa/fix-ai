import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bmw_vtg_manager.dart';
import '../services/protocols/enet_hsfz_protocol.dart';

/// BMW xDrive / xDelete Transfer Case Control Screen
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
      if (connected) {
        _vtgManager.startTelemetryPolling();
      }
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
              backgroundColor: const Color(0xFF161B22),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: accentColor.withValues(alpha: 0.8), width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.warning_amber_rounded, color: accentColor, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      description,
                      style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildSafetyCheckRow(Icons.speed, 'Vehicle completely stationary (0 km/h)'),
                          const SizedBox(height: 8),
                          _buildSafetyCheckRow(Icons.local_parking, 'Gear selector in Park (P) or Neutral (N)'),
                          const SizedBox(height: 8),
                          _buildSafetyCheckRow(Icons.pan_tool, 'Emergency brake firmly set'),
                          const SizedBox(height: 8),
                          _buildSafetyCheckRow(Icons.power_settings_new, 'Ignition ON / Engine idling'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: confirmed,
                      activeColor: accentColor,
                      checkColor: Colors.black,
                      title: const Text(
                        'I confirm safety conditions are satisfied',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      onChanged: (val) {
                        setDialogState(() => confirmed = val ?? false);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    disabledBackgroundColor: Colors.white10,
                    foregroundColor: Colors.black,
                    disabledForegroundColor: Colors.white24,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Proceed', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
    return result ?? false;
  }

  Widget _buildSafetyCheckRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.greenAccent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _handleModeSelection(XDriveMode mode) async {
    if (_isActionRunning) return;

    if (mode == XDriveMode.rwd) {
      final proceed = await _showSafetyConfirmationDialog(
        title: 'Switch to 100% RWD Mode',
        description:
            'VTG multi-disc clutch will be completely disengaged (0% front torque). Front drive axle will be uncoupled. Vehicle will behave as pure rear-wheel drive.',
        accentColor: Colors.deepOrangeAccent,
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
                const Icon(Icons.info_outline, color: Colors.cyanAccent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Preview რეჟიმი: ${mode.title} არჩეულია (მანქანასთან მიერთებისას ჩაიწერება VTG 0x19-ში).',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF161B22),
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
            success ? '✓ ${mode.title} successfully configured on VTG' : '✗ Failed to switch mode on ECU 0x19',
          ),
          backgroundColor: success ? Colors.green.shade800 : Colors.red.shade900,
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
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: const Row(
            children: [
              Icon(Icons.link_off, color: Colors.orangeAccent),
              SizedBox(width: 10),
              Text('ავტომობილი გამორთულია', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: const Text(
            'VTG გადაბმულობის კალიბრაციისთვის (Routine 0xA101) საჭიროა ENET/OBD ადაპტერის შეერთება და აალების ჩართვა (Ignition ON).',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyanAccent, foregroundColor: Colors.black),
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
      accentColor: Colors.cyanAccent,
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
          backgroundColor: const Color(0xFF161B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Icon(
                result.success ? Icons.check_circle : Icons.error,
                color: result.success ? Colors.greenAccent : Colors.redAccent,
              ),
              const SizedBox(width: 10),
              Text(
                result.success ? 'Calibration Successful' : 'Calibration Failed',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(result.message, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: result.success ? Colors.greenAccent : Colors.redAccent,
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
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.all_inclusive, color: Colors.cyanAccent, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'xDrive Mode Control',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _vtgManager.isPollingTelemetry ? Icons.sensors : Icons.sensors_off,
              color: _vtgManager.isPollingTelemetry ? Colors.greenAccent : Colors.white38,
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
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Re-ping VTG',
            onPressed: _initConnection,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeader(),
            const SizedBox(height: 16),
            _buildTorqueSplitVisualizer(),
            const SizedBox(height: 16),
            _buildTelemetryGrid(),
            const SizedBox(height: 22),
            const Text(
              'OPERATING MODE PRESETS',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 10),
            _buildModeCard(
              mode: XDriveMode.rwd,
              icon: Icons.electric_bolt,
              color: Colors.deepOrangeAccent,
              badgeText: '0% FRONT / 100% REAR',
            ),
            const SizedBox(height: 10),
            _buildModeCard(
              mode: XDriveMode.stockAwd,
              icon: Icons.tune,
              color: Colors.blueAccent,
              badgeText: '40% FRONT / 60% REAR OEM',
            ),
            const SizedBox(height: 10),
            _buildModeCard(
              mode: XDriveMode.sportAwd,
              icon: Icons.sports_motorsports,
              color: Colors.purpleAccent,
              badgeText: '30% FRONT / 70% REAR',
            ),
            const SizedBox(height: 10),
            _buildModeCard(
              mode: XDriveMode.snowAwd,
              icon: Icons.ac_unit,
              color: Colors.tealAccent,
              badgeText: '50% FRONT / 50% REAR LOCKED',
            ),
            const SizedBox(height: 10),
            _buildCustomModeCard(),
            const SizedBox(height: 24),
            _buildClutchCalibrationCard(),
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _isConnected ? Colors.greenAccent : Colors.redAccent,
              boxShadow: [
                BoxShadow(
                  color: (_isConnected ? Colors.greenAccent : Colors.redAccent).withValues(alpha: 0.6),
                  blurRadius: 6,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isConnected ? 'VTG / VGSG Active (Address 0x19)' : 'VTG Disconnected',
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  _statusText,
                  style: TextStyle(
                    color: _isActionRunning ? Colors.amberAccent : Colors.white60,
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
            ),
        ],
      ),
    );
  }

  Widget _buildTorqueSplitVisualizer() {
    final front = _telemetry.frontTorquePercent.clamp(0.0, 100.0);
    final rear = _telemetry.rearTorquePercent.clamp(0.0, 100.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.cyanAccent.withValues(alpha: 0.05),
            blurRadius: 16,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              const Text(
                'LIVE TORQUE SPLIT',
                style: TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${front.toStringAsFixed(0)}% F / ${rear.toStringAsFixed(0)}% R',
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Split Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 26,
              child: Row(
                children: [
                  Expanded(
                    flex: front.round().clamp(1, 100),
                    child: Container(
                      color: Colors.cyanAccent,
                      alignment: Alignment.center,
                      child: front >= 10
                          ? Text(
                              'FRONT ${front.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Expanded(
                    flex: rear.round().clamp(1, 100),
                    child: Container(
                      color: Colors.orangeAccent,
                      alignment: Alignment.center,
                      child: rear >= 10
                          ? Text(
                              'REAR ${rear.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
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
          // Visual Drivetrain Indicators
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildAxleIndicator('FRONT AXLE', front, Colors.cyanAccent),
              const Icon(Icons.sync_alt, color: Colors.white24, size: 20),
              _buildAxleIndicator('REAR AXLE', rear, Colors.orangeAccent),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAxleIndicator(String label, double pct, Color color) {
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label: ${pct.toStringAsFixed(0)}%',
          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildTelemetryGrid() {
    final temp = _telemetry.clutchTemperatureC;
    final tempColor = temp > 115
        ? Colors.redAccent
        : (temp > 90 ? Colors.orangeAccent : Colors.greenAccent);

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
          color: Colors.cyanAccent,
          icon: Icons.front_hand,
        ),
        _buildTelemetryCard(
          title: 'Rear Ratio',
          subTitle: '0xD031',
          value: '${_telemetry.rearTorquePercent.toStringAsFixed(1)} %',
          color: Colors.orangeAccent,
          icon: Icons.settings,
        ),
        _buildTelemetryCard(
          title: 'Clutch Temp',
          subTitle: '0xD032',
          value: '${temp.toStringAsFixed(1)} °C',
          color: tempColor,
          icon: Icons.thermostat,
        ),
        _buildTelemetryCard(
          title: 'Clutch Torque',
          subTitle: '0xD033',
          value: '${_telemetry.clutchTorqueNm.toStringAsFixed(0)} Nm',
          color: Colors.purpleAccent,
          icon: Icons.speed,
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
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
                        style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      if (subTitle != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          subTitle,
                          style: const TextStyle(color: Colors.white38, fontSize: 9, fontFamily: 'monospace'),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
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

    return InkWell(
      onTap: () => _handleModeSelection(mode),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : Colors.white12,
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.2),
                    blurRadius: 10,
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
              child: Icon(icon, color: color, size: 26),
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
                          style: const TextStyle(
                            color: Colors.white,
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
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ACTIVE',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    mode.subtitle,
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(4),
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
    const color = Colors.amberAccent;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isSelected ? color : Colors.white12,
          width: isSelected ? 2.0 : 1.0,
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
                child: const Icon(Icons.tune, color: color, size: 26),
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
                            style: const TextStyle(
                              color: Colors.white,
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
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'ACTIVE',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      XDriveMode.custom.subtitle,
                      style: const TextStyle(color: Colors.white60, fontSize: 12),
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
              const Text(
                'Front Torque Clamp Ratio:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '${_customClutchValue.toStringAsFixed(0)}% Front / ${(100 - _customClutchValue).toStringAsFixed(0)}% Rear',
                style: const TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          Slider(
            value: _customClutchValue,
            min: 0.0,
            max: 50.0, // 0 to 50% front torque (up to 50/50 locked)
            divisions: 50,
            activeColor: color,
            inactiveColor: Colors.white12,
            label: '${_customClutchValue.toStringAsFixed(0)}%',
            onChanged: (val) {
              setState(() {
                _customClutchValue = val;
              });
            },
          ),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => _handleModeSelection(XDriveMode.custom),
              icon: const Icon(Icons.check, size: 16, color: Colors.black),
              label: const Text(
                'Apply Custom Split',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.cyanAccent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.build_circle_outlined, color: Colors.cyanAccent, size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'VTG Clutch Wear Calibration',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'UDS RoutineControl 0x31 0x01 A1 01',
                      style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Resets STAT_WORKCLUTCH_WERT and STAT_PRCTMPSTRESSCLUTCH_WERT adaptation registers and runs acoustic zero-point calibration routine. Required after transfer case fluid changes or multi-disc clutch service.',
            style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isActionRunning ? null : _handleClutchCalibration,
              icon: _isActionRunning
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.play_arrow, color: Colors.black),
              label: const Text(
                'Calibrate Transfer Case Clutch',
                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                disabledBackgroundColor: Colors.grey.shade800,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
