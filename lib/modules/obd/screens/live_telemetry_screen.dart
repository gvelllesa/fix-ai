import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connection_manager.dart';
import '../services/protocols/enet_hsfz_protocol.dart';
import '../services/live_telemetry_service.dart';
import '../services/bmw_sensor_registry.dart';
import '../services/bmw_live_actuator.dart';
import '../services/actuation_guard.dart';
import '../widgets/link_status_bar.dart';

enum WarningSeverity { caution, danger }

class TelemetryWarning {
  final String title;
  final String message;
  final WarningSeverity severity;

  const TelemetryWarning({
    required this.title,
    required this.message,
    this.severity = WarningSeverity.danger,
  });
}

class LiveTelemetryScreen extends StatefulWidget {
  final EnetHsfzProtocol? activeProtocol;

  const LiveTelemetryScreen({super.key, this.activeProtocol});

  @override
  State<LiveTelemetryScreen> createState() => _LiveTelemetryScreenState();
}

class _LiveTelemetryScreenState extends State<LiveTelemetryScreen> {
  static const Color bgColor = Color(0xFF000000); // OLED pitch black for cockpit HUD
  static const Color cardColor = Color(0xFF101010);
  static const Color cardBorderColor = Color(0xFF222222);
  static const Color neonGreen = Color(0xFF1DB954);
  static const Color accentBlue = Color(0xFF29B6F6);
  static const Color alertRed = Color(0xFFE53935);
  static const Color purpleAccent = Color(0xFFAB47BC);

  late EnetHsfzProtocol _protocol;
  bool _ownsProtocol = false;
  late LiveTelemetryService _telemetryService;
  late BmwLiveActuator _actuator;
  StreamSubscription<Map<String, double>>? _readingsSub;

  final ValueNotifier<TelemetryWarning?> _warningNotifier = ValueNotifier<TelemetryWarning?>(null);
  bool _isConnected = false;
  bool _isConnecting = false;
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    if (widget.activeProtocol != null && widget.activeProtocol!.isConnected) {
      _protocol = widget.activeProtocol!;
      _ownsProtocol = false;
      _isConnected = true;
    } else if (ConnectionManager.instance.protocol.isConnected) {
      _protocol = ConnectionManager.instance.protocol;
      _ownsProtocol = false;
      _isConnected = true;
    } else {
      _protocol = EnetHsfzProtocol();
      _ownsProtocol = true;
    }

    _telemetryService = LiveTelemetryService(protocol: _protocol);
    _actuator = BmwLiveActuator(protocol: _protocol);

    // RepaintBoundary isolates individual gauges; stream only updates HUD warnings
    _readingsSub = _telemetryService.readingsStream.listen((data) {
      if (mounted) {
        _checkWarningState();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isConnected) {
        _telemetryService.startPolling();
      } else {
        _connectAndStart();
      }
    });
  }

  void _checkWarningState() {
    final knock = _telemetryService.currentReadings['knock_detected'] ?? 0.0;
    final boost = _telemetryService.currentReadings['manifold_boost_pressure'] ??
        _telemetryService.currentReadings['boost_pressure'] ??
        0.0;
    final lambda = _telemetryService.currentReadings['wideband_lambda_bank1'] ?? 1.0;
    final coolant = _telemetryService.currentReadings['engine_coolant_temperature'] ?? 0.0;
    final oil = _telemetryService.currentReadings['engine_oil_temperature'] ?? 0.0;

    TelemetryWarning? warning;
    if (knock >= 0.5) {
      warning = const TelemetryWarning(
        title: 'KNOCK DETECTED',
        message: 'DME Retarding Ignition Timing! Reduce throttle load.',
        severity: WarningSeverity.danger,
      );
    } else if (boost > 24.0) {
      warning = TelemetryWarning(
        title: 'OVERBOOST WARNING',
        message: 'Boost reached ${boost.toStringAsFixed(1)} PSI! Exceeds safe threshold.',
        severity: WarningSeverity.danger,
      );
    } else if (boost > 5.0 && lambda > 0.88) {
      warning = TelemetryWarning(
        title: 'LEAN AIR/FUEL RATIO UNDER BOOST',
        message: 'Lambda: ${lambda.toStringAsFixed(2)} at ${boost.toStringAsFixed(1)} PSI boost! Risk of detonation.',
        severity: WarningSeverity.danger,
      );
    } else if (coolant > 110.0) {
      warning = TelemetryWarning(
        title: 'HIGH ENGINE COOLANT TEMP',
        message: 'Coolant: ${coolant.toStringAsFixed(0)}°C! Check cooling system.',
        severity: WarningSeverity.danger,
      );
    } else if (oil > 125.0) {
      warning = TelemetryWarning(
        title: 'HIGH ENGINE OIL TEMP',
        message: 'Oil: ${oil.toStringAsFixed(0)}°C! Ease off load.',
        severity: WarningSeverity.caution,
      );
    }

    if (_warningNotifier.value?.title != warning?.title) {
      _warningNotifier.value = warning;
    }
  }

  @override
  void dispose() {
    _readingsSub?.cancel();
    _telemetryService.stopPolling();
    if (_telemetryService.isLogging) {
      _telemetryService.stopLogging();
    }
    _warningNotifier.dispose();
    // Safely return any active actuations back to DME control on exit
    _actuator.releaseAllActuations();
    if (_ownsProtocol) {
      _protocol.disconnect();
    }
    super.dispose();
  }

  Future<void> _connectAndStart() async {
    setState(() {
      _isConnecting = true;
    });

    try {
      final target = await _protocol.detectAdapter();
      bool ok = false;
      if (target != null) {
        ok = await _protocol.connect(host: target.host, port: target.port, useDoip: target.isDoip);
      } else {
        ok = await _protocol.connect(host: '192.168.16.101', port: 35000);
      }

      if (ok) {
        if (mounted) {
          setState(() {
            _isConnected = true;
            _isConnecting = false;
          });
          _telemetryService.startPolling();
        }
      } else {
        throw Exception('Unable to reach vehicle gateway. Ensure adapter is plugged into OBD port and connected to Wi-Fi/Ethernet.');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceAll('Exception: ', '')),
            backgroundColor: alertRed,
          ),
        );
      }
    }
  }

  Future<void> _toggleLogging() async {
    if (_telemetryService.isLogging) {
      await _telemetryService.stopLogging();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Log saved: ${_telemetryService.currentLogPath ?? ""}'),
            backgroundColor: neonGreen,
          ),
        );
        setState(() {});
      }
    } else {
      final path = await _telemetryService.startLogging();
      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Recording live sensor telemetry...'),
              backgroundColor: alertRed,
            ),
          );
        }
        setState(() {});
      }
    }
  }

  void _showActuatorTestingModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ActuatorTestingModal(
        actuator: _actuator,
        isConnected: _isConnected,
        readings: _telemetryService.currentReadings,
      ),
    );
  }

  Widget _buildWarningBanner() {
    return ValueListenableBuilder<TelemetryWarning?>(
      valueListenable: _warningNotifier,
      builder: (context, warning, _) {
        if (warning == null) return const SizedBox.shrink();

        final color = warning.severity == WarningSeverity.danger
            ? const Color(0xFFFF0033) // Flashing Knock / Danger Alert
            : const Color(0xFFFFA000);

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color, width: 1.5),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: color, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      warning.title,
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      warning.message,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final allSensors = BmwSensorRegistry.allSensors;
    final filteredSensors = _selectedCategory == 'All'
        ? allSensors
        : BmwSensorRegistry.getByCategory(_selectedCategory);

    // List of non-hero sensors for grid
    final gridSensors = filteredSensors.where((s) => s.id != 'engine_rpm' && s.id != 'boost_pressure').toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BMW Live Datalogger',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              '${allSensors.length} Channels • Zero Simulation • OLED HUD',
              style: const TextStyle(color: Colors.white38, fontSize: 11),
            ),
          ],
        ),
        actions: [
          // Actuator Testing Button
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ElevatedButton.icon(
              onPressed: _isConnected ? _showActuatorTestingModal : null,
              icon: const Icon(Icons.precision_manufacturing, size: 16),
              label: const Text('ACTUATORS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isConnected ? purpleAccent.withValues(alpha: 0.25) : Colors.white10,
                foregroundColor: _isConnected ? purpleAccent : Colors.white38,
                side: BorderSide(color: _isConnected ? purpleAccent.withValues(alpha: 0.5) : Colors.transparent),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
          // Live Logging Button
          IconButton(
            icon: Icon(
              _telemetryService.isLogging ? Icons.stop_circle : Icons.fiber_manual_record,
              color: _telemetryService.isLogging ? alertRed : Colors.white60,
            ),
            tooltip: _telemetryService.isLogging ? 'Stop Recording' : 'Record Session Log',
            onPressed: _isConnected ? _toggleLogging : null,
          ),
          IconButton(
            icon: Icon(
              _isConnected ? Icons.link : Icons.link_off,
              color: _isConnected ? neonGreen : Colors.white38,
            ),
            tooltip: _isConnected ? 'Connected' : 'Reconnect',
            onPressed: _isConnecting ? null : _connectAndStart,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Standardized 3-state Link Status Bar (P3.6)
            LinkStatusBar(
              onConnectPressed: _isConnecting ? null : _connectAndStart,
            ),

            // Automotive Warning HUD Banner (P3.5)
            _buildWarningBanner(),

            // Primary Hero Gauges: RPM & Boost (P3.2 - RepaintBoundary + ValueNotifier)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: _buildHeroGauge(
                      title: 'ENGINE RPM',
                      notifier: _telemetryService.getSensorNotifier('engine_rpm'),
                      max: 7000,
                      unit: 'RPM',
                      accentColor: neonGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildHeroGauge(
                      title: 'BOOST PRESSURE',
                      notifier: _telemetryService.getSensorNotifier('boost_pressure'),
                      max: 28.0,
                      unit: 'PSI',
                      accentColor: accentBlue,
                    ),
                  ),
                ],
              ),
            ),

            // Category Filter Chips
            Container(
              height: 38,
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: BmwSensorRegistry.categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final cat = BmwSensorRegistry.categories[index];
                  final isSelected = cat == _selectedCategory;
                  return ChoiceChip(
                    label: Text(
                      cat,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.black : Colors.white70,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: neonGreen,
                    backgroundColor: cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected ? neonGreen : cardBorderColor,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedCategory = cat;
                        });
                      }
                    },
                  );
                },
              ),
            ),

            // Secondary Sensors Grid (P3.2: 60/120 FPS Granular RepaintBoundaries)
            Expanded(
              child: gridSensors.isEmpty
                  ? Center(
                      child: Text(
                        'No sensors in $_selectedCategory',
                        style: const TextStyle(color: Colors.white38),
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.55,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: gridSensors.length,
                      itemBuilder: (context, index) {
                        final sensor = gridSensors[index];
                        return RepaintBoundary(
                          child: ValueListenableBuilder<double>(
                            valueListenable: _telemetryService.getSensorNotifier(sensor.id),
                            builder: (context, val, _) {
                              final isWarning = sensor.isWarning(val);
                              final hasReading = val > 0 || _telemetryService.currentReadings.containsKey(sensor.id);

                              return Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isWarning
                                        ? alertRed
                                        : (hasReading ? neonGreen.withValues(alpha: 0.2) : cardBorderColor),
                                    width: isWarning ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            sensor.label,
                                            style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (isWarning)
                                          const Icon(Icons.warning_amber_rounded, color: alertRed, size: 14),
                                      ],
                                    ),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          sensor.formatValue(val),
                                          style: TextStyle(
                                            color: isWarning ? alertRed : Colors.white,
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                            fontFamily: 'monospace',
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          sensor.unit,
                                          style: const TextStyle(color: Colors.white38, fontSize: 10),
                                        ),
                                      ],
                                    ),
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(2),
                                      child: LinearProgressIndicator(
                                        value: ((val - sensor.min) / (sensor.max - sensor.min)).clamp(0.0, 1.0),
                                        backgroundColor: Colors.white12,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          isWarning ? alertRed : (hasReading ? neonGreen : Colors.white24),
                                        ),
                                        minHeight: 3,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroGauge({
    required String title,
    required ValueNotifier<double> notifier,
    required double max,
    required String unit,
    required Color accentColor,
  }) {
    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: notifier,
        builder: (context, value, _) {
          final ratio = (value / max).clamp(0.0, 1.0);

          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: accentColor,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      value.toStringAsFixed(unit == 'PSI' ? 1 : 0),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      unit,
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: ratio,
                    backgroundColor: Colors.white12,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    minHeight: 5,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Modal Bottom Sheet for ISTA / ProTool Active Component Testing
class _ActuatorTestingModal extends StatefulWidget {
  final BmwLiveActuator actuator;
  final bool isConnected;
  final Map<String, double> readings;

  const _ActuatorTestingModal({
    required this.actuator,
    required this.isConnected,
    this.readings = const {},
  });

  @override
  State<_ActuatorTestingModal> createState() => _ActuatorTestingModalState();
}

class _ActuatorTestingModalState extends State<_ActuatorTestingModal> {
  static const Color sheetBg = Color(0xFF161616);
  static const Color boxBg = Color(0xFF222222);
  static const Color neonGreen = Color(0xFF1DB954);
  static const Color alertRed = Color(0xFFE53935);
  static const Color accentBlue = Color(0xFF29B6F6);
  static const Color purpleAccent = Color(0xFFAB47BC);
  static const Color orangeWarning = Color(0xFFFF9800);

  bool _isBleeding = false;
  int _fanSpeed = 0;
  bool _tevActive = false;
  bool _disaStage1Open = false;
  bool _disaStage2Open = false;
  bool _intakeVanosActive = false;
  bool _exhaustVanosActive = false;
  bool _exhaustFlapOpen = false;
  bool _needleSweepInProgress = false;
  final Map<int, bool> _cylinderCutoffs = {1: false, 2: false, 3: false, 4: false, 5: false, 6: false};
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _isBleeding = widget.actuator.isCoolantBleedingActive;
    _fanSpeed = widget.actuator.radiatorFanSpeed;
    _tevActive = widget.actuator.isFuelTankVentValveActive;
    _disaStage1Open = widget.actuator.disaValvesState[1] ?? false;
    _disaStage2Open = widget.actuator.disaValvesState[2] ?? false;
    _intakeVanosActive = widget.actuator.isIntakeVanosActive;
    _exhaustVanosActive = widget.actuator.isExhaustVanosActive;
    _exhaustFlapOpen = widget.actuator.isExhaustFlapOpen;
    for (int i = 1; i <= 6; i++) {
      _cylinderCutoffs[i] = widget.actuator.cylinderCutoffState[i] ?? false;
    }
  }

  void _showFeedback(String msg) {
    setState(() {
      _statusMessage = msg;
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          if (_statusMessage == msg) _statusMessage = null;
        });
      }
    });
  }

  Future<bool> _guardActuation({
    required ActuationRisk risk,
    String? confirmTitle,
    String? confirmDescriptionKa,
    int activeCutCylinders = 0,
  }) async {
    try {
      ActuationGuard.verify(
        risk: risk,
        rpm: widget.readings['engine_rpm'],
        speedKmh: widget.readings['vehicle_speed'],
        voltage: widget.readings['battery_voltage'],
        activeCutCylinders: activeCutCylinders,
      );
    } on InterlockViolation catch (e) {
      _showFeedback(e.messageKa);
      return false;
    }
    if (confirmTitle != null && confirmDescriptionKa != null) {
      if (!mounted) return false;
      final confirmed = await ActuationGuard.confirmActuation(
        context,
        title: confirmTitle,
        descriptionKa: confirmDescriptionKa,
      );
      if (!confirmed) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: const BoxDecoration(
        color: sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      'Component Actuator Testing',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'ISTA / ProTool Diagnostic Routines (UDS 0x2F / 0x31)',
                      style: TextStyle(color: Colors.white38, fontSize: 11),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white60),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          // Status Feedback Toast Banner
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: neonGreen.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: neonGreen.withValues(alpha: 0.4)),
              ),
              child: Text(
                _statusMessage!,
                style: const TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),

          // Safety Warning
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: alertRed.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: alertRed.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: const [
                Icon(Icons.warning_amber_rounded, color: alertRed, size: 18),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Ensure vehicle is parked with ignition ON or engine idling. Direct ECU output commands bypass autonomous safety checks.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Actuator Controls
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. Coolant Bleeding Routine
                _buildActuatorCard(
                  title: 'Coolant Bleeding Routine (12-Min)',
                  subtitle: 'Automatic electric water pump purge cycle (UDS 0x31 0x01 0x10 0x03)',
                  icon: Icons.water_drop,
                  accentColor: accentBlue,
                  isActive: _isBleeding,
                  child: Column(
                    children: [
                      if (_isBleeding) ...[
                        const ClipRRect(
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                          child: LinearProgressIndicator(
                            color: accentBlue,
                            backgroundColor: Colors.white12,
                            minHeight: 4,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Pump is operating in automatic pulsing sequence (~12 minutes remaining)...',
                          style: TextStyle(color: accentBlue, fontSize: 11),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                if (_isBleeding) {
                                  final ok = await widget.actuator.stopCoolantBleedingProcedure();
                                  if (ok) {
                                    setState(() => _isBleeding = false);
                                    _showFeedback('Coolant Bleeding Stopped');
                                  }
                                } else {
                                  final allowed = await _guardActuation(
                                    risk: ActuationRisk.requiresEngineOff,
                                    confirmTitle: 'Coolant Bleeding (12 წთ)',
                                    confirmDescriptionKa:
                                        'ელექტრო წყლის ტუმბოს 12-წუთიანი განჰაერების ციკლი მოითხოვს გამორთულ ძრავს (KOEO) და >= 12.2V ძაბვას. გსურთ გაშვება?',
                                  );
                                  if (!allowed) return;
                                  final ok = await widget.actuator.triggerCoolantBleedingProcedure();
                                  if (ok) {
                                    setState(() => _isBleeding = true);
                                    _showFeedback('Coolant Bleeding 12-Min Cycle Activated');
                                  }
                                }
                              },
                              icon: Icon(_isBleeding ? Icons.stop : Icons.play_arrow),
                              label: Text(_isBleeding ? 'STOP BLEED ROUTINE' : 'START 12-MIN BLEED ROUTINE'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isBleeding ? alertRed : accentBlue,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 2. Radiator Fan Stepped Test
                _buildActuatorCard(
                  title: 'Radiator Fan Step Test',
                  subtitle: 'Direct PWM speed override (UDS 0x2F 0xD0 0x12 0x03 [pct])',
                  icon: Icons.toys,
                  accentColor: neonGreen,
                  isActive: _fanSpeed > 0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Current Speed: $_fanSpeed%', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(_fanSpeed == 0 ? 'DME Autonomous' : 'Manual Override (Max 30s)',
                              style: TextStyle(color: _fanSpeed == 0 ? Colors.white38 : neonGreen, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: _fanSpeed / 100.0,
                          backgroundColor: Colors.white12,
                          color: neonGreen,
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [0, 20, 50, 100].map((speed) {
                          final isCurrent = _fanSpeed == speed;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 3),
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  backgroundColor: isCurrent ? neonGreen.withValues(alpha: 0.2) : Colors.transparent,
                                  side: BorderSide(color: isCurrent ? neonGreen : Colors.white24),
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () async {
                                  if (speed > 0) {
                                    final allowed = await _guardActuation(
                                      risk: ActuationRisk.safeParked,
                                    );
                                    if (!allowed) return;
                                  }
                                  final ok = await widget.actuator.testRadiatorFanStep(speed);
                                  if (ok) {
                                    setState(() => _fanSpeed = speed);
                                    _showFeedback('Fan speed set to $speed%');
                                  }
                                },
                                child: Text(
                                  speed == 0 ? 'OFF' : '$speed%',
                                  style: TextStyle(
                                    color: isCurrent ? neonGreen : Colors.white70,
                                    fontSize: 12,
                                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 3. Selective Cylinder Cutoff (Cyl 1-6)
                _buildActuatorCard(
                  title: 'Selective Cylinder Cutoff (Cylinders 1-6)',
                  subtitle: 'Temporarily suppress injection/spark to isolate misfires (UDS 0x2F 0xD0 0x20+N)',
                  icon: Icons.power_settings_new,
                  accentColor: alertRed,
                  isActive: _cylinderCutoffs.values.any((c) => c),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tap a cylinder to CUT OFF fuel & spark (Idle only, max 1 cylinder, 30s auto-release).',
                        style: TextStyle(color: Colors.white54, fontSize: 11),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: List.generate(6, (idx) {
                          final cyl = idx + 1;
                          final isCut = _cylinderCutoffs[cyl] ?? false;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: isCut ? alertRed : Colors.white10,
                                  foregroundColor: isCut ? Colors.white : Colors.white70,
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    side: BorderSide(color: isCut ? alertRed : Colors.white24),
                                  ),
                                ),
                                onPressed: () async {
                                  final nextState = !isCut;
                                  if (nextState) {
                                    final activeOthers = _cylinderCutoffs.entries
                                        .where((e) => e.key != cyl && e.value)
                                        .length;
                                    final allowed = await _guardActuation(
                                      risk: ActuationRisk.requiresIdleOnly,
                                      activeCutCylinders: activeOthers,
                                      confirmTitle: 'ცილინდრის #$cyl გათიშვა',
                                      confirmDescriptionKa:
                                          'ცილინდრ #$cyl-ზე დროებით შეწყდება საწვავის მიწოდება და ნაპერწკალი (მაქს. 30 წმ). დარწმუნდით, რომ ძრავი მუშაობს უქმ სვლაზე (550–1100 RPM) და ავტომობილი დგას.',
                                    );
                                    if (!allowed) return;
                                  }
                                  final ok = await widget.actuator.testCylinderCutoff(cyl, nextState);
                                  if (ok) {
                                    setState(() => _cylinderCutoffs[cyl] = nextState);
                                    _showFeedback(nextState ? 'Cylinder $cyl CUT OFF' : 'Cylinder $cyl RESTORED');
                                  }
                                },
                                child: Text(
                                  'C$cyl',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 4. DISA Variable Intake Valves
                _buildActuatorCard(
                  title: 'DISA Variable Intake Valves',
                  subtitle: 'Test Stage 1 and Stage 2 manifold runner flaps (UDS 0x2F 0xD0 0x16)',
                  icon: Icons.air,
                  accentColor: orangeWarning,
                  isActive: _disaStage1Open || _disaStage2Open,
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _disaStage1Open ? orangeWarning.withValues(alpha: 0.2) : Colors.transparent,
                            side: BorderSide(color: _disaStage1Open ? orangeWarning : Colors.white24),
                          ),
                          onPressed: () async {
                            final next = !_disaStage1Open;
                            if (next) {
                              final allowed = await _guardActuation(
                                risk: ActuationRisk.requiresEngineOff,
                              );
                              if (!allowed) return;
                            }
                            final ok = await widget.actuator.testDisaValves(1, next);
                            if (ok) {
                              setState(() => _disaStage1Open = next);
                              _showFeedback('DISA Stage 1: ${next ? "OPEN" : "CLOSED"}');
                            }
                          },
                          child: Text(
                            'STAGE 1: ${_disaStage1Open ? "OPEN" : "CLOSED"}',
                            style: TextStyle(
                              color: _disaStage1Open ? orangeWarning : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: _disaStage2Open ? orangeWarning.withValues(alpha: 0.2) : Colors.transparent,
                            side: BorderSide(color: _disaStage2Open ? orangeWarning : Colors.white24),
                          ),
                          onPressed: () async {
                            final next = !_disaStage2Open;
                            if (next) {
                              final allowed = await _guardActuation(
                                risk: ActuationRisk.requiresEngineOff,
                              );
                              if (!allowed) return;
                            }
                            final ok = await widget.actuator.testDisaValves(2, next);
                            if (ok) {
                              setState(() => _disaStage2Open = next);
                              _showFeedback('DISA Stage 2: ${next ? "OPEN" : "CLOSED"}');
                            }
                          },
                          child: Text(
                            'STAGE 2: ${_disaStage2Open ? "OPEN" : "CLOSED"}',
                            style: TextStyle(
                              color: _disaStage2Open ? orangeWarning : Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 5. VANOS Solenoid Pulse Tests
                _buildActuatorCard(
                  title: 'VANOS Camshaft Timing Solenoids',
                  subtitle: 'Test hydraulic camshaft actuator solenoids (UDS 0x2F 0xD0 0x18)',
                  icon: Icons.sync,
                  accentColor: purpleAccent,
                  isActive: _intakeVanosActive || _exhaustVanosActive,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _intakeVanosActive ? purpleAccent : Colors.white10,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final next = !_intakeVanosActive;
                            if (next) {
                              final allowed = await _guardActuation(
                                risk: ActuationRisk.requiresEngineOff,
                                confirmTitle: 'Intake VANOS სოლენოიდის ტესტი',
                                confirmDescriptionKa:
                                    'VANOS სოლენოიდის 100%-იანი გააქტიურება დასაშვებია მხოლოდ გამორთულ ძრავზე (KOEO). გსურთ გაგრძელება?',
                              );
                              if (!allowed) return;
                            }
                            final ok = await widget.actuator.testVanosSolenoid(false, next);
                            if (ok) {
                              setState(() => _intakeVanosActive = next);
                              _showFeedback('Intake VANOS ${next ? "TRIGGERED (100%)" : "OFF"}');
                            }
                          },
                          child: Text(_intakeVanosActive ? 'INTAKE: ON' : 'PULSE INTAKE', style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _exhaustVanosActive ? purpleAccent : Colors.white10,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: () async {
                            final next = !_exhaustVanosActive;
                            if (next) {
                              final allowed = await _guardActuation(
                                risk: ActuationRisk.requiresEngineOff,
                                confirmTitle: 'Exhaust VANOS სოლენოიდის ტესტი',
                                confirmDescriptionKa:
                                    'VANOS სოლენოიდის 100%-იანი გააქტიურება დასაშვებია მხოლოდ გამორთულ ძრავზე (KOEO). გსურთ გაგრძელება?',
                              );
                              if (!allowed) return;
                            }
                            final ok = await widget.actuator.testVanosSolenoid(true, next);
                            if (ok) {
                              setState(() => _exhaustVanosActive = next);
                              _showFeedback('Exhaust VANOS ${next ? "TRIGGERED (100%)" : "OFF"}');
                            }
                          },
                          child: Text(_exhaustVanosActive ? 'EXHAUST: ON' : 'PULSE EXHAUST', style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // 6. TEV Fuel Tank Purge Valve & Exhaust Flap
                Row(
                  children: [
                    // TEV
                    Expanded(
                      child: _buildActuatorCard(
                        title: 'TEV Purge Valve',
                        subtitle: 'UDS 0x2F 0xD0 0x14',
                        icon: Icons.local_gas_station,
                        accentColor: neonGreen,
                        isActive: _tevActive,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _tevActive ? neonGreen : Colors.white10,
                            foregroundColor: _tevActive ? Colors.black : Colors.white,
                          ),
                          onPressed: () async {
                            final next = !_tevActive;
                            if (next) {
                              final allowed = await _guardActuation(
                                risk: ActuationRisk.safeParked,
                              );
                              if (!allowed) return;
                            }
                            final ok = await widget.actuator.testFuelTankVentValve(next);
                            if (ok) {
                              setState(() => _tevActive = next);
                              _showFeedback('Purge Valve ${next ? "ACTIVATED" : "RELEASED"}');
                            }
                          },
                          child: Text(_tevActive ? 'ACTIVE (100%)' : 'TEST PURGE', style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Exhaust Flap
                    Expanded(
                      child: _buildActuatorCard(
                        title: 'Exhaust Sound Flap',
                        subtitle: 'UDS 0x2F 0x31 0x0A',
                        icon: Icons.volume_up,
                        accentColor: orangeWarning,
                        isActive: _exhaustFlapOpen,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _exhaustFlapOpen ? orangeWarning : Colors.white10,
                            foregroundColor: _exhaustFlapOpen ? Colors.black : Colors.white,
                          ),
                          onPressed: () async {
                            final next = !_exhaustFlapOpen;
                            if (next) {
                              final allowed = await _guardActuation(
                                risk: ActuationRisk.safeParked,
                              );
                              if (!allowed) return;
                            }
                            final ok = await widget.actuator.setExhaustFlap(next);
                            if (ok) {
                              setState(() => _exhaustFlapOpen = next);
                              _showFeedback('Exhaust Flap ${next ? "OPEN" : "CLOSED"}');
                            }
                          },
                          child: Text(_exhaustFlapOpen ? 'OPEN' : 'CLOSED', style: const TextStyle(fontSize: 11)),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 7. KOMBI Gauge Needle Sweep
                _buildActuatorCard(
                  title: 'KOMBI Gauge Needle Sweep',
                  subtitle: 'Full sweep of speed, tachometer, and gauge needles (KOMBI 0x60 UDS 0x2F 0xD0 0x01)',
                  icon: Icons.speed,
                  accentColor: Colors.amber,
                  isActive: _needleSweepInProgress,
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _needleSweepInProgress
                              ? null
                              : () async {
                                  final allowed = await _guardActuation(
                                    risk: ActuationRisk.safeParked,
                                  );
                                  if (!allowed) return;
                                  setState(() => _needleSweepInProgress = true);
                                  _showFeedback('Running KOMBI Gauge Needle Sweep...');
                                  final ok = await widget.actuator.triggerKombiGaugeNeedleSweep();
                                  if (mounted) {
                                    setState(() => _needleSweepInProgress = false);
                                    _showFeedback(ok ? 'Needle Sweep Completed' : 'KOMBI sweep failed');
                                  }
                                },
                          icon: _needleSweepInProgress
                              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.play_circle_outline, size: 16),
                          label: Text(_needleSweepInProgress ? 'SWEEPING GAUGES...' : 'TRIGGER NEEDLE SWEEP'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 8. Safety Reset All Actuations Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: alertRed,
                      side: const BorderSide(color: alertRed),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () async {
                      await widget.actuator.releaseAllActuations();
                      if (mounted) {
                        setState(() {
                          _isBleeding = false;
                          _fanSpeed = 0;
                          _tevActive = false;
                          _disaStage1Open = false;
                          _disaStage2Open = false;
                          _intakeVanosActive = false;
                          _exhaustVanosActive = false;
                          _exhaustFlapOpen = false;
                          _needleSweepInProgress = false;
                          for (int i = 1; i <= 6; i++) {
                            _cylinderCutoffs[i] = false;
                          }
                        });
                        _showFeedback('All Actuations Released - Returned to ECU Control');
                      }
                    },
                    icon: const Icon(Icons.restart_alt, size: 20),
                    label: const Text(
                      'RELEASE ALL ACTUATIONS (SAFETY RESET)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActuatorCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accentColor,
    required bool isActive,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: boxBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isActive ? accentColor : Colors.white12,
          width: isActive ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: isActive ? accentColor : Colors.white60, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                  ],
                ),
              ),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: accentColor.withValues(alpha: 0.6)),
                  ),
                  child: Text(
                    'ACTIVE',
                    style: TextStyle(color: accentColor, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
