import 'dart:async';
import 'package:flutter/material.dart';
import '../services/bmw_service_functions.dart';
import '../services/protocols/enet_hsfz_protocol.dart';
import '../widgets/advanced_connection_dialog.dart';

/// BMW Dealer-Level Workshop Routines & Service Functions Screen
///
/// Ports BimmerGeeks ProTool & ISTA dealer-level service functions to FIX AI:
/// 1. Battery Registration (DME 0xA010 & CAS/BDC KLASSE_BATTERIE)
/// 2. Injector Flow Compensation (DME DIDs 0xD101..0xD106)
/// 3. ABS / DSC Hydraulic Brake Bleeding (DSC 0x0322)
/// 4. Electronic Parking Brake Service Mode (EMF 0xE001 / 0xE002)
/// 5. ZF Transmission Adaptations Readout & Reset (EGS 0xD301..0xD305 & 0x0F01)
/// 6. Valvetronic & Throttle Stop Re-learn (DME 0x1005)
/// 7. DPF Regeneration & Ash Mass Reset (DME/DDE res_dpfRegen 0xD015 / 0xD016 & DID 0xD017)
/// 8. Steering Angle Sensor (SZL / LWS) Zero-Point Calibration (DSC/EPS res_CalSZL 0xA010 & DID 0x4002)
/// 9. FRM Short-Circuit Counter Reset (FRM res_ShortsCir 0xB001)
/// 10. Low Pressure Fuel Pump Priming (EKP/DME res_PrimeFuel 0xF010)
/// 11. Transport Mode Deactivation / Activation (Gateway/BDC res_transPort 0x28 0x00)
/// 12. VTG Transfer Case Fluid Reset (VTG res_vgsgReset 0xA105)
class ServiceFunctionsScreen extends StatefulWidget {
  final EnetHsfzProtocol? activeProtocol;

  const ServiceFunctionsScreen({super.key, this.activeProtocol});

  @override
  State<ServiceFunctionsScreen> createState() => _ServiceFunctionsScreenState();
}

class _ServiceFunctionsScreenState extends State<ServiceFunctionsScreen> {
  late BmwServiceFunctions _service;
  bool _isConnected = false;
  double? _liveVoltage;
  int? _odometerKm;
  bool _isActionRunning = false;
  String _activeActionName = '';
  double _actionProgress = 0.0;
  String _actionStatusMessage = '';

  // Condition Based Service (CBS) State
  List<CbsItemStatus> _cbsItems = [];
  bool _isLoadingCbs = false;

  // Idle RPM State
  int _selectedIdleOffset = 0;
  bool _idleWithAc = false;

  // Active Sound Design (ASD) State
  AsdState _asdState = AsdState.active;
  bool _isLoadingAsd = false;

  // Exhaust Flap Control State
  ExhaustFlapMode _exhaustFlapMode = ExhaustFlapMode.autoOem;
  bool _isLoadingExhaustFlap = false;

  // Advanced Mechanical Adaptations & Calibration State
  int _airSuspensionLeftMm = 0;
  int _airSuspensionRightMm = 0;
  List<CylinderSmoothnessData>? _lastSmoothnessData;
  bool _isLoadingSmoothness = false;

  // Theme Constants
  static const Color _bgDark = Color(0xFF0D1117);
  static const Color _cardDark = Color(0xFF161B22);
  static const Color _cardBorder = Color(0xFF30363D);

  @override
  void initState() {
    super.initState();
    _service = BmwServiceFunctions(protocol: widget.activeProtocol);
    _checkInitialConnection();
  }

  Future<void> _checkInitialConnection() async {
    final connected = await _service.ensureConnected();
    if (mounted) {
      setState(() => _isConnected = connected);
      if (connected) {
        _refreshVehicleState();
      }
    }
  }

  Future<void> _refreshVehicleState() async {
    final volt = await _service.readBatteryVoltage();
    final odo = await _service.readVehicleMileageKm();
    if (mounted) {
      setState(() {
        _liveVoltage = volt;
        _odometerKm = odo;
      });
      _loadCbsStatus();
      _loadIdleRpm();
      _loadAsdState();
      _loadExhaustFlapState();
    }
  }

  /// Safety confirmation dialog with workshop checklist
  Future<bool> _showSafetyDialog({
    required String title,
    required String description,
    required Color accentColor,
    List<String>? extraChecks,
  }) async {
    bool confirmed = false;
    final checks = [
      'Vehicle stationary & parking brake engaged',
      'Ignition ON (Terminal 15 active)',
      'Engine OFF (Do not start engine during routine)',
      'Stable battery supply / Workshop charger connected',
      ...?extraChecks,
    ];

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
                    child: Icon(Icons.shield_outlined, color: accentColor, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
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
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Workshop Safety Interlocks:',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          ...checks.map(
                            (c) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.check_circle_outline, color: accentColor, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      c,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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
                        'I confirm all workshop prerequisites are met',
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
                  child: const Text('Abort', style: TextStyle(color: Colors.white60)),
                ),
                ElevatedButton(
                  onPressed: confirmed ? () => Navigator.pop(ctx, true) : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: Colors.white10,
                  ),
                  child: const Text('Execute Routine', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );

    return result ?? false;
  }

  /// Routine Result Modal Dialog
  void _showResultDialog(ServiceRoutineResult result) {
    showDialog(
      context: context,
      builder: (ctx) {
        final color = result.success ? Colors.greenAccent : Colors.redAccent;
        return AlertDialog(
          backgroundColor: _cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.6)),
          ),
          title: Row(
            children: [
              Icon(result.success ? Icons.check_circle : Icons.error, color: color, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  result.title,
                  style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
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
                  result.message,
                  style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
                ),
                if (result.nrcCode != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'UDS NRC 0x${result.nrcCode!.toRadixString(16).toUpperCase()}: ${result.nrcDescription}',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ),
                ],
                if (result.details.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _bgDark,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: result.details.entries.map((e) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('${e.key}:', style: const TextStyle(color: Colors.white60, fontSize: 11)),
                              Text('${e.value}', style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.black,
              ),
              child: const Text('Dismiss', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  // ===========================================================================
  // 1. BATTERY REGISTRATION HANDLER
  // ===========================================================================
  Future<void> _handleBatteryRegistration() async {
    BatteryProfile selectedProfile = BatteryProfile.agm90;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.battery_charging_full, color: Colors.cyanAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Register New Battery',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Select replacement battery capacity and chemistry (AGM, Wet Lead-Acid, or 69 Ah LiFePO4 for M3/M4). FIX AI will write the KLASSE_BATTERIE coding byte to CAS/BDC and execute DME Routine 0x31 0x01 A0 10 to reset the aging counter.',
                    style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: _bgDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      children: BatteryProfile.values.map((profile) {
                        final isSelected = selectedProfile == profile;
                        return InkWell(
                          onTap: () => setSheetState(() => selectedProfile = profile),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.cyanAccent.withValues(alpha: 0.1) : Colors.transparent,
                              border: Border(
                                bottom: profile != BatteryProfile.values.last
                                    ? const BorderSide(color: Colors.white10)
                                    : BorderSide.none,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: isSelected ? Colors.cyanAccent : Colors.white38,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    profile.label,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: profile.isAgm
                                        ? Colors.cyanAccent.withValues(alpha: 0.15)
                                        : (profile.isLithium
                                            ? Colors.purpleAccent.withValues(alpha: 0.2)
                                            : Colors.amberAccent.withValues(alpha: 0.15)),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    profile.isAgm
                                        ? 'AGM'
                                        : (profile.isLithium ? 'LiFePO4' : 'WET LEAD'),
                                    style: TextStyle(
                                      color: profile.isAgm
                                          ? Colors.cyanAccent
                                          : (profile.isLithium ? Colors.purpleAccent : Colors.amberAccent),
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check, color: Colors.black),
                    label: Text(
                      'Proceed with ${selectedProfile.label}',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final safetyOk = await _showSafetyDialog(
      title: 'Battery Registration Safety Check',
      description: 'The Intelligent Battery Sensor (IBS) will reset its internal SOC and state-of-charge calculation model. The vehicle odometer will be stamped into DME flash.',
      accentColor: Colors.cyanAccent,
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Registering Battery (${selectedProfile.label})';
      _actionProgress = 0.1;
      _actionStatusMessage = 'Initializing UDS diagnostic session...';
    });

    final result = await _service.registerBattery(
      profile: selectedProfile,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _refreshVehicleState();
      _showResultDialog(result);
    }
  }

  /// ISTA Battery Replacement History Viewer (Status Batterietausch / Kilometerstand bei Batterietausch)
  Future<void> _showBatteryHistoryModal() async {
    List<BatteryHistoryRecord> records = [];
    PowerSupplyStatus? powerStatus;
    bool isLoading = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (isLoading) {
              Future.microtask(() async {
                final historyList = await _service.readBatteryHistory();
                final pStatus = await _service.readPowerSupplyStatus();
                if (ctx.mounted) {
                  setSheetState(() {
                    records = historyList;
                    powerStatus = pStatus;
                    isLoading = false;
                  });
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.history, color: Colors.cyanAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'რეგისტრაციის ისტორია (ქარხნული)',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'DME 0x12 DID 0xD012 • Status Batterietausch',
                              style: TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white60),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (powerStatus != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              const Text('Terminal 30', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${powerStatus!.terminal30Voltage.toStringAsFixed(2)} V',
                                  style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('Terminal 15', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${powerStatus!.terminal15Voltage.toStringAsFixed(2)} V',
                                  style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('IBS SoC', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${powerStatus!.batterySocPercent}%',
                                  style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                            ],
                          ),
                          Column(
                            children: [
                              const Text('IBS SoH', style: TextStyle(color: Colors.white54, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text('${powerStatus!.batterySohPercent}%',
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(color: Colors.cyanAccent),
                            SizedBox(height: 14),
                            Text(
                              'DME DID 0xD012 ისტორიის კითხვა...',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (records.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.info_outline, color: Colors.white38, size: 36),
                          SizedBox(height: 10),
                          Text(
                            'არ მოიძებნა წინა რეგისტრაციის ჩანაწერები DME-ში',
                            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'ავტომობილის ძრავის კომპიუტერში (DME) ისტორიის მეხსიერება ცარიელია ან რეგისტრაცია ჯერ არ ჩატარებულა.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: records.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, idx) {
                          final rec = records[idx];
                          final isLatest = rec.replacementIndex == 1;
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _bgDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isLatest ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.white12,
                                width: isLatest ? 1.5 : 1.0,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 34,
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isLatest
                                        ? Colors.cyanAccent.withValues(alpha: 0.2)
                                        : Colors.white10,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '#${rec.replacementIndex}',
                                    style: TextStyle(
                                      color: isLatest ? Colors.cyanAccent : Colors.white70,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${rec.odometerKm} km',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                          if (isLatest) ...[
                                            const SizedBox(width: 8),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.cyanAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'ბოლო (Latest)',
                                                style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'სიმძლავრე: ${rec.capacityAh} Ah • ${rec.batteryTypeLabel}',
                                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                                      ),
                                      if (rec.timestamp != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'თარიღი: ${rec.timestamp!.toLocal().toString().split(".")[0]}',
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(
                                  rec.isAgm ? Icons.battery_charging_full : Icons.battery_std,
                                  color: rec.isAgm ? Colors.cyanAccent : Colors.amberAccent,
                                  size: 24,
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('დახურვა (Close)'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // 2. INJECTOR FLOW COMPENSATION HANDLER (3, 4, 6, 8 Cylinders & B-Series Support)
  // ===========================================================================
  Future<void> _handleInjectorCalibration() async {
    List<InjectorData> injectors = [];
    bool isReading = true;
    int selectedCylinders = 6;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // Trigger reading once when opened or when cylinder count changes
            if (isReading && injectors.isEmpty) {
              Future.microtask(() async {
                final list = await _service.readAllInjectors(cylinders: selectedCylinders);
                if (ctx.mounted) {
                  setSheetState(() {
                    injectors = list;
                    isReading = false;
                  });
                }
              });
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.tune, color: Colors.amberAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Injector Flow Calibration',
                          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setSheetState(() {
                            isReading = true;
                            injectors.clear();
                          });
                        },
                        icon: const Icon(Icons.refresh, color: Colors.amberAccent),
                        tooltip: 'Re-read DIDs from DME',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Direct-injection piezo/solenoid injectors require flow and energy calibration codes stamped onto the injector body (6-digit for N-series or 6-8 alphanumeric chars for B-series).',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),

                  // Engine Cylinder Count Selector (3, 4, 6, 8 Cylinders)
                  Row(
                    children: [
                      const Text(
                        'Engine Config: ',
                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.5)),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: selectedCylinders,
                            dropdownColor: _cardDark,
                            isDense: true,
                            style: const TextStyle(color: Colors.amberAccent, fontSize: 13, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('3 Cyl [B38] (DIDs 0xD101..3)')),
                              DropdownMenuItem(value: 4, child: Text('4 Cyl [N20/B48] (DIDs 0xD101..4)')),
                              DropdownMenuItem(value: 6, child: Text('6 Cyl [N55/B58] (DIDs 0xD101..6)')),
                              DropdownMenuItem(value: 8, child: Text('8 Cyl [N63/S63] (DIDs 0xD101..8)')),
                            ],
                            onChanged: isReading ? null : (val) {
                              if (val != null && val != selectedCylinders) {
                                setSheetState(() {
                                  selectedCylinders = val;
                                  isReading = true;
                                  injectors.clear();
                                });
                              }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (isReading) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(color: Colors.amberAccent),
                      ),
                    ),
                    Center(
                      child: Text(
                        'Reading DIDs 0xD101..0xD10$selectedCylinders from DME (0x12)...',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                      ),
                    ),
                  ] else ...[
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: injectors.length,
                        itemBuilder: (c, idx) {
                          final inj = injectors[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: _bgDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: Colors.amberAccent.withValues(alpha: 0.2),
                                  child: Text(
                                    '${inj.cylinder}',
                                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Cylinder ${inj.cylinder}',
                                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      Text(
                                        'DID 0x${inj.did.toRadixString(16).toUpperCase()}',
                                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black26,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    inj.formattedCode,
                                    style: const TextStyle(
                                      color: Colors.amberAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.white70, size: 18),
                                  onPressed: () async {
                                    final newCode = await _promptNewInjectorCode(inj.cylinder, inj.code);
                                    if (newCode != null && newCode.isNotEmpty) {
                                      if (ctx.mounted) {
                                        Navigator.pop(ctx);
                                      }
                                      _writeInjectorValue(inj.cylinder, newCode);
                                    }
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _promptNewInjectorCode(int cylinder, String currentCode) async {
    final controller = TextEditingController(text: currentCode.replaceAll(' ', ''));
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _cardDark,
          title: Text('Edit Cylinder $cylinder Code', style: const TextStyle(color: Colors.white, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter 6 to 8 alphanumeric characters printed on injector body (e.g. 578214 or A374E8):',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLength: 8,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(color: Colors.amberAccent, fontSize: 18, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                decoration: const InputDecoration(
                  hintText: 'e.g. 578214 or A374E8',
                  hintStyle: TextStyle(color: Colors.white24),
                  border: OutlineInputBorder(),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.amberAccent)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Program', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _writeInjectorValue(int cylinder, String code) async {
    final safetyOk = await _showSafetyDialog(
      title: 'Program Cylinder $cylinder Injector',
      description: 'New flow compensation code "$code" will be written via UDS 0x2E into DME memory. Engine must NOT be running.',
      accentColor: Colors.amberAccent,
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Calibrating Injector #$cylinder';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending WriteDataByIdentifier (0x2E)...';
    });

    final result = await _service.writeInjectorCompensation(
      cylinder: cylinder,
      compensationCode: code,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 3. ABS / DSC GUIDED 4-CORNER BRAKE BLEEDING HANDLER (ISTA ABL_DIT_AS3450_ENTL)
  // ===========================================================================
  Future<void> _handleDscBrakeBleeding() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Guided 4-Corner Brake Bleeding (DSC_ENTL)',
      description: 'Automated hydraulic procedure (ABL_DIT_AS3450_ENTL / DSC_ENTLUEFTUNG) purges air from each wheel circuit.\n\nConnect pressurized brake bleeder (approx 1.5 - 2.0 bar) and ensure reservoir is FULL.\n\nRecommended Sequence: Rear Right -> Rear Left -> Front Right -> Front Left.',
      accentColor: Colors.redAccent,
      extraChecks: [
        'Pressurized bleeder bottle connected to caliper bleeder screw',
        'Brake master cylinder filled with fresh DOT 4 or 5.1 fluid',
        'Service technician ready to pump brake pedal when prompted',
      ],
    );

    if (!safetyOk || !mounted) return;

    DscBleedCorner selectedCorner = DscBleedCorner.rearRight;
    bool isBleeding = false;
    double bleedProgress = 0.0;
    String statusMessage = 'Select a corner to begin hydraulic bleeding.';
    int countdown = 0;
    bool pedalPrompt = false;
    final Map<DscBleedCorner, String> cornerStatuses = {
      DscBleedCorner.rearRight: 'Pending',
      DscBleedCorner.rearLeft: 'Pending',
      DscBleedCorner.frontRight: 'Pending',
      DscBleedCorner.frontLeft: 'Pending',
    };

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> runCorner(DscBleedCorner corner) async {
              setModalState(() {
                isBleeding = true;
                selectedCorner = corner;
                bleedProgress = 0.05;
                statusMessage = 'Connecting to DSC (0x29) for ${corner.label}...';
                countdown = 0;
                pedalPrompt = false;
                cornerStatuses[corner] = 'Bleeding...';
              });

              await for (final event in _service.executeGuidedCornerBleed(corner: corner)) {
                if (!ctx.mounted) break;
                setModalState(() {
                  bleedProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
                  statusMessage = (event['message'] as String?) ?? '';
                  countdown = (event['countdownSeconds'] as int?) ?? 0;
                  pedalPrompt = (event['pedalPrompt'] as bool?) ?? false;
                });

                if (event['step'] == 'COMPLETE') {
                  setModalState(() {
                    cornerStatuses[corner] = 'Completed ✓';
                  });
                } else if (event['step'] == 'FAILED' || event['step'] == 'EXCEPTION') {
                  setModalState(() {
                    cornerStatuses[corner] = 'Failed ✗';
                  });
                }
              }

              if (ctx.mounted) {
                setModalState(() {
                  isBleeding = false;
                  pedalPrompt = false;
                  countdown = 0;
                });
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.redAccent.withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.invert_colors, color: Colors.redAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Guided 4-Corner Brake Bleeding',
                                style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                              Text(
                                'ABL_DIT_AS3450_ENTL / DSC_ENTLUEFTUNG (0x29)',
                                style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'BMW Factory Sequence: Rear Right (HR) -> Rear Left (HL) -> Front Right (VR) -> Front Left (VL).',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // 4 Corner Selector Cards
                    ...DscBleedCorner.values.map((corner) {
                      final isCurrent = selectedCorner == corner;
                      final st = cornerStatuses[corner] ?? 'Pending';
                      final isCompleted = st.contains('Completed');
                      final isFailed = st.contains('Failed');
                      final isThisBleeding = isBleeding && isCurrent;

                      Color borderColor = isCurrent ? Colors.redAccent : Colors.white12;
                      if (isCompleted) borderColor = Colors.tealAccent;
                      if (isFailed) borderColor = Colors.orangeAccent;

                      return GestureDetector(
                        onTap: isBleeding ? null : () => setModalState(() => selectedCorner = corner),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isCurrent ? Colors.redAccent.withValues(alpha: 0.1) : _bgDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: borderColor, width: isCurrent ? 1.5 : 1.0),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isCompleted
                                    ? Icons.check_circle
                                    : (isThisBleeding ? Icons.hourglass_top : Icons.radio_button_checked),
                                color: isCompleted
                                    ? Colors.tealAccent
                                    : (isCurrent ? Colors.redAccent : Colors.white38),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      corner.label,
                                      style: TextStyle(
                                        color: isCurrent ? Colors.white : Colors.white70,
                                        fontSize: 14,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                    Text(
                                      'UDS 0x31 0x01 D0 10 0x0${corner.byte}',
                                      style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isCompleted
                                      ? Colors.tealAccent.withValues(alpha: 0.15)
                                      : (isFailed ? Colors.orangeAccent.withValues(alpha: 0.15) : Colors.white10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  st,
                                  style: TextStyle(
                                    color: isCompleted
                                        ? Colors.tealAccent
                                        : (isFailed ? Colors.orangeAccent : Colors.white60),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 12),

                    // Countdown & Active Status Banner
                    if (countdown > 0) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.timer, color: Colors.redAccent, size: 24),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Return Pump Priming: $countdown s remaining',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Pedal Depression Indicator
                    if (pedalPrompt) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amberAccent, width: 2),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.touch_app, color: Colors.amberAccent, size: 28),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'დააჭირეთ და აუშვით მუხრუჭის სატერფულს 5-ჯერ ნელა სითხის გასადევნად',
                                style: TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Status Message & Progress
                    if (isBleeding) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: bleedProgress,
                          backgroundColor: Colors.white10,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.redAccent),
                          minHeight: 6,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        statusMessage,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      Text(
                        statusMessage,
                        style: const TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: isBleeding ? null : () => runCorner(selectedCorner),
                            icon: const Icon(Icons.play_arrow, size: 18),
                            label: Text('Bleed ${selectedCorner.label}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: isBleeding ? null : () => Navigator.pop(ctx),
                          child: const Text('Close', style: TextStyle(color: Colors.white60)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // ADAPTIVE HEADLIGHT INITIALIZATION HANDLER (FLE_INIT)
  // ===========================================================================
  Future<void> _handleHeadlightInitialization() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Adaptive Headlight & LED Leveling Initialization',
      description: 'Executes Stepper Motor Reference Run and chassis ride height sensor zeroing (FLE_INIT).\n\nVehicle must be parked on flat, level ground with normal unladen weight.',
      accentColor: Colors.cyanAccent,
      extraChecks: [
        'Vehicle parked on level horizontal workshop surface',
        'Headlight lenses clean and unobstructed',
        'Normal unladen vehicle load (no heavy cargo in trunk)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Headlight Leveling Init';
      _actionProgress = 0.10;
      _actionStatusMessage = 'Connecting to Headlight Electronics (FLEL 0x43 / FLER 0x44)...';
    });

    final result = await _service.initializeHeadlights(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // VTG TRANSFER CASE CLUTCH CALIBRATION & HEALTH HANDLERS
  // ===========================================================================
  Future<void> _handleVtgReadClutchHealth() async {
    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Reading VTG Clutch Health';
      _actionProgress = 0.3;
      _actionStatusMessage = 'Querying DID 0xD210 from VTG (0x19)...';
    });

    final data = await _service.readVtgCalibrationData();

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });

      if (data != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _cardDark,
            title: const Row(
              children: [
                Icon(Icons.health_and_safety, color: Colors.deepOrangeAccent),
                SizedBox(width: 10),
                Text('VTG Clutch Health Readout', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• Clutch Degradation Index: ${data.degradationIndex} / 255', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text('• Max Lock Torque: ${data.maxTorqueNm} Nm', style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 6),
                Text(
                  '• Calibration State: ${data.isCalibrated ? "Calibrated (OK)" : "Needs Calibration"}',
                  style: TextStyle(
                    color: data.isCalibrated ? Colors.tealAccent : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close', style: TextStyle(color: Colors.white60)),
              ),
            ],
          ),
        );
      } else {
        _showResultDialog(ServiceRoutineResult(
          success: false,
          title: 'VTG Readout Failed',
          message: 'Could not read DID 0xD210 from VTG (0x19). Ensure vehicle is an xDrive model.',
        ));
      }
    }
  }

  Future<void> _handleVtgClutchCalibration() async {
    final safetyOk = await _showSafetyDialog(
      title: 'xDrive VTG Transfer Case Clutch Calibration',
      description: 'Executes actuator motor learn & multi-plate clutch kiss-point calibration (ABL_DIT_AS2700_VTG).\n\nGear selector must be in PARK or NEUTRAL. Engine must NOT be running.',
      accentColor: Colors.deepOrangeAccent,
      extraChecks: [
        'Transmission selector in PARK or NEUTRAL',
        'Parking brake engaged & wheels chocked',
        'Stable 12V workshop power supply connected',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'VTG Clutch Calibration';
      _actionProgress = 0.15;
      _actionStatusMessage = 'Connecting to Transfer Case (VTG 0x19)...';
    });

    final result = await _service.calibrateVtgClutch(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // SUNROOF & POWER WINDOWS NORMALIZATION HANDLERS
  // ===========================================================================
  Future<void> _handleSunroofNormalization() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Sunroof Anti-Pinch Normalization',
      description: 'Triggers automated glass panel and sunblind travel cycle to learn mechanical end-stops and pinch force characteristics (ABL_DIT_AS6131_SHD).\n\nKeep fingers and foreign objects completely clear of the sunroof aperture!',
      accentColor: Colors.indigoAccent,
      extraChecks: [
        'Sunroof guide rails clear of obstructions and debris',
        'All vehicle doors closed',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Sunroof Normalization';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to Roof Function Center (FZD 0x56)...';
    });

    final result = await _service.normalizeSunroof(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  Future<void> _handlePowerWindowsNormalization() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Power Windows Anti-Pinch Normalization',
      description: 'Cycles all four power windows to re-learn pinch limits and upper/lower physical end-stops (FH_NORM).\n\nEnsure window apertures are completely unobstructed!',
      accentColor: Colors.indigoAccent,
      extraChecks: [
        'All doors closed and window glass clear of obstacles',
        'Terminal 15 active (ignition ON)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Windows Normalization';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to Front Electronic Module (FEM/BDC 0x40)...';
    });

    final result = await _service.normalizePowerWindows(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 4. EMF PARKING BRAKE PAD REPLACEMENT MODE HANDLER
  // ===========================================================================
  Future<void> _handleEmfServiceMode(EmfServiceMode mode) async {
    final isRewind = mode == EmfServiceMode.assemblyOpen;
    final safetyOk = await _showSafetyDialog(
      title: mode.title,
      description: isRewind
          ? 'Electric parking brake calipers will rewind their threaded spindles back into the caliper pistons. Keep fingers away from brake mechanisms!'
          : 'Calipers will wind forward until pads firmly clamp the brake disc, calibrating the clearance air-gap.',
      accentColor: Colors.purpleAccent,
      extraChecks: [
        'Parking brake center console switch is NOT pulled',
        'Vehicle wheel chocks installed on flat surface',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = mode.title;
      _actionProgress = 0.15;
      _actionStatusMessage = 'Communicating with EMF (0x53)...';
    });

    final result = await _service.setEmfServiceMode(
      mode: mode,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 5. ZF TRANSMISSION ADAPTATION HANDLERS
  // ===========================================================================
  Future<void> _handleReadTransmissionAdaptations() async {
    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Reading ZF Clutch Adaptations';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Connecting to EGS (0x18)...';
    });

    final list = await _service.readTransmissionAdaptations(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });

      _showClutchAdaptationsSheet(list);
    }
  }

  void _showClutchAdaptationsSheet(List<ClutchAdaptation> clutches) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_suggest, color: Colors.blueAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'ZF 6HP / 8HP Clutch Adaptations',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Clutch fill pressure offsets and rapid filling times calculated dynamically by EGS mechatronics to compensate for plate wear.',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 16),
              ...clutches.map((clutch) {
                final isCrit = clutch.isCritical;
                final isWarn = clutch.isWarning;
                final tagColor = isCrit ? Colors.redAccent : (isWarn ? Colors.amberAccent : Colors.greenAccent);

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _bgDark,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  clutch.clutchName,
                                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: tagColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    clutch.statusAssessment,
                                    style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'DID 0x${clutch.did.toRadixString(16).toUpperCase()}',
                              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${clutch.fillPressureMbar >= 0 ? "+" : ""}${clutch.fillPressureMbar} mbar',
                            style: TextStyle(
                              color: tagColor,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          Text(
                            '${clutch.rapidFillTimeMs >= 0 ? "+" : ""}${clutch.rapidFillTimeMs} ms',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                      ),
                      child: const Text('Close'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _handleResetTransmissionAdaptations();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Reset Adaptations', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleResetTransmissionAdaptations() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Reset Transmission Adaptations',
      description: 'WARNING: Only reset adaptations after a transmission oil change, mechatronics valve-body rebuild, or clutch pack replacement.\n\nA strict 30-minute adaptive drive cycle is required immediately following the reset.',
      accentColor: Colors.blueAccent,
      extraChecks: [
        'Transmission fluid level verified at 40°C - 50°C',
        'Selector lever in Park (P)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Resetting ZF Adaptations';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending UDS Routine 0x31 0x01 0F 01...';
    });

    final result = await _service.resetTransmissionAdaptations(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 6. VALVETRONIC & THROTTLE RE-LEARN HANDLER
  // ===========================================================================
  Future<void> _handleValvetronicRelearn() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Valvetronic & Throttle Stop Re-learn',
      description: 'The DME will power the eccentric shaft stepper motor to drive the Valvetronic intermediate levers to both physical end stops (0.25mm minimum lift to 9.9mm maximum lift). It will also cycle the throttle valve stops.',
      accentColor: Colors.tealAccent,
      extraChecks: [
        'Engine cold or warm (not overheating)',
        'Battery charger connected (high current draw during motor stall test)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Valvetronic & Throttle Re-learn';
      _actionProgress = 0.15;
      _actionStatusMessage = 'Connecting to DME (0x12)...';
    });

    final result = await _service.relearnValvetronicAndThrottle(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 7. DPF REGENERATION & ASH MASS RESET HANDLER (res_dpfRegen)
  // ===========================================================================
  Future<void> _handleDpfManagement() async {
    DpfStatusData? dpfData;
    bool isReading = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (isReading && dpfData == null) {
              Future.microtask(() async {
                final data = await _service.readDpfStatus();
                if (ctx.mounted) {
                  setSheetState(() {
                    dpfData = data;
                    isReading = false;
                  });
                }
              });
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.filter_alt_outlined, color: Colors.orangeAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Diesel Particulate Filter (DPF)',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'UDS DID 0xD017 & Routine 0xD015 / 0xD016',
                              style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setSheetState(() {
                            isReading = true;
                            dpfData = null;
                          });
                        },
                        icon: const Icon(Icons.refresh, color: Colors.orangeAccent),
                        tooltip: 'Re-read DPF Status',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isReading) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(color: Colors.orangeAccent),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'Reading DPF status (DID 0xD017) from DDE (0x12)...',
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                      ),
                    ),
                  ] else if (dpfData != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Calculated Soot Mass:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Row(
                                children: [
                                  Text(
                                    '${dpfData!.sootMassGrams.toStringAsFixed(1)} g',
                                    style: TextStyle(
                                      color: dpfData!.isSootCritical ? Colors.redAccent : Colors.orangeAccent,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (dpfData!.isSootCritical ? Colors.redAccent : Colors.orangeAccent).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      dpfData!.sootAssessment,
                                      style: TextStyle(
                                        color: dpfData!.isSootCritical ? Colors.redAccent : Colors.orangeAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Calculated Ash Mass:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(
                                '${dpfData!.ashMassGrams.toStringAsFixed(1)} g',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Exhaust Gas Temperature:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(
                                '${dpfData!.exhaustTempC.toStringAsFixed(0)} °C',
                                style: const TextStyle(
                                  color: Colors.amberAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white10, height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Regeneration Status:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(
                                dpfData!.regenStatusText,
                                style: TextStyle(
                                  color: dpfData!.isRegenActive ? Colors.greenAccent : (dpfData!.isRegenRequested ? Colors.cyanAccent : Colors.white60),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Could not retrieve live DID 0xD017 from DDE. Ensure ignition is ON.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _executeDpfAshMassReset();
                          },
                          icon: const Icon(Icons.restart_alt, size: 16),
                          label: const Text('Reset Ash (New DPF)'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.orangeAccent,
                            side: const BorderSide(color: Colors.orangeAccent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _executeDpfRegenRequest();
                          },
                          icon: const Icon(Icons.play_arrow, size: 16),
                          label: const Text('Request Regen'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orangeAccent,
                            foregroundColor: Colors.black,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeDpfRegenRequest() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Request DPF Service Regeneration',
      description: 'DDE will schedule a forced regeneration (Routine 0x31 0x01 D0 15). Immediately following this request, take the vehicle on a continuous 25-35 minute highway drive.',
      accentColor: Colors.orangeAccent,
      extraChecks: [
        'Fuel tank has at least 10 liters (Regen aborted if low fuel)',
        'Engine coolant temperature reaches operating temp (> 75°C)',
        'Continuous drive > 60 km/h (40 mph) at 2000-2500 RPM planned',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Requesting DPF Service Regen';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 D0 15 to DDE (0x12)...';
    });

    final result = await _service.requestDpfRegeneration(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  Future<void> _executeDpfAshMassReset() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Reset DPF Ash & Soot Mass',
      description: 'WARNING: Only execute this routine after installing a brand-new or professionally cleaned particulate filter. It zeroes out cumulative ash mass calculations in DDE flash.',
      accentColor: Colors.orangeAccent,
      extraChecks: [
        'New / cleaned diesel particulate filter installed',
        'Exhaust backpressure / differential sensor tubes verified clean',
        'Ignition ON, Engine OFF',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Resetting DPF Ash Mass';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 D0 16 to DDE (0x12)...';
    });

    final result = await _service.resetDpfAshMass(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 8. STEERING ANGLE SENSOR (SZL / LWS) ZERO-POINT CALIBRATION HANDLER
  // ===========================================================================
  Future<void> _handleSteeringAngleCalibration() async {
    SteeringAngleData? angleData;
    bool isReading = true;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            if (isReading && angleData == null) {
              Future.microtask(() async {
                final data = await _service.readSteeringAngle();
                if (ctx.mounted) {
                  setSheetState(() {
                    angleData = data;
                    isReading = false;
                  });
                }
              });
            }

            final isPass = angleData?.isZeroCalibrated ?? false;
            final badgeColor = isPass ? Colors.lightGreenAccent : Colors.amberAccent;

            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.lightGreenAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.navigation_outlined, color: Colors.lightGreenAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Steering Angle Sensor (SZL / LWS)',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'UDS DID 0x4002 & Routine 0x31 0x01 A0 10',
                              style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setSheetState(() {
                            isReading = true;
                            angleData = null;
                          });
                        },
                        icon: const Icon(Icons.refresh, color: Colors.lightGreenAccent),
                        tooltip: 'Re-read Angle DID 0x4002',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (isReading) ...[
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24.0),
                        child: CircularProgressIndicator(color: Colors.lightGreenAccent),
                      ),
                    ),
                    const Center(
                      child: Text(
                        'Reading steering angle (DID 0x4002) from DSC/EPS...',
                        style: TextStyle(color: Colors.lightGreenAccent, fontSize: 12),
                      ),
                    ),
                  ] else if (angleData != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isPass ? Icons.check_circle : Icons.warning_amber_rounded,
                            color: badgeColor,
                            size: 36,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      angleData!.formattedAngle,
                                      style: TextStyle(
                                        color: badgeColor,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        angleData!.statusAssessment,
                                        style: TextStyle(
                                          color: badgeColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Target: 0.0° ± 0.5° tolerance (Active ECU: 0x${angleData!.targetEcu.toRadixString(16).toUpperCase()})',
                                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'Ensure steering wheel is centered and front wheels are aligned straight ahead before executing optical zero-point calibration.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _executeSteeringAngleCalibration();
                    },
                    icon: const Icon(Icons.tune, color: Colors.black, size: 18),
                    label: const Text('Calibrate Zero-Point (±0.5°)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightGreenAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 46),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _executeSteeringAngleCalibration() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Steering Angle Sensor Calibration',
      description: 'DSC & EPS optical zero-point will be calibrated to current wheel position via Routine 0x31 0x01 A0 10.',
      accentColor: Colors.lightGreenAccent,
      extraChecks: [
        'Steering wheel mechanically leveled straight',
        'Front wheels pointing exactly straight forward',
        'Vehicle parked on level ground',
        'Ignition ON (Terminal 15), Engine OFF',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Calibrating SZL / LWS Zero-Point';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 A0 10 to DSC/EPS...';
    });

    final result = await _service.calibrateSteeringAngleSensor(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 9. FRM SHORT-CIRCUIT COUNTER RESET HANDLER (res_ShortsCir)
  // ===========================================================================
  Future<void> _handleFrmShortCircuitReset() async {
    FrmLightChannel selectedChannel = FrmLightChannel.allChannels;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.yellowAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.electric_bolt, color: Colors.yellowAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FRM Short-Circuit Counter Reset',
                              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'FRM _reset_kurzschluss_sperre (Routine 0xB001)',
                              style: TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'When a short circuit occurs in a lighting circuit (e.g. blown bulb, ballast short), the Footwell Module (FRM) permanently locks power to that channel after 50 trips. Select the channel to unlock:',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 280),
                    decoration: BoxDecoration(
                      color: _bgDark,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ListView(
                      shrinkWrap: true,
                      children: FrmLightChannel.values.map((channel) {
                        final isSelected = selectedChannel == channel;
                        return InkWell(
                          onTap: () => setSheetState(() => selectedChannel = channel),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.yellowAccent.withValues(alpha: 0.1) : Colors.transparent,
                              border: Border(
                                bottom: channel != FrmLightChannel.values.last
                                    ? const BorderSide(color: Colors.white10)
                                    : BorderSide.none,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                  color: isSelected ? Colors.yellowAccent : Colors.white38,
                                  size: 18,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    channel.label,
                                    style: TextStyle(
                                      color: isSelected ? Colors.white : Colors.white70,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                Text(
                                  '0x${channel.channelByte.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.lock_open, color: Colors.black, size: 18),
                    label: Text(
                      'Unlock ${selectedChannel.label}',
                      style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.yellowAccent,
                      minimumSize: const Size(double.infinity, 46),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true) return;

    final safetyOk = await _showSafetyDialog(
      title: 'Reset FRM Short-Circuit Lock',
      description: 'FRM short-circuit counter for ${selectedChannel.label} will be zeroed out in EEPROM. Ensure the physical wiring short circuit or defective bulb has been repaired.',
      accentColor: Colors.yellowAccent,
      extraChecks: [
        'Defective bulb / ballast replaced or harness repaired',
        'Ignition ON (Terminal 15 active)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Resetting FRM Latch (${selectedChannel.label})';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 B0 01 to FRM (0x40)...';
    });

    final result = await _service.resetFrmShortCircuitCounter(
      channel: selectedChannel,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 10. FUEL PUMP PRIMING ROUTINE HANDLER (res_PrimeFuel)
  // ===========================================================================
  Future<void> _handleFuelPumpPriming() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Low Pressure Fuel Pump Priming',
      description: 'Electric fuel pump (EKP 0x17 / DME 0x12) will run continuously at 100% duty cycle for 30 seconds to purge trapped air from fuel lines, high pressure pump, and fuel rail.\n\nRequired after replacing the fuel filter, LPFP, or HPFP.',
      accentColor: Colors.lightBlueAccent,
      extraChecks: [
        'Fuel filter & lines securely fastened with no leaks',
        'Fuel tank has at least 10 liters of fuel',
        'Engine OFF (Do NOT crank starter while priming)',
        'Workshop battery charger connected (high pump current draw)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Fuel Pump Priming (100% Duty Cycle)';
      _actionProgress = 0.05;
      _actionStatusMessage = 'Initializing EKP / DME fuel aggregate...';
    });

    await for (final event in _service.executeFuelPumpPrimingSequence(durationSeconds: 30)) {
      if (!mounted) break;

      setState(() {
        _actionProgress = (event['progress'] as num?)?.toDouble() ?? 0.0;
        _actionStatusMessage = (event['message'] as String?) ?? '';
      });

      if (event['step'] == 'COMPLETE' || event['step'] == 'FAILED' || event['step'] == 'EXCEPTION') {
        final success = event['success'] == true;
        _showResultDialog(ServiceRoutineResult(
          success: success,
          title: success ? 'Fuel Priming Complete' : 'Priming Aborted',
          message: event['message'] ?? '',
        ));
        break;
      }
    }

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
    }
  }

  // ===========================================================================
  // 11. TRANSPORT MODE TOGGLE HANDLER (res_transPort)
  // ===========================================================================
  Future<void> _handleTransportMode() async {
    final action = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.pinkAccent),
          ),
          title: const Row(
            children: [
              Icon(Icons.flight_takeoff, color: Colors.pinkAccent, size: 24),
              SizedBox(width: 10),
              Text('Transport Mode Toggle', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: const Text(
            'BMW Transport Mode powers down climate blower fans, infotainment, ambient lighting, and comfort access to prevent battery depletion during transit.\n\nChoose configuration:',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.pinkAccent,
                side: const BorderSide(color: Colors.pinkAccent),
              ),
              child: const Text('Activate (Storage)'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pinkAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Deactivate (Normal)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (action == null) return;

    final deactivate = action;
    final safetyOk = await _showSafetyDialog(
      title: deactivate ? 'Deactivate Transport Mode' : 'Activate Transport Mode',
      description: deactivate
          ? 'Gateway and BDC will execute UDS 0x28 0x00 to wake all body convenience consumers and extinguish transport mode instrument cluster warnings.'
          : 'Vehicle will be placed into low-power storage mode (UDS 0x28 0x01). Infotainment and blower fans will be disabled.',
      accentColor: Colors.pinkAccent,
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = deactivate ? 'Deactivating Transport Mode' : 'Activating Transport Mode';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending UDS CommunicationControl (0x28) to Gateways...';
    });

    final result = await _service.setTransportMode(
      deactivate: deactivate,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 12. VTG TRANSFER CASE FLUID RESET HANDLER (res_vgsgReset)
  // ===========================================================================
  Future<void> _handleVtgFluidReset() async {
    final safetyOk = await _showSafetyDialog(
      title: 'VTG Transfer Case Fluid Reset',
      description: 'Resets the oil deterioration integrator counter and clutch wear model in the VTG ECU (0x19) via Routine 0x31 0x01 A1 05. Clears fault code 54C6 ("VTG: Oil wear").\n\nOnly perform after changing transfer case fluid (BMW DTF-1 / Shell TF0870).',
      accentColor: Colors.deepOrangeAccent,
      extraChecks: [
        'Transfer case oil drained and refilled with fresh DTF-1 / TF0870',
        'Oil level verified at fill plug bottom edge',
        'Transmission gear selector in Park (P)',
        'Ignition ON, Engine OFF',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Resetting VTG Fluid Integrator';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 A1 05 to VTG (0x19)...';
    });

    final result = await _service.resetVtgTransferCaseFluid(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 13. CONDITION BASED SERVICE (CBS) HANDLERS
  // ===========================================================================
  Future<void> _loadCbsStatus() async {
    if (_isLoadingCbs) return;
    setState(() => _isLoadingCbs = true);
    final items = await _service.readCbsStatus();
    if (mounted) {
      setState(() {
        _cbsItems = items;
        _isLoadingCbs = false;
      });
    }
  }

  Future<void> _handleResetCbsItem(CbsItemStatus item) async {
    final safetyOk = await _showSafetyDialog(
      title: 'Reset ${item.type.label} (CBS)',
      description: 'Executes UDS Routine 0x31 0x01 D0 0x${item.type.serviceIdByte.toRadixString(16).padLeft(2, '0').toUpperCase()} on ${item.type == CbsServiceType.engineOil || item.type == CbsServiceType.sparkPlugs ? "DME/KOMBI" : "KOMBI"}.\n\nService interval will be reset to factory baseline (${item.type.nominalIntervalKm > 0 ? "${item.type.nominalIntervalKm} km" : ""}${item.type.nominalIntervalMonths > 0 ? " / ${item.type.nominalIntervalMonths} months" : ""}) and wear life restored to 100%.',
      accentColor: Colors.tealAccent,
      extraChecks: [
        'Component physically replaced or serviced according to BMW specifications',
        if (item.type == CbsServiceType.frontBrakes || item.type == CbsServiceType.rearBrakes)
          'New brake pad wear sensor installed and plugged into harness',
        'Vehicle date and time configured correctly in iDrive',
        'Ignition Terminal 15 ON, Engine completely OFF',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Resetting ${item.type.label} (CBS)';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending UDS Routine 0x31 0x01 D0 0x${item.type.serviceIdByte.toRadixString(16).padLeft(2, '0').toUpperCase()}...';
    });

    final result = await _service.resetCbsItem(
      item.type,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _loadCbsStatus();
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 14. THROTTLE END STOPS RE-LEARN HANDLER (res_throtCal)
  // ===========================================================================
  Future<void> _handleThrottleCalibration() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Throttle End Stops Learn (res_throtCal)',
      description: 'DME will actuate the electronic throttle valve to lower mechanical stop (0%), emergency limp-home return spring position (5-7%), and full wide-open throttle stop (100%) via Routine 0x31 0x01 10 01.',
      accentColor: Colors.lightGreenAccent,
      extraChecks: [
        'Accelerator pedal NOT touched or depressed',
        'Ignition ON (Terminal 15), Engine completely OFF',
        'Clean battery voltage >= 12.0V',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Learning Throttle End Stops';
      _actionProgress = 0.15;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 10 01 to DME (0x12)...';
    });

    final result = await _service.calibrateThrottle(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 15. IDLE SPEED (RPM) ADJUSTMENT HANDLERS (res_idleAdj)
  // ===========================================================================
  Future<void> _loadIdleRpm() async {
    final offset = await _service.readIdleRpmOffset(withAc: _idleWithAc);
    if (mounted && offset != null) {
      setState(() => _selectedIdleOffset = offset);
    }
  }

  Future<void> _handleApplyIdleRpm() async {
    final conditionText = _idleWithAc ? 'A/C Active (Air Conditioning ON)' : 'Standard Idle (A/C OFF)';
    final safetyOk = await _showSafetyDialog(
      title: 'Set Idle Speed Offset (${_selectedIdleOffset >= 0 ? "+" : ""}$_selectedIdleOffset RPM)',
      description: 'DME will commit the target idle offset to DID 0xD115 and execute Routine 0x31 0x01 10 08 for $conditionText.',
      accentColor: Colors.amberAccent,
      extraChecks: [
        'Ignition ON (Terminal 15 active)',
        'Vehicle parked with handbrake engaged',
        'Target offset within factory range (-150 to +250 RPM)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Adjusting Idle Speed (${_selectedIdleOffset >= 0 ? "+" : ""}$_selectedIdleOffset RPM)';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 10 08 to DME...';
    });

    final result = await _service.adjustIdleRpm(
      rpmOffset: _selectedIdleOffset,
      withAc: _idleWithAc,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 16. ELV STEERING LOCK RESET HANDLER (resetELV / res_lockElv)
  // ===========================================================================
  Future<void> _handleResetElv() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Reset ELV Steering Lock (res_lockElv)',
      description: 'Zeroes out the internal fault counter in CAS/BDC (0x40) EEPROM via Routine 0x31 0x01 D1 00, unlocks the steering column, and extinguishes the yellow/red steering wheel warning symbol.',
      accentColor: Colors.cyanAccent,
      extraChecks: [
        'Steering wheel centered and not mechanically bound against curb',
        'Valid key fob inserted in slot / Comfort Access detected',
        'Ignition Terminal 15 active',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Resetting ELV Steering Lock';
      _actionProgress = 0.2;
      _actionStatusMessage = 'Sending Routine 0x31 0x01 D1 00 to CAS (0x40)...';
    });

    final result = await _service.resetElvSteeringLock(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 17. CAS-DME (EWS) ROLLING CODE SYNCHRONIZATION HANDLER (res_casDmeSync)
  // ===========================================================================
  Future<void> _handleCasDmeSync() async {
    final safetyOk = await _showSafetyDialog(
      title: 'CAS-DME (EWS) Rolling Code Sync (res_casDmeSync)',
      description: 'Re-aligns immobilizer rolling codes between CAS (0x40) and DME (0x12) via Routines 0x2000 / 0x2001. Clears 2F44/4A63 tampering lockout to resolve "Crank, No Start".',
      accentColor: Colors.greenAccent,
      extraChecks: [
        'Key fob is verified original to vehicle',
        'Battery voltage stable (clean charger recommended)',
        'Ignition ON (Terminal 15), Engine OFF',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Syncing CAS-DME EWS Codes';
      _actionProgress = 0.15;
      _actionStatusMessage = 'Executing EWS synchronization sequence...';
    });

    final result = await _service.syncCasDmeRollingCode(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 18. ACTIVE SOUND DESIGN (ASD) CABIN SOUND HANDLERS (activity_asd.xml)
  // ===========================================================================
  Future<void> _loadAsdState() async {
    setState(() => _isLoadingAsd = true);
    final state = await _service.readAsdState();
    if (mounted) {
      setState(() {
        _asdState = state;
        _isLoadingAsd = false;
      });
    }
  }

  Future<void> _handleSetAsdState(AsdState targetState) async {
    final safetyOk = await _showSafetyDialog(
      title: 'Active Sound Design (ASD) მართვა',
      description: 'სალონის დინამიკებში ხელოვნური ძრავის აკუსტიკის შეცვლა რეჟიმზე: "${targetState.label}". FIX AI ჩაწერს DID 0x3000 ASD მოდულზე (0x20) ან სათავო მოწყობილობაზე (HU_NBT 0x63).',
      accentColor: Colors.deepPurpleAccent,
      extraChecks: [
        'Ignition ON (Terminal 15 active)',
        'Audio system powered on',
        'Stable battery voltage >= 12.0V',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Setting ASD: ${targetState.label}';
      _actionProgress = 0.25;
      _actionStatusMessage = 'Sending UDS WriteDataByIdentifier 0x3000...';
    });

    final result = await _service.setAsdState(
      targetState,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
        if (result.success) {
          _asdState = targetState;
        }
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 19. EXHAUST FLAP 3-WAY CONTROL HANDLERS (activity_exhaust_flap.xml)
  // ===========================================================================
  Future<void> _loadExhaustFlapState() async {
    setState(() => _isLoadingExhaustFlap = true);
    final mode = await _service.readExhaustFlapState();
    if (mounted) {
      setState(() {
        if (mode != null) _exhaustFlapMode = mode;
        _isLoadingExhaustFlap = false;
      });
    }
  }

  Future<void> _handleSetExhaustFlapMode(ExhaustFlapMode targetMode) async {
    final safetyOk = await _showSafetyDialog(
      title: 'Exhaust Flap (გამონაბოლქვის ფლაპები) - ${targetMode.label}',
      description: 'DME (0x12) გაგზავნის UDS 0x2F IO Control ბრძანებას მაყუჩის ელექტრონული ფლაპის აქტუატორზე (DID 0x310A).',
      accentColor: Colors.redAccent,
      extraChecks: [
        'Ignition ON (Terminal 15 active)',
        'Exhaust system cooled or hands clear of tailpipe flap mechanism',
        'Vehicle stationary with parking brake engaged',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Setting Exhaust Flap: ${targetMode.label}';
      _actionProgress = 0.25;
      _actionStatusMessage = 'Executing UDS 0x2F IO Control on DME (0x12)...';
    });

    final result = await _service.setExhaustFlapMode(
      targetMode,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
        if (result.success) {
          _exhaustFlapMode = targetMode;
        }
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // 20. ADVANCED MECHANICAL ADAPTATIONS & CALIBRATION HANDLERS (ProTool DEX)
  // ===========================================================================

  /// Valvetronic (VVT) Limit Positions Learn (res_vvtCal)
  Future<void> _handleValvetronicCalibration() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Valvetronic (VVT) Limit Positions Learn (res_vvtCal)',
      description: 'DME (0x12) გაუშვებს ექსცენტრიკული ლილვის სერვომოტორს მექანიკურ მინიმალურ (0.25 მმ) და მაქსიმალურ (9.9 მმ) შემზღუდველ პოზიციებზე UDS რუტინით 0x31 0x01 10 05 (N20, N55, S55, B58 ძრავებისთვის).',
      accentColor: Colors.tealAccent,
      extraChecks: [
        'Engine cold or warm (not overheating)',
        'Ignition ON (Terminal 15 active), Engine completely OFF',
        'Clean workshop battery charger connected (high motor stall draw)',
        'Eccentric shaft sensor properly connected',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Valvetronic Limit Positions Learn';
      _actionProgress = 0.15;
      _actionStatusMessage = 'Checking battery voltage and connecting to DME (0x12)...';
    });

    final result = await _service.valvetronicCalibration(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  /// Master Engine Adaptations Reset (res_engineAdapt)
  Future<void> _handleResetEngineAdaptations() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Master Engine Adaptations Reset (res_engineAdapt)',
      description: 'DME (0x12) გაანულებს ძრავის მართვის ყველა ძირითად ადაპტაციურ ცხრილს NVRAM-ში: Lambda ნარევის ადაპტაციები (STFT/LTFT), დროსელის მოდელი, ოქტანობის კორექცია და VANOS-ის ადაპტაციები (Routine 0x31 0x01 10 00).',
      accentColor: Colors.orangeAccent,
      extraChecks: [
        'Ignition ON (Terminal 15 active)',
        'Engine completely OFF (Do not start during reset)',
        'Stable battery voltage (minimum 11.8V)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Master Engine Adaptations Reset';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to DME (0x12)...';
    });

    final result = await _service.resetEngineAdaptations(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  /// Rain / Light Sensor Windshield Initialization (res_RLSInit)
  Future<void> _handleRainLightSensorInit() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Rain / Light Sensor Windshield Init (res_RLSInit)',
      description: 'საქარე მინის შეცვლის შემდეგ RLS / FZD (0x56) და FEM (0x40) მოდულში განულდება და ხელახლა დაკალიბრდება მინის ოპტიკური გარდატეხის კოეფიციენტი Routine 0x31 0x01 A0 02-ით.',
      accentColor: Colors.cyanAccent,
      extraChecks: [
        'Ignition ON (Terminal 15 active)',
        'Windshield glass completely clean and dry in front of sensor mirror area',
        'Avoid intense direct sunlight hitting the sensor during calibration',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Rain / Light Sensor Initialization';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to RLS / FZD (0x56)...';
    });

    final result = await _service.rainLightSensorInit(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  /// Tire Pressure Monitor (TPMS / RDC / RPA) Reset (res_TpmsReset)
  Future<void> _handleTpmsReset() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Tire Pressure Monitor (TPMS / RDC) Reset (res_TpmsReset)',
      description: 'DSC (0x29) მოდულში გაეშვება საბურავების წნევის დაკალიბრებისა და სასწავლო მოძრაობის ინიციალიზაციის UDS რუტინა (0x31 0x01 D0 30).',
      accentColor: Colors.amberAccent,
      extraChecks: [
        'All 4 tire cold pressures adjusted according to B-pillar spec sticker',
        'Vehicle parked on level ground with handbrake set',
        'Prepare to drive at > 30 km/h after reset to finish learning cycle',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'TPMS / RDC Calibration Reset';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to DSC (0x29)...';
    });

    final result = await _service.tpmsReset(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  /// Air Suspension (EHC / Luftfederung) Ride Height Calibration (res_rideHeight)
  Future<void> _handleAirSuspensionCalibration() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Air Suspension Ride Height Calibration (res_rideHeight)',
      description: 'უკანა პნევმო დაკიდების სიმაღლის კალიბრაცია EHC (0x6E) / VDC (0x3F) მოდულში Routine 0x31 0x01 41 01-ით (F11, F15, G05, G31 მოდელებისთვის).\n\nარჩეული ოფსეტები:\n• მარცხენა: $_airSuspensionLeftMm მმ\n• მარჯვენა: $_airSuspensionRightMm მმ',
      accentColor: Colors.lightGreenAccent,
      extraChecks: [
        'Vehicle parked on level ground with wheels straight',
        'All vehicle doors, tailgate, and hood closed',
        'Handbrake released, transmission in Park (P)',
        'Suspension compressor free of pneumatic leak faults',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Air Suspension Ride Height Calibration';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to EHC (0x6E)...';
    });

    final result = await _service.airSuspensionRideHeightCalibration(
      leftOffsetMm: _airSuspensionLeftMm,
      rightOffsetMm: _airSuspensionRightMm,
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  /// Cylinder Running Smoothness Measurement (res_CylEqu - Zylindergleichstellung)
  Future<void> _handleCylinderSmoothness() async {
    setState(() => _isLoadingSmoothness = true);
    final data = await _service.readCylinderSmoothness();
    if (mounted) {
      setState(() {
        _lastSmoothnessData = data;
        _isLoadingSmoothness = false;
      });

      if (data == null || data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ცილინდრების რხევის წაკითხვა ვერ მოხერხდა. დარწმუნდით, რომ ძრავი მუშაობს (Idling) და DME ჩართულია.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      _showCylinderSmoothnessSheet(data);
    }
  }

  void _showCylinderSmoothnessSheet(List<CylinderSmoothnessData> initialData) {
    var cylinders = initialData;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.equalizer, color: Colors.cyanAccent, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cylinder Smoothness (Zylindergleichstellung)',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'DME 0x12 • DID 0xD120 (Flywheel Δ 1/min²)',
                              style: TextStyle(color: Colors.cyanAccent, fontSize: 11, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.white70),
                        tooltip: 'Measure Again',
                        onPressed: () async {
                          final freshData = await _service.readCylinderSmoothness();
                          if (freshData != null) {
                            setSheetState(() => cylinders = freshData);
                            if (mounted) setState(() => _lastSmoothnessData = freshData);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Flywheel crankshaft angular acceleration fluctuations measured in 1/min² (scale 0.1). Factory specification: ±2.0 1/min² during warm idle.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  ...cylinders.map((cyl) {
                    final absVal = cyl.roughnessRpm2.abs();
                    final isCrit = cyl.isCritical;
                    final isWarn = cyl.isElevated;
                    final tagColor = isCrit ? Colors.redAccent : (isWarn ? Colors.amberAccent : Colors.greenAccent);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bgDark,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: tagColor.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '#${cyl.cylinder}',
                              style: TextStyle(color: tagColor, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      'Cylinder ${cyl.cylinder}',
                                      style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: tagColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        cyl.statusAssessment,
                                        style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2),
                                  child: LinearProgressIndicator(
                                    value: (absVal / 6.0).clamp(0.0, 1.0),
                                    backgroundColor: Colors.white12,
                                    valueColor: AlwaysStoppedAnimation<Color>(tagColor),
                                    minHeight: 4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            cyl.formattedRoughness,
                            style: TextStyle(
                              color: tagColor,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Active Front Steering (AFS) Center Calibration (res_CalAFS)
  Future<void> _handleActiveFrontSteeringCalibration() async {
    final safetyOk = await _showSafetyDialog(
      title: 'Active Front Steering Calibration (res_CalAFS)',
      description: 'AFS / AL (0x1B) მოდულში დაკალიბრდება საჭის აქტიური მექანიზმის პლანეტარული რედუქტორის ნულოვანი ცენტრი Routine 0x31 0x01 A0 12-ით.',
      accentColor: Colors.blueAccent,
      extraChecks: [
        'Steering wheel positioned dead straight ahead',
        'Front wheels aligned straight on level workshop ground',
        'Ignition ON (Terminal 15 active)',
        'Battery voltage stable (> 11.8V)',
      ],
    );

    if (!safetyOk) return;

    setState(() {
      _isActionRunning = true;
      _activeActionName = 'Active Front Steering (AFS) Calibration';
      _actionProgress = 0.20;
      _actionStatusMessage = 'Connecting to AFS (0x1B)...';
    });

    final result = await _service.activeFrontSteeringCalibration(
      onProgress: (status, progress) {
        if (mounted) {
          setState(() {
            _actionStatusMessage = status;
            _actionProgress = progress;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isActionRunning = false;
        _activeActionName = '';
      });
      _showResultDialog(result);
    }
  }

  // ===========================================================================
  // UI BUILD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _cardDark,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BMW Workshop Routines',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  _isConnected ? 'ENET/HSFZ Online' : 'Vehicle Disconnected',
                  style: TextStyle(
                    color: _isConnected ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 11,
                  ),
                ),
                if (_liveVoltage != null)
                  Text(
                    '${_liveVoltage!.toStringAsFixed(1)}V',
                    style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                if (_odometerKm != null)
                  Text(
                    '$_odometerKm km',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_ethernet, color: Colors.cyanAccent),
            tooltip: 'Adapter Setup',
            onPressed: () async {
              final result = await showDialog<Map<String, dynamic>>(
                context: context,
                builder: (c) => const AdvancedConnectionDialog(),
              );
              if (result != null && result['status'] == 'connected') {
                _checkInitialConnection();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Refresh Status',
            onPressed: _refreshVehicleState,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Active Action Neon Progress Bar
            if (_isActionRunning)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: _cardDark,
                  border: Border(bottom: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.4))),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _activeActionName,
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '${(_actionProgress * 100).toInt()}%',
                          style: const TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _actionProgress > 0 ? _actionProgress : null,
                      backgroundColor: Colors.white10,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                      minHeight: 4,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _actionStatusMessage,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),

            // Top Status & Safety Banner
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cardDark,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _cardBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.amberAccent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.info_outline, color: Colors.amberAccent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dealer-Level ISO 14229 Diagnostic Routines',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Factory ISO 14229 diagnostic routines. Executes directly against vehicle ECUs via ENET.',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Service Routines Grid
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  // CBS Section: Condition Based Service
                  _buildCbsSection(),

                  // Throttle & Idle Section: Throttle Learn & Idle RPM Adjustment
                  _buildThrottleAndIdleSection(),

                  // Security & Immobilizer Section: ELV Steering Lock Reset & CAS-DME Sync
                  _buildElvAndEwsSection(),

                  // Sound & Power Section: Active Sound Design (ASD) & Exhaust Flap Control
                  _buildSoundAndPowerSection(),

                  // Master Section: მოწინავე მექანიკური ადაპტაციები & კალიბრაცია (ProTool DEX)
                  _buildMasterMechanicalAndCalibrationSection(),

                  // Routine 1: Battery Registration
                  _buildRoutineCard(
                    title: 'Battery Registration & Coding',
                    subtitle: 'Reset DME battery aging counter & code CAS/FEM/BDC KLASSE_BATTERIE for new AGM, Lead-Acid, or LiFePO4 (M3/M4).',
                    ecuBadge: 'DME 0x12 / CAS 0x40',
                    routineCode: 'UDS 0x31 0x01 A0 10',
                    accentColor: Colors.cyanAccent,
                    icon: Icons.battery_charging_full,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleBatteryRegistration,
                        icon: const Icon(Icons.electric_meter, size: 16),
                        label: const Text('Register New Battery'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _isActionRunning ? null : _showBatteryHistoryModal,
                        icon: const Icon(Icons.history, size: 16),
                        label: const Text('რეგისტრაციის ისტორია'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.cyanAccent,
                          side: BorderSide(color: Colors.cyanAccent.withValues(alpha: 0.5)),
                        ),
                      ),
                    ],
                  ),

                  // Routine 2: Injector Flow Compensation
                  _buildRoutineCard(
                    title: 'Injector Flow Compensation',
                    subtitle: 'Read and calibrate individual 6-digit flow and energy tolerance codes for cylinders 1 through 6.',
                    ecuBadge: 'DME 0x12',
                    routineCode: 'UDS 0x22 / 0x2E DIDs 0xD101..6',
                    accentColor: Colors.amberAccent,
                    icon: Icons.tune,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleInjectorCalibration,
                        icon: const Icon(Icons.format_list_numbered, size: 16),
                        label: const Text('Manage Injectors'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 3: ABS / DSC Hydraulic Brake Bleeding
                  _buildRoutineCard(
                    title: 'ABS / DSC Hydraulic Brake Bleeding',
                    subtitle: 'Autonomously pulses the DSC secondary return pump and cycles solenoid valves to purge air.',
                    ecuBadge: 'DSC 0x29',
                    routineCode: 'UDS 0x31 0x01 03 22',
                    accentColor: Colors.redAccent,
                    icon: Icons.invert_colors,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleDscBrakeBleeding,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Start Hydraulic Bleed'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  // Routine 4: Electronic Parking Brake (EMF)
                  _buildRoutineCard(
                    title: 'EMF Parking Brake Pad Replacement',
                    subtitle: 'Winds rear caliper motorized spindles into service mode for pad fitting, then calibrates clearance.',
                    ecuBadge: 'EMF 0x53',
                    routineCode: 'UDS Routine 0xE001 / 0xE002',
                    accentColor: Colors.purpleAccent,
                    icon: Icons.settings_backup_restore,
                    buttons: [
                      OutlinedButton.icon(
                        onPressed: _isActionRunning ? null : () => _handleEmfServiceMode(EmfServiceMode.assemblyOpen),
                        icon: const Icon(Icons.open_in_full, size: 14),
                        label: const Text('Rewind Calipers'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.purpleAccent,
                          side: const BorderSide(color: Colors.purpleAccent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : () => _handleEmfServiceMode(EmfServiceMode.assemblyClose),
                        icon: const Icon(Icons.check_circle_outline, size: 14),
                        label: const Text('Calibrate Clearance'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  // Routine 5: Transmission Adaptations
                  _buildRoutineCard(
                    title: 'ZF Transmission Adaptations',
                    subtitle: 'Read rapid fill times (ms) & pressures (mbar) for clutches A, B, C, D, E and reset shift adaptations.',
                    ecuBadge: 'EGS 0x18 (ZF 6HP/8HP)',
                    routineCode: 'UDS DIDs 0xD301..5 & Routine 0x0F01',
                    accentColor: Colors.blueAccent,
                    icon: Icons.speed,
                    buttons: [
                      OutlinedButton.icon(
                        onPressed: _isActionRunning ? null : _handleReadTransmissionAdaptations,
                        icon: const Icon(Icons.visibility, size: 14),
                        label: const Text('Read Clutches'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.blueAccent,
                          side: const BorderSide(color: Colors.blueAccent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleResetTransmissionAdaptations,
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('Reset Adaptations'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  // Routine 6: Valvetronic & Throttle Re-learn
                  _buildRoutineCard(
                    title: 'Valvetronic & Throttle Stop Re-learn',
                    subtitle: 'Drives VVT eccentric shaft to physical minimum/maximum stops (0.25mm - 9.9mm) and learns throttle stops.',
                    ecuBadge: 'DME 0x12',
                    routineCode: 'UDS Routine 0x31 0x01 10 05',
                    accentColor: Colors.tealAccent,
                    icon: Icons.precision_manufacturing,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleValvetronicRelearn,
                        icon: const Icon(Icons.restart_alt, size: 16),
                        label: const Text('Re-learn End Stops'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.tealAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 7: DPF Regeneration & Ash Mass Reset (res_dpfRegen)
                  _buildRoutineCard(
                    title: 'DPF Regeneration & Ash Mass Reset',
                    subtitle: 'Read live soot/ash loading (DID 0xD017), trigger service regeneration, or reset ash counter after filter swap.',
                    ecuBadge: 'DME/DDE 0x12',
                    routineCode: 'UDS Routine 0xD015 / 0xD016',
                    accentColor: Colors.orangeAccent,
                    icon: Icons.filter_alt_outlined,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleDpfManagement,
                        icon: const Icon(Icons.auto_mode, size: 16),
                        label: const Text('DPF Status & Service'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 8: Steering Angle Sensor Zero-Point Calibration (res_CalSZL, res_epsSzlReset)
                  _buildRoutineCard(
                    title: 'Steering Angle Sensor (SZL / LWS) Calibration',
                    subtitle: 'Read live angle (DID 0x4002) and execute optical zero-point center calibration within factory ±0.5° tolerance.',
                    ecuBadge: 'DSC 0x29 / EPS 0x30',
                    routineCode: 'UDS Routine 0x31 0x01 A0 10',
                    accentColor: Colors.lightGreenAccent,
                    icon: Icons.navigation_outlined,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleSteeringAngleCalibration,
                        icon: const Icon(Icons.tune, size: 16),
                        label: const Text('Calibrate SZL Zero-Point'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightGreenAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 9: FRM Short-Circuit Counter Reset (res_ShortsCir)
                  _buildRoutineCard(
                    title: 'FRM Short-Circuit Counter Reset',
                    subtitle: 'Reset hardware short-circuit latch counter (50-trip lockout) in FRM/BDC EEPROM to restore dead light circuits.',
                    ecuBadge: 'FRM 0x40 (Footwell Module)',
                    routineCode: 'UDS Routine 0x31 0x01 B0 01',
                    accentColor: Colors.yellowAccent,
                    icon: Icons.electric_bolt,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleFrmShortCircuitReset,
                        icon: const Icon(Icons.lock_open, size: 16),
                        label: const Text('Unlock Light Channels'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellowAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 10: Fuel Pump Priming Routine (res_PrimeFuel)
                  _buildRoutineCard(
                    title: 'Fuel Pump Priming Routine',
                    subtitle: 'Run electric fuel pump at 100% duty cycle for 30 seconds to purge air bubbles after pump/filter replacement.',
                    ecuBadge: 'EKP 0x17 / DME 0x12',
                    routineCode: 'UDS Routine 0x31 0x01 F0 10',
                    accentColor: Colors.lightBlueAccent,
                    icon: Icons.local_gas_station,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleFuelPumpPriming,
                        icon: const Icon(Icons.play_circle_filled, size: 16),
                        label: const Text('Prime Fuel Pump (30s)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.lightBlueAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 11: Transport Mode Deactivation / Activation (res_transPort)
                  _buildRoutineCard(
                    title: 'Transport Mode Toggle',
                    subtitle: 'Deactivate factory shipping power-down mode to awaken HVAC blower, audio/infotainment, and comfort access.',
                    ecuBadge: 'Gateway / JBBF 0x00 & BDC 0x40',
                    routineCode: 'UDS Service 0x28 0x00',
                    accentColor: Colors.pinkAccent,
                    icon: Icons.flight_takeoff,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleTransportMode,
                        icon: const Icon(Icons.power_settings_new, size: 16),
                        label: const Text('Toggle Transport Mode'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.pinkAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 12: VTG Transfer Case Fluid Reset (res_vgsgReset)
                  _buildRoutineCard(
                    title: 'VTG Transfer Case Fluid Reset',
                    subtitle: 'Reset oil deterioration integrator counter and erase fault code 54C6 after xDrive transfer case fluid service.',
                    ecuBadge: 'VTG 0x19 (Transfer Case)',
                    routineCode: 'UDS Routine 0x31 0x01 A1 05',
                    accentColor: Colors.deepOrangeAccent,
                    icon: Icons.sync_alt,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleVtgFluidReset,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Reset VTG Oil Counter'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrangeAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  // Routine 13: Adaptive Headlight & LED Leveling Initialization (ISTA FLE_INIT)
                  _buildRoutineCard(
                    title: 'Adaptive Headlight & LED Leveling Initialization (FLE_INIT)',
                    subtitle: 'Stepper Motor Reference Run & Height Sensor Zeroing (ABL_DIT_AS6300_SCHEINWERFER) across FLEL 0x43, FLER 0x44, and FEM 0x40.',
                    ecuBadge: 'FLEL 0x43 / FLER 0x44 / FEM 0x40',
                    routineCode: 'UDS Routine 0x31 0x01 D0 40',
                    accentColor: Colors.cyanAccent,
                    icon: Icons.light_mode,
                    buttons: [
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleHeadlightInitialization,
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text('Initialize Headlights'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ],
                  ),

                  // Routine 14: xDrive VTG Transfer Case Clutch Calibration (ISTA)
                  _buildRoutineCard(
                    title: 'xDrive VTG Transfer Case Clutch Calibration (VTG_KALIBRIERUNG)',
                    subtitle: 'Read degradation index & max torque (DID 0xD210), and calibrate clutch kiss-point & actuator motor (ABL_DIT_AS2700_VTG).',
                    ecuBadge: 'VTG 0x19',
                    routineCode: 'UDS Routine 0xA101 & DID 0xD210',
                    accentColor: Colors.deepOrangeAccent,
                    icon: Icons.settings_suggest,
                    buttons: [
                      OutlinedButton.icon(
                        onPressed: _isActionRunning ? null : _handleVtgReadClutchHealth,
                        icon: const Icon(Icons.health_and_safety, size: 14),
                        label: const Text('Read Clutch Health'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepOrangeAccent,
                          side: const BorderSide(color: Colors.deepOrangeAccent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handleVtgClutchCalibration,
                        icon: const Icon(Icons.tune, size: 14),
                        label: const Text('Calibrate VTG Clutch'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepOrangeAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  // Routine 15: Sunroof & Power Windows Normalization (ISTA)
                  _buildRoutineCard(
                    title: 'Sunroof & Power Windows Normalization',
                    subtitle: 'Learn anti-pinch force curves and mechanical end-stops for panoramic sunroof (FZD 0x56) and power windows (FEM 0x40).',
                    ecuBadge: 'FZD 0x56 & FEM 0x40',
                    routineCode: 'UDS Routine 0xD050 / 0xD051',
                    accentColor: Colors.indigoAccent,
                    icon: Icons.window,
                    buttons: [
                      OutlinedButton.icon(
                        onPressed: _isActionRunning ? null : _handleSunroofNormalization,
                        icon: const Icon(Icons.roofing, size: 14),
                        label: const Text('Normalize Sunroof'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.indigoAccent,
                          side: const BorderSide(color: Colors.indigoAccent),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isActionRunning ? null : _handlePowerWindowsNormalization,
                        icon: const Icon(Icons.view_array, size: 14),
                        label: const Text('Normalize Windows'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigoAccent,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutineCard({
    required String title,
    required String subtitle,
    required String ecuBadge,
    required String routineCode,
    required Color accentColor,
    required IconData icon,
    required List<Widget> buttons,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              ecuBadge,
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            routineCode,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              subtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: buttons,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 1: CBS (CONDITION BASED SERVICE) WIDGET
  // ===========================================================================
  Widget _buildCbsSection() {
    final displayItems = _cbsItems.isNotEmpty
        ? _cbsItems
        : CbsServiceType.values
            .map((t) => CbsItemStatus(
                  type: t,
                  remainingKm: t.nominalIntervalKm,
                  remainingPercent: 100,
                  expiryMonth: DateTime.now().month,
                  expiryYear: DateTime.now().year + 2,
                  status: CbsHealthStatus.ok,
                ))
            .toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.car_repair_rounded, color: Colors.tealAccent, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Condition Based Service (CBS) რესეტები',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Wrap(
                        spacing: 6,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'KOMBI 0x60 / DME 0x12',
                              style: TextStyle(
                                color: Colors.tealAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Text(
                            'DID 0xD00A & Routine 0xD001..6',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _isActionRunning || _isLoadingCbs ? null : _loadCbsStatus,
                  icon: _isLoadingCbs
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.tealAccent),
                        )
                      : const Icon(Icons.refresh, color: Colors.tealAccent, size: 20),
                  tooltip: 'Read live CBS status from vehicle',
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Live Condition Based Service (CBS) monitoring and statutory maintenance counters. Read real-time wear percentage & remaining mileage or execute individual service resets.',
              style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 14),
            ...displayItems.map((item) {
              final pct = item.remainingPercent;
              final Color statusColor = item.status == CbsHealthStatus.overdue
                  ? Colors.redAccent
                  : (item.status == CbsHealthStatus.dueSoon ? Colors.amberAccent : Colors.tealAccent);

              IconData itemIcon;
              switch (item.type) {
                case CbsServiceType.engineOil:
                  itemIcon = Icons.oil_barrel_rounded;
                  break;
                case CbsServiceType.frontBrakes:
                  itemIcon = Icons.disc_full_rounded;
                  break;
                case CbsServiceType.rearBrakes:
                  itemIcon = Icons.album_rounded;
                  break;
                case CbsServiceType.brakeFluid:
                  itemIcon = Icons.water_drop_rounded;
                  break;
                case CbsServiceType.sparkPlugs:
                  itemIcon = Icons.bolt_rounded;
                  break;
                case CbsServiceType.vehicleCheck:
                  itemIcon = Icons.verified_user_rounded;
                  break;
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bgDark,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(itemIcon, color: statusColor, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item.type.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.status.label,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '$pct%',
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct / 100.0,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                        minHeight: 5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.straighten_rounded, color: Colors.white38, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              item.formattedRemainingKm,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                            const SizedBox(width: 8),
                            const Icon(Icons.calendar_month_rounded, color: Colors.white38, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              item.formattedExpiry,
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: _isActionRunning ? null : () => _handleResetCbsItem(item),
                          icon: const Icon(Icons.restart_alt, size: 14),
                          label: const Text('Reset', style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: statusColor,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: const Size(60, 28),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 2: THROTTLE LEARN & IDLE RPM ADJUSTMENT WIDGET
  // ===========================================================================
  Widget _buildThrottleAndIdleSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.lightGreenAccent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.lightGreenAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.speed_rounded, color: Colors.lightGreenAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'დროსელის სწავლება & Idle RPM რეგულირება',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'DME 0x12',
                            style: TextStyle(
                              color: Colors.lightGreenAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Routines 0x1001 / 0x1008 & DID 0xD115',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Subsection A: Throttle End Stops Learn (res_throtCal)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune_rounded, color: Colors.lightGreenAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'დროსელის სწავლება (res_throtCal)',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Re-learns electronic throttle body (DKI) mechanical minimum rest stop (0%), emergency spring limp position (5-7%), and wide-open throttle (100%) stop.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isActionRunning ? null : _handleThrottleCalibration,
                    icon: const Icon(Icons.settings_overscan_rounded, size: 16),
                    label: const Text('Re-learn Throttle End Stops'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.lightGreenAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 38),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Subsection B: Idle RPM Adjustment (res_idleAdj)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.av_timer_rounded, color: Colors.amberAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Idle RPM რეგულირება (res_idleAdj)',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${_selectedIdleOffset >= 0 ? "+" : ""}$_selectedIdleOffset RPM',
                          style: const TextStyle(
                            color: Colors.amberAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Adjust engine base idle speed between -150 RPM and +250 RPM to eliminate chassis vibrations, compensate for lumpy cams, or dual-mass flywheel chatter.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),

                  // AC Toggle
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Standard Idle (A/C OFF)', style: TextStyle(fontSize: 11)),
                        selected: !_idleWithAc,
                        selectedColor: Colors.amberAccent.withValues(alpha: 0.25),
                        backgroundColor: Colors.white10,
                        labelStyle: TextStyle(
                          color: !_idleWithAc ? Colors.amberAccent : Colors.white60,
                          fontWeight: !_idleWithAc ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (sel) {
                          if (sel) {
                            setState(() => _idleWithAc = false);
                            _loadIdleRpm();
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('With A/C Active', style: TextStyle(fontSize: 11)),
                        selected: _idleWithAc,
                        selectedColor: Colors.amberAccent.withValues(alpha: 0.25),
                        backgroundColor: Colors.white10,
                        labelStyle: TextStyle(
                          color: _idleWithAc ? Colors.amberAccent : Colors.white60,
                          fontWeight: _idleWithAc ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (sel) {
                          if (sel) {
                            setState(() => _idleWithAc = true);
                            _loadIdleRpm();
                          }
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Slider
                  Row(
                    children: [
                      const Text('-150', style: TextStyle(color: Colors.white38, fontSize: 10)),
                      Expanded(
                        child: Slider(
                          value: _selectedIdleOffset.toDouble(),
                          min: -150.0,
                          max: 250.0,
                          divisions: 40,
                          activeColor: Colors.amberAccent,
                          inactiveColor: Colors.white12,
                          label: '${_selectedIdleOffset >= 0 ? "+" : ""}$_selectedIdleOffset RPM',
                          onChanged: (val) {
                            setState(() => _selectedIdleOffset = val.round());
                          },
                        ),
                      ),
                      const Text('+250', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    ],
                  ),

                  // Quick presets
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [-100, -50, 0, 50, 100, 150, 200].map((preset) {
                      final isSelected = _selectedIdleOffset == preset;
                      return InkWell(
                        onTap: () => setState(() => _selectedIdleOffset = preset),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.amberAccent.withValues(alpha: 0.2) : Colors.white10,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected ? Colors.amberAccent : Colors.transparent,
                            ),
                          ),
                          child: Text(
                            '${preset >= 0 ? "+" : ""}$preset',
                            style: TextStyle(
                              color: isSelected ? Colors.amberAccent : Colors.white70,
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 12),

                  ElevatedButton.icon(
                    onPressed: _isActionRunning ? null : _handleApplyIdleRpm,
                    icon: const Icon(Icons.check, size: 16),
                    label: Text(
                      'Commit Idle Speed (${_selectedIdleOffset >= 0 ? "+" : ""}$_selectedIdleOffset RPM)',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amberAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 38),
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

  // ===========================================================================
  // SECTION 3: ELV STEERING LOCK & CAS-DME EWS SYNC WIDGET
  // ===========================================================================
  Widget _buildElvAndEwsSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.cyanAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.lock_reset_rounded, color: Colors.cyanAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ELV საჭის საკეტის რესეტი & CAS-DME EWS სინქრონიზაცია',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'CAS 0x40 / DME 0x12',
                            style: TextStyle(
                              color: Colors.cyanAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Routines 0xD100 / 0x2000 / 0x2001',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Item 1: ELV Steering Lock Reset (resetELV / res_lockElv)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.lock_open_rounded, color: Colors.cyanAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'საჭის ელექტრო საკეტის (ELV) რესეტი (res_lockElv)',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Clears the internal ELV counter in CAS/BDC (0x40) EEPROM. Erases faults A0AA, A0AB, A0B0, A115, A116, unlocks the steering column, and removes the yellow/red steering lock symbol.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isActionRunning ? null : _handleResetElv,
                    icon: const Icon(Icons.lock_open, size: 16),
                    label: const Text('Reset ELV Steering Lock'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 38),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Item 2: CAS-DME EWS Rolling Code Sync (res_casDmeSync)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync_lock_rounded, color: Colors.greenAccent, size: 18),
                      SizedBox(width: 8),
                      Text(
                        'CAS-DME (EWS) როლინგ კოდის სინქრონიზაცია (res_casDmeSync)',
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Re-aligns immobilizer rolling codes between Car Access System (0x40) and DME (0x12). Clears anti-tampering lockout (fault 2F44 in DME / 4A63 in DDE) to fix "Crank, No Start" after battery disconnect.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _isActionRunning ? null : _handleCasDmeSync,
                    icon: const Icon(Icons.sync_alt, size: 16),
                    label: const Text('Synchronize CAS-DME Rolling Code'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.greenAccent,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 38),
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

  // ===========================================================================
  // SECTION 4: SOUND & EXHAUST CONTROL WIDGET (ASD & EXHAUST FLAP)
  // ===========================================================================
  Widget _buildSoundAndPowerSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.deepPurpleAccent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.deepPurpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.music_note_rounded, color: Colors.deepPurpleAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sound & Exhaust Flap მართვა',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'ASD 0x20 / HU 0x63 / DME 0x12',
                            style: TextStyle(
                              color: Colors.deepPurpleAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'DID 0x3000 & UDS 0x2F (DID 0x310A)',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Subsection A: Active Sound Design (ASD) Mute / Control
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.volume_up_rounded, color: Colors.purpleAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Active Sound Design (ASD) მართვა',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _asdState == AsdState.muted
                              ? Colors.grey.withValues(alpha: 0.2)
                              : (_asdState == AsdState.reduced
                                  ? Colors.amberAccent.withValues(alpha: 0.2)
                                  : Colors.purpleAccent.withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _asdState == AsdState.muted
                              ? 'MUTED'
                              : (_asdState == AsdState.reduced ? 'REDUCED' : 'ACTIVE'),
                          style: TextStyle(
                            color: _asdState == AsdState.muted
                                ? Colors.grey
                                : (_asdState == AsdState.reduced ? Colors.amberAccent : Colors.purpleAccent),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'სალონის დინამიკებში ხელოვნური ძრავის ხმის მართვა (გათიშვა, შემცირება ან ჩართვა) ASD ECU (0x20) ან HU_NBT (0x63) DID 0x3000 Funktionen-ის მეშვეობით.',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),

                  // 3 State Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isActionRunning || _isLoadingAsd) ? null : () => _handleSetAsdState(AsdState.active),
                          icon: const Icon(Icons.volume_up, size: 14),
                          label: const Text('Active', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _asdState == AsdState.active ? Colors.purpleAccent : Colors.white10,
                            foregroundColor: _asdState == AsdState.active ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isActionRunning || _isLoadingAsd) ? null : () => _handleSetAsdState(AsdState.muted),
                          icon: const Icon(Icons.volume_off, size: 14),
                          label: const Text('Muted', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _asdState == AsdState.muted ? Colors.purpleAccent : Colors.white10,
                            foregroundColor: _asdState == AsdState.muted ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isActionRunning || _isLoadingAsd) ? null : () => _handleSetAsdState(AsdState.reduced),
                          icon: const Icon(Icons.volume_down, size: 14),
                          label: const Text('Reduced', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _asdState == AsdState.reduced ? Colors.purpleAccent : Colors.white10,
                            foregroundColor: _asdState == AsdState.reduced ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Subsection B: Exhaust Flap 3-Way Control (activity_exhaust_flap.xml)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.waves_rounded, color: Colors.redAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Exhaust Flap (გამონაბოლქვის ფლაპები)',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _exhaustFlapMode == ExhaustFlapMode.forceOpen
                              ? Colors.redAccent.withValues(alpha: 0.2)
                              : (_exhaustFlapMode == ExhaustFlapMode.forceClosed
                                  ? Colors.blueAccent.withValues(alpha: 0.2)
                                  : Colors.greenAccent.withValues(alpha: 0.2)),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _exhaustFlapMode == ExhaustFlapMode.forceOpen
                              ? 'FORCE OPEN'
                              : (_exhaustFlapMode == ExhaustFlapMode.forceClosed ? 'FORCE CLOSED' : 'AUTO (OEM)'),
                          style: TextStyle(
                            color: _exhaustFlapMode == ExhaustFlapMode.forceOpen
                                ? Colors.redAccent
                                : (_exhaustFlapMode == ExhaustFlapMode.forceClosed ? Colors.blueAccent : Colors.greenAccent),
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'გამონაბოლქვის ელექტრონული ფლაპის 3-Way მართვა: Auto (OEM ქარხნული მართვა), Force Open (მუდმივად 100% ღია ხმამაღალი აკუსტიკისთვის), Force Closed (მუდმივად დახურული ჩუმი მგზავრობისთვის).',
                    style: TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                  ),
                  const SizedBox(height: 10),

                  // 3 Flap Mode Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isActionRunning || _isLoadingExhaustFlap) ? null : () => _handleSetExhaustFlapMode(ExhaustFlapMode.autoOem),
                          icon: const Icon(Icons.autorenew_rounded, size: 14),
                          label: const Text('Auto (OEM)', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _exhaustFlapMode == ExhaustFlapMode.autoOem ? Colors.redAccent : Colors.white10,
                            foregroundColor: _exhaustFlapMode == ExhaustFlapMode.autoOem ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isActionRunning || _isLoadingExhaustFlap) ? null : () => _handleSetExhaustFlapMode(ExhaustFlapMode.forceOpen),
                          icon: const Icon(Icons.lock_open_rounded, size: 14),
                          label: const Text('Force Open', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _exhaustFlapMode == ExhaustFlapMode.forceOpen ? Colors.redAccent : Colors.white10,
                            foregroundColor: _exhaustFlapMode == ExhaustFlapMode.forceOpen ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_isActionRunning || _isLoadingExhaustFlap) ? null : () => _handleSetExhaustFlapMode(ExhaustFlapMode.forceClosed),
                          icon: const Icon(Icons.lock_outline_rounded, size: 14),
                          label: const Text('Force Closed', style: TextStyle(fontSize: 11)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _exhaustFlapMode == ExhaustFlapMode.forceClosed ? Colors.redAccent : Colors.white10,
                            foregroundColor: _exhaustFlapMode == ExhaustFlapMode.forceClosed ? Colors.black : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 5: MASTER MECHANICAL ADAPTATIONS & CALIBRATION (ProTool DEX)
  // ===========================================================================
  Widget _buildMasterMechanicalAndCalibrationSection() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.precision_manufacturing_rounded, color: Colors.tealAccent, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'მოწინავე მექანიკური ადაპტაციები & კალიბრაცია',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 2),
                      Row(
                        children: [
                          Text(
                            'DME / DSC / EHC / RLS / AFS',
                            style: TextStyle(
                              color: Colors.tealAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Advanced Workshop Routines',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Item 1: Valvetronic (VVT) Limit Positions Learn (res_vvtCal)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tune_rounded, color: Colors.tealAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Valvetronic (VVT) სწავლება',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.tealAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DME 0x12 • 0x1005',
                          style: TextStyle(color: Colors.tealAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'მინიმალური (0.25 მმ) და მაქსიმალური (9.9 მმ) ექსცენტრიკული ლილვის მექანიკური სვლის კალიბრაცია და ზამბარის ძალის ადაპტაცია (N20/N55/S55/B58 ძრავებისთვის).',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isActionRunning ? null : _handleValvetronicCalibration,
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: const Text('Valvetronic სწავლება (res_vvtCal)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.tealAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Item 2: Master Engine Adaptations Reset (res_engineAdapt)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.restart_alt_rounded, color: Colors.orangeAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Engine Adaptations Reset',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orangeAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DME 0x12 • 0x1000',
                          style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'სრულად განულდება: Lambda ნარევის ადაპტაციები (STFT/LTFT), დროსელის დატვირთვის მოდელი, ოქტანობის კორექციის ცხრილები და VANOS-ის ადაპტაციები.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isActionRunning ? null : _handleResetEngineAdaptations,
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: const Text('Engine Adaptations Reset (res_engineAdapt)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Item 3: Rain / Light / Solar Sensor Windshield Initialization (res_RLSInit)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.water_drop_outlined, color: Colors.cyanAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Rain/Light Sensor (RLS) ინიციალიზაცია',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'RLS 0x56 / FEM 0x40',
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'საქარე მინის შეცვლის შემდეგ ოპტიკური გარდატეხის კოეფიციენტის განულება და სენსორის მინაზე მორგება Routine 0x31 0x01 A0 02-ით.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isActionRunning ? null : _handleRainLightSensorInit,
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('RLS ინიციალიზაცია (res_RLSInit)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Item 4: Tire Pressure Monitor (TPMS / RDC / RPA) Reset (res_TpmsReset)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.tire_repair, color: Colors.amberAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'TPMS საბურავების წნევის რესეტი',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DSC 0x29 • 0xD030',
                          style: TextStyle(color: Colors.amberAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'საბურავების წნევის დაკალიბრების რეჟიმის გაშვება DSC-ში (Routine 0x31 0x01 D0 30) და სასწავლო მოძრაობის ინიციალიზაცია.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isActionRunning ? null : _handleTpmsReset,
                      icon: const Icon(Icons.settings_backup_restore, size: 16),
                      label: const Text('TPMS რესეტი (res_TpmsReset)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amberAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Item 5: Air Suspension (EHC / Luftfederung) Ride Height Calibration (res_rideHeight)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.height_rounded, color: Colors.lightGreenAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Air Suspension სიმაღლის კალიბრაცია',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.lightGreenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'EHC 0x6E / VDC 0x3F',
                          style: TextStyle(color: Colors.lightGreenAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'უკანა პნევმო დაკიდების სიმაღლის კალიბრაცია F11, F15, G05, G31 მოდელებისთვის (Routine 0x31 0x01 41 01).',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),

                  // Left & Right mm Offsets adjustment
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Left Axle (მმ)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
                                    onPressed: () {
                                      if (_airSuspensionLeftMm > -30) {
                                        setState(() => _airSuspensionLeftMm -= 1);
                                      }
                                    },
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    padding: EdgeInsets.zero,
                                  ),
                                  Text(
                                    '${_airSuspensionLeftMm >= 0 ? "+" : ""}$_airSuspensionLeftMm',
                                    style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                                    onPressed: () {
                                      if (_airSuspensionLeftMm < 30) {
                                        setState(() => _airSuspensionLeftMm += 1);
                                      }
                                    },
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text('Right Axle (მმ)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
                                    onPressed: () {
                                      if (_airSuspensionRightMm > -30) {
                                        setState(() => _airSuspensionRightMm -= 1);
                                      }
                                    },
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    padding: EdgeInsets.zero,
                                  ),
                                  Text(
                                    '${_airSuspensionRightMm >= 0 ? "+" : ""}$_airSuspensionRightMm',
                                    style: const TextStyle(color: Colors.lightGreenAccent, fontSize: 14, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 16, color: Colors.white70),
                                    onPressed: () {
                                      if (_airSuspensionRightMm < 30) {
                                        setState(() => _airSuspensionRightMm += 1);
                                      }
                                    },
                                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                    padding: EdgeInsets.zero,
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isActionRunning ? null : _handleAirSuspensionCalibration,
                      icon: const Icon(Icons.play_arrow_rounded, size: 16),
                      label: Text('სიმაღლის კალიბრაცია (L: ${_airSuspensionLeftMm}mm, R: ${_airSuspensionRightMm}mm)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.lightGreenAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Item 6: Cylinder Smoothness (Zylindergleichstellung - res_CylEqu)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.equalizer, color: Colors.cyanAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Cylinder Running Smoothness',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.cyanAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'DME 0x12 • 0xD120',
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'ცილინდრების 1-6 flywheel აჩქარების რხევები (Zylindergleichstellung) 1/min²-ში. ამოწმებს ინჟექტორების დისბალანსსა და ცილინდრების თანაბარ მუშაობას (ძრავი უნდა იყოს Idle-ზე).',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  if (_lastSmoothnessData != null && _lastSmoothnessData!.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _lastSmoothnessData!.map((c) {
                        final tagColor = c.isCritical
                            ? Colors.redAccent
                            : (c.isElevated ? Colors.amberAccent : Colors.greenAccent);
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: tagColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: tagColor.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            'Cyl ${c.cylinder}: ${c.formattedRoughness}',
                            style: TextStyle(color: tagColor, fontSize: 10, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isLoadingSmoothness ? null : _handleCylinderSmoothness,
                      icon: _isLoadingSmoothness
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.analytics_outlined, size: 16),
                      label: const Text('ცილინდრების რხევის გაზომვა (res_CylEqu)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.cyanAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Item 7: Active Front Steering (AFS) Center Calibration (res_CalAFS)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _bgDark,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.directions_car_rounded, color: Colors.blueAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'Active Front Steering (AFS) კალიბრაცია',
                            style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blueAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'AFS 0x1B • 0xA012',
                          style: TextStyle(color: Colors.blueAccent, fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'საჭის აქტიური მექანიზმის (AFS/AL) პლანეტარული რედუქტორის ნულოვანი ცენტრის კალიბრაცია და საჭის კუთხესთან სინქრონიზაცია Routine 0x31 0x01 A0 12-ით.',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isActionRunning ? null : _handleActiveFrontSteeringCalibration,
                      icon: const Icon(Icons.straighten, size: 16),
                      label: const Text('AFS ცენტრის კალიბრაცია (res_CalAFS)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
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
}
