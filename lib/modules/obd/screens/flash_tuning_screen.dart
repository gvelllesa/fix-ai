// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/config/feature_flags.dart';
import '../services/actuation_guard.dart';
import '../services/flash_os_guard.dart';
import '../services/bmw_flash_options.dart';
import '../services/bmw_live_actuator.dart';
import '../services/bmw_flash_manager.dart';
import '../services/bmw_custom_rom_service.dart';
import '../services/protocols/enet_hsfz_protocol.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/link_status_bar.dart';

class FlashTuningScreen extends StatefulWidget {
  final EnetHsfzProtocol? activeProtocol;

  const FlashTuningScreen({super.key, this.activeProtocol});

  @override
  State<FlashTuningScreen> createState() => _FlashTuningScreenState();
}

class _FlashTuningScreenState extends State<FlashTuningScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BmwLiveActuator _liveActuator;
  late BmwFlashManager _flashManager;
  late BmwCustomRomService _customRomService;
  final BmwFlashOptions _options = BmwFlashOptions();

  // Tab 1: Custom ROM & Multimap state
  CustomRomSlot _activeSlot = CustomRomSlot.slot1;
  int _tachometerRpm = 1000;
  bool _isSlotSwitching = false;
  bool _isResTriggering = false;
  bool _isAntiLagTriggering = false;
  bool _isTestingCel = false;
  bool _isTestingShiftBrap = false;
  bool _isAntiTheftArmed = false;
  bool _isAntiTheftLoading = false;
  bool _isFlexFuelLoading = false;
  FlexFuelData _flexFuelData = const FlexFuelData(
    ethanolPercent: 35.0,
    fuelTempCelsius: 24.0,
    boostScalar: 1.117,
    timingAdvanceDeg: 1.83,
    isSensorValid: true,
  );

  // Tab 2: OTS Flash state
  bool _isFlashing = false;
  double _flashProgress = 0.0;
  String _flashStatus = '';
  int _selectedGearIndex = 0; // 0..7 (Gears 1..8)
  bool _isFlashingTcu = false;
  bool _isWritingDmeOptions = false;
  StreamSubscription? _flashSubscription;

  // Tab 3: Actuator state
  bool _maxCoolingActive = false;
  bool _exhaustFlapOpen = false;
  int _wastegateActuationDc = 50;
  bool _isActuatorLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _liveActuator = BmwLiveActuator(protocol: widget.activeProtocol);
    _flashManager = BmwFlashManager(protocol: widget.activeProtocol);
    _customRomService = BmwCustomRomService(protocol: widget.activeProtocol);
    _loadCustomRomState();
  }

  @override
  void dispose() {
    _flashSubscription?.cancel();
    FlashOsGuard.instance.release();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCustomRomState() async {
    try {
      final slot = await _customRomService.readActiveSlot();
      if (slot != null && mounted) {
        setState(() {
          _activeSlot = slot;
          _tachometerRpm = slot.clusterTachRpm;
        });
      }

      final ff = await _customRomService.readFlexFuelData();
      if (ff != null && mounted) {
        setState(() => _flexFuelData = ff);
      }

      final armed = await _customRomService.isAntiTheftArmed();
      if (armed != null && mounted) {
        setState(() => _isAntiTheftArmed = armed);
      }

      final ral = await _customRomService.readRollingAntiLag();
      if (ral != null && mounted) {
        setState(() => _options.antiLag = ral);
      }

      final bbg = await _customRomService.readBoostByGear();
      if (bbg != null && mounted) {
        setState(() => _options.boostByGear = bbg);
      }

      final tbg = await _customRomService.readTorqueByGear();
      if (tbg != null && mounted) {
        setState(() => _options.torqueByGear = tbg);
      }

      final hpfp = await _customRomService.readHpfpProfile();
      if (hpfp != null && mounted) {
        setState(() => _options.hpfp = hpfp);
      }

      final tmap = await _customRomService.readTmapCalibration();
      if (tmap != null && mounted) {
        setState(() {
          _options.manifoldTMAP = tmap['manifold']!;
          _options.preThrottleTMAPSensor = tmap['preThrottle']!;
        });
      }

      final tcu = await _customRomService.readTcuOptions();
      if (tcu != null && mounted) {
        setState(() => _options.tcuOptions = tcu);
      }

      final burble = await _customRomService.readBurbleOptions();
      if (burble != null && mounted) {
        setState(() {
          _options.burbleAggressiveness = burble['aggressiveness'] as BurbleAggressiveness;
          _options.burbleDurationSeconds = burble['duration'] as double;
          _options.sportBurbleDurationSeconds = burble['sportDuration'] as double;
          _options.burbleMinRpm = burble['minRpm'] as int;
          _options.burbleMaxRpm = burble['maxRpm'] as int;
        });
      }

      final coldStart = await _customRomService.readColdStartDeactivation();
      if (coldStart != null && mounted) {
        setState(() => _options.coldStartDisabled = coldStart);
      }

      final vmax = await _customRomService.readSpeedLimiterVmax();
      if (vmax != null && mounted) {
        setState(() => _options.vmaxDisabled = vmax);
      }

      final flap = await _customRomService.readExhaustFlapConfig();
      if (flap != null && mounted) {
        setState(() => _options.exhaustFlapOpenInSport = (flap == 1));
      }
    } catch (_) {}
  }

  Future<void> _switchSlot(CustomRomSlot slot) async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      setState(() {
        _activeSlot = slot;
        _tachometerRpm = slot.clusterTachRpm;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚡ Preview რეჟიმი: არჩეულია ${slot.title} (სპიდომეტრის ისარი: ${slot.clusterTachRpm} RPM).'),
          backgroundColor: const Color(0xFF161B22),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isSlotSwitching = true);
    final ok = await _customRomService.switchMapSlot(slot.id);
    if (mounted) {
      setState(() {
        _isSlotSwitching = false;
        if (ok) {
          _activeSlot = slot;
          _tachometerRpm = slot.clusterTachRpm;
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '⚡ Multimap switched to ${slot.title}! Cluster tach swept to ${slot.clusterTachRpm} RPM.'
                : 'Failed to switch map slot. Verify Custom ROM bootloader unlock.',
          ),
          backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _triggerCruiseResNeedle() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      setState(() => _tachometerRpm = _activeSlot.clusterTachRpm);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('🎯 Preview რეჟიმი: Cruise "RES" ისარი: $_tachometerRpm RPM (${_activeSlot.title}).'),
          backgroundColor: Colors.cyan.shade900,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    setState(() => _isResTriggering = true);
    final ok = await _customRomService.triggerCruiseResButton(targetSlot: _activeSlot.id);
    if (mounted) {
      setState(() {
        _isResTriggering = false;
        _tachometerRpm = _activeSlot.clusterTachRpm;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '🎯 Cruise "RES" triggered! Cluster tach needle indicating $_tachometerRpm RPM (${_activeSlot.title}).'
                : 'Cruise RES signal sent. Check CAN/HSFZ connection.',
          ),
          backgroundColor: ok ? Colors.cyan.shade800 : Colors.amber.shade900,
        ),
      );
    }
  }

  Future<void> _triggerAntiLagLive() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ავტომობილი არ არის დაკავშირებული. Anti-Lag-ის გასაშვებად შეაერთეთ OBD/ENET ადაპტერი.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    final confirmed = await ActuationGuard.confirmActuation(
      context,
      title: 'Rolling Anti-Lag Actuation',
      descriptionKa:
          'Rolling Anti-Lag ცვლის ანთების კუთხეს (${_options.antiLag.ignitionRetardDeg}° ATDC) და ზრდის ტურბინის წნევას (${_options.antiLag.boostTargetPsi} PSI). დარწმუნდით, რომ ავტომობილი უსაფრთხო გარემოშია.',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isAntiLagTriggering = true);
    final ok = await _customRomService.triggerRollingAntiLag(
      activate: true,
      boostTargetPsi: _options.antiLag.boostTargetPsi,
      durationSeconds: _options.antiLag.maxDurationSeconds,
      retardDeg: _options.antiLag.ignitionRetardDeg,
    );
    if (mounted) {
      setState(() => _isAntiLagTriggering = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '🔥 Rolling Anti-Lag ACTIVATED! Cruise rocker held. Retard: ${_options.antiLag.ignitionRetardDeg}° ATDC | Target: ${_options.antiLag.boostTargetPsi} PSI.'
                : 'Rolling Anti-Lag routine command sent (UDS 0x31 0xD421).',
          ),
          backgroundColor: ok ? Colors.orange.shade900 : Colors.grey.shade900,
        ),
      );
    }
  }

  Future<void> _saveAntiLagDmeRam() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ავტომობილი გამორთულია. პარამეტრები შენახულია აპლიკაციაში.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    final ok = await _customRomService.writeRollingAntiLag(_options.antiLag);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '💾 Rolling Anti-Lag settings written to DME RAM DID 0xD420!'
                : 'Failed to write Anti-Lag DID. Verify Custom ROM unlock.',
          ),
          backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _testKnockCelFlash() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ავტომობილი გამორთულია. KOMBI შემოწმებისთვის შეაერთეთ ადაპტერი.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    setState(() => _isTestingCel = true);
    final ok = await _customRomService.testKnockCelFlash(
      flashCount: 4,
      rateHz: _options.knockCel.flashRateHz,
    );
    if (mounted) {
      setState(() => _isTestingCel = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '🚨 Knock CEL Alert triggered on cluster KOMBI (4 pulses @ ${_options.knockCel.flashRateHz}Hz)!'
                : 'Knock CEL routine command sent to cluster (0x60 / 0xD466).',
          ),
          backgroundColor: ok ? Colors.amber.shade900 : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _testShiftBrapLive() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ავტომობილი გამორთულია. Shift Brap ტესტისთვის შეაერთეთ ადაპტერი.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    setState(() => _isTestingShiftBrap = true);
    final ok = await _customRomService.testShiftBrap();
    if (mounted) {
      setState(() => _isTestingShiftBrap = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '💥 Transmission Shift Brap pulse actuated (Spark Cut ${_options.shiftBrap.durationMs}ms)!'
                : 'Shift Brap routine sent to DME (UDS 0x31 0xD461).',
          ),
          backgroundColor: ok ? Colors.deepOrange.shade800 : Colors.grey.shade900,
        ),
      );
    }
  }

  Future<void> _flashTcuOptionsToEgs() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ავტომობილი გამორთულია. TCU კალიბრაციის ჩასაწერად შეაერთეთ OBD/ENET ადაპტერი.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    setState(() => _isFlashingTcu = true);
    final ok = await _customRomService.writeTcuOptions(_options.tcuOptions);
    if (mounted) {
      setState(() => _isFlashingTcu = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '⚡ TCU Transmission Calibration written to EGS (0x18 / DID 0xD440) successfully!'
                : 'Failed to write TCU calibration to EGS ECU 0x18. Verify OBD/ENET connection.',
          ),
          backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _writeDmeCustomOptionsLive() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ავტომობილი გამორთულია. DME ოფციების ჩასაწერად შეაერთეთ OBD/ENET ადაპტერი.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    setState(() => _isWritingDmeOptions = true);
    final ok = await _customRomService.writeDmeCustomOptions(_options);
    if (mounted) {
      setState(() => _isWritingDmeOptions = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '⚡ DME Custom Options (Burble, Cold Start, VMAX, Exhaust Flap) წარმატებით ჩაიწერა (DIDs 0xD408-0xD40B)!'
                : 'DME Custom Options ჩაწერა გადაიგზავნა DME ECU-ში.',
          ),
          backgroundColor: ok ? Colors.green.shade800 : Colors.grey.shade900,
        ),
      );
    }
  }

  Future<void> _refreshFlexFuel() async {
    final isOnline = widget.activeProtocol?.isConnected ?? false;
    if (!isOnline) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🌾 ავტომობილი გამორთულია. ნაჩვენებია შენახული FlexFuel პარამეტრები.'),
          backgroundColor: Color(0xFF161B22),
        ),
      );
      return;
    }

    setState(() => _isFlexFuelLoading = true);
    final ff = await _customRomService.readFlexFuelData();
    if (mounted) {
      setState(() {
        _isFlexFuelLoading = false;
        if (ff != null) _flexFuelData = ff;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ff != null
                ? '🌾 FlexFuel live data refreshed: ${ff.ethanolPercent.toInt()}% Ethanol (${ff.fuelTempCelsius.toInt()}°C)'
                : 'DME RAM DID 0xD410 read failed. Check adapter connection.',
          ),
          backgroundColor: ff != null ? Colors.green.shade800 : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _toggleAntiTheft() async {
    if (!_isAntiTheftArmed) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.redAccent),
              SizedBox(width: 10),
              Text('Arm Anti-Theft Kill Switch?', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: const Text(
            'This completely cuts DME injector pulse widths to 0% and disables the starter relay. The engine cannot start until disarmed via PIN.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('ARM NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() => _isAntiTheftLoading = true);
        final ok = await _customRomService.armAntiTheft();
        if (mounted) {
          setState(() {
            _isAntiTheftLoading = false;
            if (ok) _isAntiTheftArmed = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ok ? '🔒 Anti-Theft Armed! Fuel injection & starter disabled.' : 'Failed to arm Anti-Theft.',
              ),
              backgroundColor: ok ? Colors.red.shade900 : Colors.grey.shade900,
            ),
          );
        }
      }
    } else {
      _showDisarmPinDialog();
    }
  }

  void _showDisarmPinDialog() {
    final controllers = List.generate(4, (_) => TextEditingController());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Row(
          children: [
            Icon(Icons.lock_open, color: Colors.greenAccent),
            SizedBox(width: 10),
            Text('Disarm Anti-Theft PIN', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter 4-digit PIN routine authentication code (Default: 1 2 3 4):',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: List.generate(4, (index) {
                return SizedBox(
                  width: 45,
                  child: TextField(
                    controller: controllers[index],
                    autofocus: index == 0,
                    keyboardType: TextInputType.number,
                    maxLength: 1,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 20, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF0D1117),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onChanged: (val) {
                      if (val.isNotEmpty && index < 3) {
                        FocusScope.of(ctx).nextFocus();
                      }
                    },
                  ),
                );
              }),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () async {
              final pin = controllers.map((c) => int.tryParse(c.text.trim()) ?? 0).toList();
              Navigator.pop(ctx);
              setState(() => _isAntiTheftLoading = true);
              final ok = await _customRomService.disarmAntiTheft(pin: pin);
              if (mounted) {
                setState(() {
                  _isAntiTheftLoading = false;
                  if (ok) _isAntiTheftArmed = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok ? '🔓 Anti-Theft Disarmed! Engine injection restored.' : 'PIN authentication failed.',
                    ),
                    backgroundColor: ok ? Colors.green.shade800 : Colors.red.shade900,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
            child: const Text('Authenticate & Disarm', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleMaxCooling() async {
    setState(() => _isActuatorLoading = true);
    final targetState = !_maxCoolingActive;
    final success = await _liveActuator.setMaxCooling(targetState);
    if (mounted) {
      setState(() {
        _isActuatorLoading = false;
        if (success) _maxCoolingActive = targetState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (targetState ? '⚡ Max Cooling Mode ACTIVATED (Pump & Fan 100%)' : 'Max Cooling returned to DME Control')
                : 'Failed to actuate cooling pump. Check ENET/OBD connection.',
          ),
          backgroundColor: success ? (targetState ? Colors.cyan.shade800 : Colors.green.shade800) : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _toggleExhaustFlap() async {
    setState(() => _isActuatorLoading = true);
    final targetState = !_exhaustFlapOpen;
    final success = await _liveActuator.setExhaustFlap(targetState);
    if (mounted) {
      setState(() {
        _isActuatorLoading = false;
        if (success) _exhaustFlapOpen = targetState;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (targetState ? '🔊 Exhaust Flap FORCED OPEN' : 'Exhaust Flap RETURNED TO DME CONTROL')
                : 'Failed to actuate exhaust flap.',
          ),
          backgroundColor: success ? Colors.green.shade800 : Colors.red.shade900,
        ),
      );
    }
  }

  Future<void> _actuateWastegateDutyCycle(int dc) async {
    final confirmed = await ActuationGuard.confirmActuation(
      context,
      title: 'Wastegate Solenoid ($dc% PWM)',
      descriptionKa:
          'Wastegate სოლენოიდის მართვა ($dc% Duty Cycle) UDS 0x2F სერვისით (ავტომატური გათიშვით 30 წამში).',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isActuatorLoading = true);
    final success = await _liveActuator.setWastegateDutyCycle(dc);
    if (mounted) {
      setState(() => _isActuatorLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? '⚡ Pneumatic Wastegate PWM set to $dc% Duty Cycle'
                : 'Failed to actuate wastegate solenoid. Verify DME session.',
          ),
          backgroundColor: success ? Colors.cyan.shade800 : Colors.red.shade900,
        ),
      );
    }
  }

  void _showFlashConfirmation() async {
    final preFlight = await _flashManager.runPreFlightChecks();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: !_isFlashing,
      enableDrag: !_isFlashing,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return PopScope(
              canPop: !_isFlashing,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!FeatureFlags.kFlashEnabled) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.redAccent),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.shield_outlined, color: Colors.redAccent, size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'ECU Flashing დროებით გამორთულია უსაფრთხოების რეჟიმით (HIL/bench ვერიფიკაციამდე)',
                                  style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
                          ),
                          const SizedBox(width: 14),
                          const Expanded(
                            child: Text(
                              'Pre-Flash Safety Interlocks',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildInterlockRow(
                        icon: Icons.battery_charging_full,
                        title: 'Battery Voltage',
                        value: '${preFlight.batteryVoltage.toStringAsFixed(2)} V (Min: 12.50V)',
                        isOk: preFlight.batteryVoltage >= 12.5,
                      ),
                    const SizedBox(height: 8),
                    _buildInterlockRow(
                      icon: Icons.power_settings_new,
                      title: 'Ignition Status',
                      value: preFlight.isIgnitionOnEngineOff ? 'Ignition ON / Engine OFF' : 'Engine Running Hazard',
                      isOk: preFlight.isIgnitionOnEngineOff,
                    ),
                    const SizedBox(height: 8),
                    _buildInterlockRow(
                      icon: Icons.lock_open,
                      title: 'DME Unlock / Custom ROM',
                      value: preFlight.isCustomRomBootloader
                          ? 'Custom ROM Bootloader Ready'
                          : (preFlight.isDmeUnlocked ? 'OBD Flash Ready' : 'DME Bootloader Locked'),
                      isOk: preFlight.isDmeUnlocked || preFlight.isCustomRomBootloader,
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
                          const Text(
                            'Selected Calibration Patches (ZERO SIMULATION):',
                            style: TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 6),
                          Text('• Base OTS Map: ${_options.stage.title}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Thermostat Target: ${_options.coolingMode.label}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Burble: ${_options.burbleAggressiveness.label} (${_options.burbleDurationSeconds}s base / ${_options.sportBurbleDurationSeconds}s sport)', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Rolling Anti-Lag: ${_options.antiLag.enabled ? "${_options.antiLag.boostTargetPsi} PSI target (${_options.antiLag.ignitionRetardDeg}° ATDC, ${_options.antiLag.maxDurationSeconds}s)" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• HPFP Flow Scaling: ${_options.hpfp.label} (${_options.hpfp.flowScalar}x Flow, ${_options.hpfp.maxPressureBar} Bar)', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TMAP Sensors: Manifold: ${_options.manifoldTMAP.label} | Pre-Throttle: ${_options.preThrottleTMAPSensor.label}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Boost By Gear: ${_options.boostByGear.enabled ? "G1:${_options.boostByGear.gearLimitsPsi[0]} PSI, G2:${_options.boostByGear.gearLimitsPsi[1]} PSI, G3:${_options.boostByGear.gearLimitsPsi[2]} PSI..." : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Torque By Gear: ${_options.torqueByGear.enabled ? "G1:${_options.torqueByGear.gearLimitsNm[0]} Nm, G2:${_options.torqueByGear.gearLimitsNm[1]} Nm..." : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• GTS Startup Roar: ${_options.gtsStartupRoar.enabled ? "${_options.gtsStartupRoar.durationMs}ms bark (${_options.gtsStartupRoar.flareRpmTarget} RPM)" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Shift Brap (ZF/DCT): ${_options.shiftBrap.enabled ? "Aggressiveness ${_options.shiftBrap.aggressiveness} (${_options.shiftBrap.durationMs}ms cut)" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Wastegate Rattle Fix: ${_options.wastegateRattleFix ? "${_options.wastegateDutyCycleOffsetPercent}% PWM offset" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Knock CEL Notification: ${_options.knockCel.enabled ? ">${_options.knockCel.timingThresholdDeg}° retard alert (@${_options.knockCel.flashRateHz}Hz)" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Catless Downpipe CEL Mask: ${_options.catlessSuppression.enabled ? "Suppressed (180001, 12B104, 180002, P0420, P0430)" : "OEM Monitoring"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• Multimap Enabled: ${_options.multimapEnabled ? "YES (Slots 1-4)" : "NO"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• FlexFuel Sensor: ${_options.flexFuelEnabled ? "CAN 0x4F0 Active" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU Line Pressure Bump: ${_options.tcuOptions.linePressureBump ? "19 Bar High Clamping (800+ Nm)" : "Stock Clamping"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU Custom Launch: ${_options.tcuOptions.customLaunchControlEnabled ? "${_options.tcuOptions.launchRpm} RPM, ${_options.tcuOptions.launchBoostPsi} PSI, Punch Lvl ${_options.tcuOptions.torquePunch}" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU Shift Speed: ${_options.tcuOptions.shiftSpeed.label} | Max Shift: ${_options.tcuOptions.maxShiftRpm} RPM', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU True Manual Mode (Rev Limiter Hold): ${_options.tcuOptions.trueManualMode ? "ENABLED" : "Disabled"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU Kickdown Lockout (M Mode): ${_options.tcuOptions.kickdownManualDisabled ? "Inhibited" : "OEM"} | 2nd Gear Launch: ${_options.tcuOptions.takeOffIn2ndGear ? "Active" : "1st Gear"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU Downshift Blips: ${_options.tcuOptions.throttleBlipAggressiveness}% | Kombi Display: ${_options.tcuOptions.gearDisplayKombi ? "D1..D8 / S1..S8" : "OEM D/S"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Text('• TCU Torque Limits Per Gear: ${_options.tcuOptions.torqueLimitsPerGearRemoved ? "Removed (1st-8th)" : "Active"} | Standstill Decoupling: ${_options.tcuOptions.standstillDecouplingDisabled ? "Disabled (Instant)" : "Stock"}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_isFlashing) ...[
                      LinearProgressIndicator(
                        value: _flashProgress,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                      ),
                      const SizedBox(height: 10),
                      Center(
                        child: Text(
                          '$_flashStatus (${(_flashProgress * 100).toInt()}%)',
                          style: const TextStyle(color: Colors.greenAccent, fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Colors.white24),
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: SlideToConfirm(
                              label: 'SLIDE TO FLASH DME',
                              confirmedLabel: 'FLASHING...',
                              sliderColor: const Color(0xFF00E676),
                              icon: Icons.flash_on,
                              isEnabled: (FeatureFlags.kFlashEnabled && preFlight.passed),
                              currentRpm: preFlight.isIgnitionOnEngineOff ? 0.0 : 800.0,
                              onConfirmed: () async {
                                setModalState(() => _isFlashing = true);
                                setState(() => _isFlashing = true);
                                await FlashOsGuard.instance.acquire();
                                _flashSubscription?.cancel();
                                _flashSubscription = _flashManager.executeFlash(options: _options).listen(
                                  (event) {
                                    if (!mounted) return;
                                    final progress = (event['progress'] as num?)?.toDouble() ?? 0.0;
                                    final msg = (event['message'] as String?) ?? '';
                                    setModalState(() {
                                      _flashProgress = progress;
                                      _flashStatus = msg;
                                    });
                                    setState(() {
                                      _flashProgress = progress;
                                      _flashStatus = msg;
                                    });

                                    if (event['step'] == 'COMPLETE' || event['step'] == 'FAILED' || event['step'] == 'SAFETY_LOCK') {
                                      FlashOsGuard.instance.release();
                                      setModalState(() => _isFlashing = false);
                                      setState(() => _isFlashing = false);
                                    }
                                  },
                                  onError: (err) {
                                    FlashOsGuard.instance.release();
                                    if (!mounted) return;
                                    setModalState(() {
                                      _isFlashing = false;
                                      _flashStatus = 'შეცდომა: $err';
                                    });
                                    setState(() {
                                      _isFlashing = false;
                                      _flashStatus = 'შეცდომა: $err';
                                    });
                                  },
                                  onDone: () {
                                    FlashOsGuard.instance.release();
                                  },
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      );
    },
  );
}

  Widget _buildInterlockRow({
    required IconData icon,
    required String title,
    required String value,
    required bool isOk,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: isOk ? Colors.greenAccent : Colors.redAccent),
        const SizedBox(width: 10),
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: isOk ? Colors.greenAccent : Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
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
            Icon(Icons.tune, color: Colors.greenAccent, size: 22),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'BMW DME Tuning',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(icon: Icon(Icons.flash_auto, size: 18), text: 'Custom ROM'),
            Tab(icon: Icon(Icons.memory, size: 18), text: 'OTS Maps'),
            Tab(icon: Icon(Icons.bolt, size: 18), text: 'Actuators'),
          ],
        ),
      ),
      body: Column(
        children: [
          LinkStatusBar(
            flashProgress: _isFlashing ? _flashProgress : null,
            flashStage: _isFlashing ? _flashStatus : null,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCustomRomMultimapTab(),
                _buildFlashCalibrationTab(),
                _buildLiveActuatorsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: CUSTOM ROM & MULTIMAP
  // ==========================================

  Widget _buildCustomRomMultimapTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Custom ROM Status Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.greenAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.greenAccent, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Custom Calibrated ROM Active',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'On-the-fly Multimap switching, Rolling Anti-Lag (Cruise Rocker), FlexFuel CAN 0x4F0 & Knock CEL alert.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12, height: 1.3),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Multimap Slot Switcher Section
        _buildSectionHeader('Live Multimap Slot Selector (On-The-Fly)', Icons.layers),
        Column(
          children: CustomRomSlot.values.map((slot) {
            final isSelected = _activeSlot == slot;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected ? Colors.greenAccent : Colors.white12,
                  width: isSelected ? 1.8 : 1.0,
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: CircleAvatar(
                  backgroundColor: isSelected ? Colors.greenAccent : Colors.white10,
                  foregroundColor: isSelected ? Colors.black : Colors.white70,
                  child: Text('${slot.id}', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                title: Row(
                  children: [
                    Expanded(
                      child: Text(
                        slot.title,
                        style: TextStyle(
                          color: isSelected ? Colors.greenAccent : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'ACTIVE',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Text(slot.description, style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    const SizedBox(height: 2),
                    Text('Cluster Tachometer Indication: ${slot.clusterTachRpm} RPM', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                  ],
                ),
                trailing: isSelected
                    ? const Icon(Icons.check, color: Colors.greenAccent)
                    : OutlinedButton(
                        onPressed: _isSlotSwitching ? null : () => _switchSlot(slot),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.greenAccent,
                          side: const BorderSide(color: Colors.greenAccent),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        ),
                        child: const Text('Switch', style: TextStyle(fontSize: 12)),
                      ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 16),

        // Tachometer Cluster Needle Visualizer Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.speed, color: Colors.cyanAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Cluster Tachometer Slot Indication',
                      style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '$_tachometerRpm RPM',
                    style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Stack(
                children: [
                  Container(
                    height: 16,
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (_tachometerRpm / 7000.0).clamp(0.05, 1.0),
                    child: Container(
                      height: 16,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.cyanAccent, Colors.greenAccent],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('0', style: TextStyle(color: Colors.white38, fontSize: 11)),
                  Text('1K (Slot 1)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('2K (Slot 2)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('3K (Slot 3)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('4K (Slot 4)', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  Text('7K', style: TextStyle(color: Colors.white38, fontSize: 11)),
                ],
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: _isResTriggering ? null : _triggerCruiseResNeedle,
                icon: const Icon(Icons.radio_button_checked, size: 18, color: Colors.black),
                label: Text(
                  _isResTriggering ? 'Simulating RES Button...' : 'Trigger Steering Wheel Cruise "RES" Button',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.cyanAccent,
                  minimumSize: const Size(double.infinity, 42),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 1. ROLLING ANTI-LAG (RAL) CARD
        _buildSectionHeader('Rolling Anti-Lag (RAL) - Cruise Rocker / RES', Icons.local_fire_department),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _options.antiLag.enabled ? Colors.orangeAccent.withValues(alpha: 0.5) : Colors.white12,
            ),
          ),
          child: Column(
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
                    child: const Icon(Icons.local_fire_department, color: Colors.orangeAccent, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Rolling Anti-Lag (Boost On Cruise Rocker)',
                          style: TextStyle(
                            color: _options.antiLag.enabled ? Colors.orangeAccent : Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Hold Cruise Rocker UP or RES with pedal >85% while rolling',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _options.antiLag.enabled,
                    activeColor: Colors.orangeAccent,
                    onChanged: (val) => setState(() => _options.antiLag.enabled = val),
                  ),
                ],
              ),
              if (_options.antiLag.enabled) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Boost Target Pressure:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_options.antiLag.boostTargetPsi.toStringAsFixed(1)} PSI',
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Slider(
                  value: _options.antiLag.boostTargetPsi,
                  min: 10.0,
                  max: 20.0,
                  divisions: 20,
                  activeColor: Colors.orangeAccent,
                  onChanged: (val) => setState(() => _options.antiLag.boostTargetPsi = val),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Max Duration (Thermal Safety):', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_options.antiLag.maxDurationSeconds.toStringAsFixed(1)} sec',
                      style: const TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Slider(
                  value: _options.antiLag.maxDurationSeconds,
                  min: 1.0,
                  max: 5.0,
                  divisions: 40,
                  activeColor: Colors.orangeAccent,
                  onChanged: (val) => setState(() => _options.antiLag.maxDurationSeconds = val),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ignition Angle Retard:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_options.antiLag.ignitionRetardDeg.toStringAsFixed(1)}° ATDC',
                      style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Slider(
                  value: _options.antiLag.ignitionRetardDeg,
                  min: -20.0,
                  max: -10.0,
                  divisions: 20,
                  activeColor: Colors.redAccent,
                  onChanged: (val) => setState(() => _options.antiLag.ignitionRetardDeg = val),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _isAntiLagTriggering ? null : _triggerAntiLagLive,
                        icon: const Icon(Icons.flash_on, size: 16, color: Colors.black),
                        label: Text(
                          _isAntiLagTriggering ? 'Building Boost...' : 'Trigger Anti-Lag Live',
                          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orangeAccent,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saveAntiLagDmeRam,
                        icon: const Icon(Icons.save, size: 16, color: Colors.orangeAccent),
                        label: const Text('Save RAM (0xD420)', style: TextStyle(color: Colors.orangeAccent, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.orangeAccent),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // FlexFuel Live Monitoring Card
        _buildSectionHeader('FlexFuel Live Blend (CAN 0x4F0 / DID 0xD410)', Icons.local_gas_station),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amberAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'E${_flexFuelData.ethanolPercent.toInt()}',
                          style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${_flexFuelData.ethanolPercent.toStringAsFixed(1)}% Ethanol Content',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: _isFlexFuelLoading
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent))
                        : const Icon(Icons.refresh, color: Colors.greenAccent),
                    onPressed: _isFlexFuelLoading ? null : _refreshFlexFuel,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (_flexFuelData.ethanolPercent / 100.0).clamp(0.0, 1.0),
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.amberAccent),
                minHeight: 10,
                borderRadius: BorderRadius.circular(5),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildMetricTile(
                    label: 'Fuel Temp',
                    value: '${_flexFuelData.fuelTempCelsius.toStringAsFixed(0)} °C',
                    icon: Icons.thermostat,
                    color: Colors.cyanAccent,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricTile(
                    label: 'Boost Scalar',
                    value: '${_flexFuelData.boostScalar.toStringAsFixed(2)}x',
                    icon: Icons.speed,
                    color: Colors.orangeAccent,
                  ),
                  const SizedBox(width: 10),
                  _buildMetricTile(
                    label: 'Timing Advance',
                    value: '+${_flexFuelData.timingAdvanceDeg.toStringAsFixed(1)}°',
                    icon: Icons.electric_bolt,
                    color: Colors.greenAccent,
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Knock CEL Alert Notification Tester Card
        _buildSectionHeader('Knock CEL Alert (Live Speedometer Notification)', Icons.warning_amber),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bolt, color: Colors.amberAccent, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Detonation / Knock Warning',
                      style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '>${_options.knockCel.timingThresholdDeg.toStringAsFixed(1)}° Retard',
                      style: const TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Flashes Check Engine Light on the speedometer in real time when DME detects ignition retard due to knock.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _isTestingCel ? null : _testKnockCelFlash,
                icon: const Icon(Icons.warning, size: 16, color: Colors.black),
                label: Text(
                  _isTestingCel ? 'Flashing CEL on Kombi...' : 'Test Knock CEL Warning Pulse (Cluster 0x60)',
                  style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amberAccent,
                  minimumSize: const Size(double.infinity, 38),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Anti-Theft Kill Switch Card
        _buildSectionHeader('Anti-Theft Kill Switch (0% Injector / Starter Cut)', Icons.security),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _isAntiTheftArmed ? Colors.redAccent.withValues(alpha: 0.6) : Colors.white12,
              width: _isAntiTheftArmed ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _isAntiTheftArmed
                          ? Colors.redAccent.withValues(alpha: 0.2)
                          : Colors.greenAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isAntiTheftArmed ? Icons.lock : Icons.lock_open,
                      color: _isAntiTheftArmed ? Colors.redAccent : Colors.greenAccent,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isAntiTheftArmed ? 'ANTI-THEFT ARMED' : 'ANTI-THEFT DISARMED',
                          style: TextStyle(
                            color: _isAntiTheftArmed ? Colors.redAccent : Colors.greenAccent,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isAntiTheftArmed
                              ? 'DME injector pulse width is set to 0% and starter relay is locked.'
                              : 'Engine starts normally. Arming will inhibit fuel injection & starter relay.',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isAntiTheftLoading ? null : _toggleAntiTheft,
                icon: Icon(
                  _isAntiTheftArmed ? Icons.key : Icons.security,
                  size: 18,
                  color: Colors.white,
                ),
                label: Text(
                  _isAntiTheftLoading
                      ? 'Processing UDS Command...'
                      : (_isAntiTheftArmed ? 'Disarm with Steering Wheel PIN' : 'Arm Anti-Theft Kill Switch'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isAntiTheftArmed ? Colors.green.shade800 : Colors.red.shade900,
                  minimumSize: const Size(double.infinity, 44),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  // ==========================================
  // TAB 2: OTS FLASH TUNING & ADVANCED CALIBRATION
  // ==========================================

  Widget _buildFlashCalibrationTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 1. OTS Map Stage Selection
        _buildSectionHeader('1. Calibration Map Stage', Icons.speed),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: OtsMapStage.values.map((stage) {
              final isSelected = _options.stage == stage;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Radio<OtsMapStage>(
                  value: stage,
                  groupValue: _options.stage,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) {
                    if (val != null) setState(() => _options.stage = val);
                  },
                ),
                title: Text(
                  stage.title,
                  style: TextStyle(
                    color: isSelected ? Colors.greenAccent : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  stage.requirement,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () => setState(() => _options.stage = stage),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 20),

        // 2. Cooling Target Mode Selection (Water Temp Reduction)
        _buildSectionHeader('2. Coolant Target Temp (Sport Cooling)', Icons.thermostat),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lowers the DME electronic thermostat map target to preserve oil quality and reduce under-hood thermal stress.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Row(
                children: CoolingTargetMode.values.map((mode) {
                  final isSelected = _options.coolingMode == mode;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () => setState(() => _options.coolingMode = mode),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.greenAccent.withValues(alpha: 0.15) : Colors.white10,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected ? Colors.greenAccent : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${mode.targetTempCelsius}°C',
                                style: TextStyle(
                                  color: isSelected ? Colors.greenAccent : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                mode.name.toUpperCase(),
                                style: TextStyle(
                                  color: isSelected ? Colors.greenAccent : Colors.white60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
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

        const SizedBox(height: 20),

        // 3. Exhaust Burble Configurator
        _buildSectionHeader('3. Exhaust Burble & Acoustics', Icons.music_note),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Aggressiveness Level', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: BurbleAggressiveness.values.map((aggro) {
                  final isSelected = _options.burbleAggressiveness == aggro;
                  return ChoiceChip(
                    label: Text(aggro.label),
                    selected: isSelected,
                    selectedColor: Colors.greenAccent,
                    backgroundColor: Colors.white10,
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) setState(() => _options.burbleAggressiveness = aggro);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                'Base Overrun Duration: ${_options.burbleDurationSeconds.toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Slider(
                value: _options.burbleDurationSeconds,
                min: 0.0,
                max: 2.5,
                divisions: 25,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.burbleDurationSeconds = val),
              ),
              Text(
                'Sport Mode Overrun Duration: ${_options.sportBurbleDurationSeconds.toStringAsFixed(1)}s',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              Slider(
                value: _options.sportBurbleDurationSeconds,
                min: 0.0,
                max: 2.5,
                divisions: 25,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.sportBurbleDurationSeconds = val),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Burble Min RPM Threshold:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${_options.burbleMinRpm} RPM', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _options.burbleMinRpm.toDouble(),
                min: 1000,
                max: 3000,
                divisions: 20,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.burbleMinRpm = val.toInt()),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Burble Max RPM Ceiling:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('${_options.burbleMaxRpm} RPM', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: _options.burbleMaxRpm.toDouble(),
                min: 3500,
                max: 7500,
                divisions: 40,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.burbleMaxRpm = val.toInt()),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 4. HPFP FLOW SCALING PROFILES
        _buildSectionHeader('4. HPFP Flow Scaling Profiles', Icons.local_gas_station),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Configures DME pump volume scalar (KL_KRS) and max rail pressure limit (PRMAX) for upgraded DI fuel pumps.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<HpfpProfile>(
                    value: _options.hpfp,
                    dropdownColor: const Color(0xFF161B22),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.greenAccent),
                    items: HpfpProfile.values.map((hpfp) {
                      return DropdownMenuItem<HpfpProfile>(
                        value: hpfp,
                        child: Text(
                          hpfp.label,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _options.hpfp = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Flow: ${_options.hpfp.flowScalar}x OEM',
                      style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Rail Limit: ${_options.hpfp.maxPressureBar} Bar',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _options.hpfp.description,
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 5. TMAP SENSOR SCALING MAPS
        _buildSectionHeader('5. TMAP Sensor Calibration Maps', Icons.sensors),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pressure sensor voltage-to-boost transfer function calibration for high boost applications.',
                style: TextStyle(color: Colors.white60, fontSize: 12),
              ),
              const SizedBox(height: 14),
              const Text('Manifold Pressure TMAP Sensor:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TmapSensorType>(
                    value: _options.manifoldTMAP,
                    dropdownColor: const Color(0xFF161B22),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                    items: TmapSensorType.values.map((sensor) {
                      return DropdownMenuItem<TmapSensorType>(
                        value: sensor,
                        child: Text(sensor.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _options.manifoldTMAP = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Curve: ${_options.manifoldTMAP.gradientKpaPerVolt} kPa/V (Offset: ${_options.manifoldTMAP.offsetKpa} kPa)',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
              ),
              const SizedBox(height: 14),
              const Text('Pre-Throttle (Chargepipe) TMAP Sensor:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TmapSensorType>(
                    value: _options.preThrottleTMAPSensor,
                    dropdownColor: const Color(0xFF161B22),
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down, color: Colors.cyanAccent),
                    items: TmapSensorType.values.map((sensor) {
                      return DropdownMenuItem<TmapSensorType>(
                        value: sensor,
                        child: Text(sensor.label, style: const TextStyle(color: Colors.white, fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setState(() => _options.preThrottleTMAPSensor = val);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Curve: ${_options.preThrottleTMAPSensor.gradientKpaPerVolt} kPa/V (Offset: ${_options.preThrottleTMAPSensor.offsetKpa} kPa)',
                style: const TextStyle(color: Colors.cyanAccent, fontSize: 11),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 6. BOOST & TORQUE BY GEAR (TRACTION MANAGEMENT)
        _buildSectionHeader('6. Boost & Torque By Gear (Traction Control)', Icons.linear_scale),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Enable Gear-Based Limiting', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _options.boostByGear.enabled,
                    activeColor: Colors.greenAccent,
                    onChanged: (val) => setState(() {
                      _options.boostByGear.enabled = val;
                      _options.torqueByGear.enabled = val;
                    }),
                  ),
                ],
              ),
              if (_options.boostByGear.enabled) ...[
                const SizedBox(height: 10),
                const Text('Select Transmission Gear (1st to 8th):', style: TextStyle(color: Colors.white60, fontSize: 12)),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: List.generate(8, (i) {
                      final isSelected = _selectedGearIndex == i;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text('Gear ${i + 1}'),
                          selected: isSelected,
                          selectedColor: Colors.greenAccent,
                          backgroundColor: Colors.white10,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.black : Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          onSelected: (val) {
                            if (val) setState(() => _selectedGearIndex = i);
                          },
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Gear ${_selectedGearIndex + 1} Boost Limit:', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_options.boostByGear.gearLimitsPsi[_selectedGearIndex].toStringAsFixed(1)} PSI',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Slider(
                  value: _options.boostByGear.gearLimitsPsi[_selectedGearIndex],
                  min: 10.0,
                  max: 30.0,
                  divisions: 40,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) {
                    setState(() => _options.boostByGear.gearLimitsPsi[_selectedGearIndex] = val);
                  },
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Gear ${_selectedGearIndex + 1} Torque Limit:', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    Text(
                      '${_options.torqueByGear.gearLimitsNm[_selectedGearIndex]} Nm',
                      style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ],
                ),
                Slider(
                  value: _options.torqueByGear.gearLimitsNm[_selectedGearIndex].toDouble(),
                  min: 300.0,
                  max: 1000.0,
                  divisions: 70,
                  activeColor: Colors.cyanAccent,
                  onChanged: (val) {
                    setState(() => _options.torqueByGear.gearLimitsNm[_selectedGearIndex] = val.toInt());
                  },
                ),
                const SizedBox(height: 10),
                // Overview of all 8 gears
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(8, (i) {
                      return Column(
                        children: [
                          Text('G${i + 1}', style: const TextStyle(color: Colors.white60, fontSize: 10)),
                          const SizedBox(height: 2),
                          Text(
                            '${_options.boostByGear.gearLimitsPsi[i].toInt()}',
                            style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '${_options.torqueByGear.gearLimitsNm[i]}',
                            style: const TextStyle(color: Colors.cyanAccent, fontSize: 9),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 7. GTS STARTUP ROAR / START BARK
        _buildSectionHeader('7. GTS Startup Roar / Start Bark', Icons.campaign),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('GTS Start Bark Feature', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _options.gtsStartupRoar.enabled,
                    activeColor: Colors.greenAccent,
                    onChanged: (val) => setState(() => _options.gtsStartupRoar.enabled = val),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Opens exhaust flap 100% and triggers ignition flare at crank transition for an aggressive exhaust bark.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (_options.gtsStartupRoar.enabled) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Roar Duration:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${_options.gtsStartupRoar.durationMs} ms', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _options.gtsStartupRoar.durationMs.toDouble(),
                  min: 300,
                  max: 1500,
                  divisions: 24,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) => setState(() => _options.gtsStartupRoar.durationMs = val.toInt()),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Flare Target RPM:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${_options.gtsStartupRoar.flareRpmTarget} RPM', style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _options.gtsStartupRoar.flareRpmTarget.toDouble(),
                  min: 1200,
                  max: 2200,
                  divisions: 20,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) => setState(() => _options.gtsStartupRoar.flareRpmTarget = val.toInt()),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 8. TRANSMISSION UPSHIFT SHIFT BRAP
        _buildSectionHeader('8. Transmission Upshift "Shift Brap" (ZF 8HP / M-DCT)', Icons.sports_motorsports),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('ZF / DCT Upshift Spark Cut', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _options.shiftBrap.enabled,
                    activeColor: Colors.deepOrangeAccent,
                    onChanged: (val) => setState(() => _options.shiftBrap.enabled = val),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Cuts ignition coils and retards spark during transmission gear change to produce motorsport BRAAP sound.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (_options.shiftBrap.enabled) ...[
                const SizedBox(height: 14),
                const Text('Aggressiveness Level:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [1, 2, 3].map((lvl) {
                    final isSel = _options.shiftBrap.aggressiveness == lvl;
                    final label = lvl == 1 ? 'Subtle' : (lvl == 2 ? 'Medium' : 'Aggressive');
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(label),
                        selected: isSel,
                        selectedColor: Colors.deepOrangeAccent,
                        backgroundColor: Colors.white10,
                        labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        onSelected: (val) {
                          if (val) setState(() => _options.shiftBrap.aggressiveness = lvl);
                        },
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Spark Cut Duration:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${_options.shiftBrap.durationMs} ms', style: const TextStyle(color: Colors.deepOrangeAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _options.shiftBrap.durationMs.toDouble(),
                  min: 50,
                  max: 250,
                  divisions: 20,
                  activeColor: Colors.deepOrangeAccent,
                  onChanged: (val) => setState(() => _options.shiftBrap.durationMs = val.toInt()),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: _isTestingShiftBrap ? null : _testShiftBrapLive,
                  icon: const Icon(Icons.flash_on, size: 16, color: Colors.deepOrangeAccent),
                  label: Text(
                    _isTestingShiftBrap ? 'Triggering...' : 'Test Shift Brap Spark Cut Pulse (UDS 0x31 0xD461)',
                    style: const TextStyle(color: Colors.deepOrangeAccent, fontSize: 12),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.deepOrangeAccent),
                    minimumSize: const Size(double.infinity, 36),
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 9. N55 WASTEGATE RATTLE FIX (PWG)
        _buildSectionHeader('9. Wastegate Rattle Fix (N55 PWG)', Icons.build),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Enable Wastegate Rattle Fix', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _options.wastegateRattleFix,
                    activeColor: Colors.greenAccent,
                    onChanged: (val) => setState(() => _options.wastegateRattleFix = val),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Adjusts pneumatic wastegate base PWM duty cycle offset to silence loose mechanical flapper rattle.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (_options.wastegateRattleFix) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('PWM Duty Cycle Offset:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text(
                      '${_options.wastegateDutyCycleOffsetPercent > 0 ? "+" : ""}${_options.wastegateDutyCycleOffsetPercent}%',
                      style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                Slider(
                  value: _options.wastegateDutyCycleOffsetPercent.toDouble(),
                  min: -20,
                  max: 20,
                  divisions: 40,
                  activeColor: Colors.greenAccent,
                  onChanged: (val) => setState(() => _options.wastegateDutyCycleOffsetPercent = val.toInt()),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('-20% (Less Rattle / Soft)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    Text('0% (OEM)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                    Text('+20% (Fast Spool)', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 10. KNOCK CEL ALERT NOTIFICATION TOGGLE
        _buildSectionHeader('10. Knock CEL Alert Notification', Icons.warning),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Speedometer Check Engine Blink', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _options.knockCel.enabled,
                    activeColor: Colors.amberAccent,
                    onChanged: (val) => setState(() => _options.knockCel.enabled = val),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Blinks the CEL on speedometer immediately when DME detects timing retard due to engine knock.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (_options.knockCel.enabled) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Ignition Retard Threshold:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('>${_options.knockCel.timingThresholdDeg.toStringAsFixed(1)}°', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: _options.knockCel.timingThresholdDeg,
                  min: 1.5,
                  max: 6.0,
                  divisions: 45,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) => setState(() => _options.knockCel.timingThresholdDeg = val),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 11. CATLESS DOWNPIPE CEL SUPPRESSION MASK
        _buildSectionHeader('11. Catless Downpipe CEL Suppression', Icons.shield),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Aftermarket Downpipe / Decat', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: _options.catlessSuppression.enabled,
                    activeColor: Colors.greenAccent,
                    onChanged: (val) => setState(() => _options.catlessSuppression.enabled = val),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Suppresses catalytic converter efficiency fault codes in the DME error memory mask vector.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (_options.catlessSuppression.enabled) ...[
                const SizedBox(height: 12),
                const Text('Suppressed Error Codes (CARB Mask):', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _options.catlessSuppression.suppressedCodes.map((dtc) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        dtc,
                        style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 12. Standard Flash Options & Toggles
        _buildSectionHeader('12. General ECU Calibration Toggles', Icons.settings),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Cold Start Cat Heating Off', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Disables loud & rough 1200 RPM cold idle startup sequence', style: TextStyle(color: Colors.white54, fontSize: 11)),
                value: _options.coldStartDisabled,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.coldStartDisabled = val),
              ),
              const Divider(color: Colors.white10),
              SwitchListTile(
                title: const Text('Top Speed Limiter Removal (VMAX)', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Removes 250 km/h factory governor (sets limit to 330 km/h)', style: TextStyle(color: Colors.white54, fontSize: 11)),
                value: _options.vmaxDisabled,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.vmaxDisabled = val),
              ),
              const Divider(color: Colors.white10),
              SwitchListTile(
                title: const Text('Linear Throttle Mapping', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Replaces progressive pedal map with precise 1:1 torque request', style: TextStyle(color: Colors.white54, fontSize: 11)),
                value: _options.linearThrottle,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.linearThrottle = val),
              ),
              const Divider(color: Colors.white10),
              SwitchListTile(
                title: const Text('Exhaust Flap Open in Sport Mode', style: TextStyle(color: Colors.white, fontSize: 14)),
                subtitle: const Text('Automatically opens exhaust valve whenever Sport/Sport+ is engaged', style: TextStyle(color: Colors.white54, fontSize: 11)),
                value: _options.exhaustFlapOpenInSport,
                activeColor: Colors.greenAccent,
                onChanged: (val) => setState(() => _options.exhaustFlapOpenInSport = val),
              ),
              const Divider(color: Colors.white10),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isWritingDmeOptions ? null : _writeDmeCustomOptionsLive,
                  icon: _isWritingDmeOptions
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                        )
                      : const Icon(Icons.bolt, size: 16, color: Colors.greenAccent),
                  label: Text(
                    _isWritingDmeOptions
                        ? 'Writing Custom Options to DME...'
                        : 'Fast Write Custom Options to DME (DIDs 0xD408-0xD40B)',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // 13. ZF 8HP / 6HP TRANSMISSION TUNING (TCU Transmission PARITY)
        _buildTcuTuningSection(),

        const SizedBox(height: 28),

        if (!FeatureFlags.kFlashEnabled) ...[
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent),
            ),
            child: const Row(
              children: [
                Icon(Icons.shield_outlined, color: Colors.redAccent, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ECU Flashing დროებით გამორთულია უსაფრთხოების რეჟიმით (HIL/bench ვერიფიკაციამდე)',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],

        // Flash Button
        ElevatedButton.icon(
          onPressed: _showFlashConfirmation,
          icon: const Icon(Icons.flash_on, color: Colors.black, size: 24),
          label: const Text(
            'Review & Flash DME Calibration',
            style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 2,
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ==========================================
  // ZF 8HP / 6HP TRANSMISSION TUNING (TCU Transmission PARITY)
  // ==========================================

  Widget _buildTcuTuningSection() {
    final tcu = _options.tcuOptions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('13. ZF 8HP / 6HP Transmission Calibration', Icons.speed),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header description & direct flash button
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amberAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.flash_on, color: Colors.amberAccent, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ZF 8HP / 6HP Transmission Calibration',
                          style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Advanced TCU calibration for ZF 8HP & 6HP gearboxes. Controls line pressure, custom launch, rev limiter hold, and shift profiles via UDS DID 0xD440 on EGS (ECU 0x18).',
                          style: TextStyle(color: Colors.white60, fontSize: 11, height: 1.3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Button to write directly to EGS 0x18
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isFlashingTcu ? null : _flashTcuOptionsToEgs,
                  icon: _isFlashingTcu
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                        )
                      : const Icon(Icons.bolt, size: 16, color: Colors.amberAccent),
                  label: Text(
                    _isFlashingTcu
                        ? 'Writing to EGS ECU 0x18...'
                        : 'Write TCU Options to EGS (UDS 0x18 / DID 0xD440)',
                    style: const TextStyle(color: Colors.amberAccent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.amberAccent),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 1. Shift Speed Profile Selector
              const Text('Shift Speed Profile:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TcuShiftSpeed.values.map((speed) {
                  final isSel = tcu.shiftSpeed == speed;
                  return ChoiceChip(
                    label: Text(speed.label),
                    selected: isSel,
                    selectedColor: Colors.amberAccent,
                    backgroundColor: Colors.white10,
                    labelStyle: TextStyle(
                      color: isSel ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() => _options.tcuOptions = tcu.copyWith(shiftSpeed: speed));
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 6),
              Text(
                tcu.shiftSpeed.description,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 2. Line Pressure Bump (19 Bar)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: const [
                    Expanded(
                      child: Text(
                        'Line Pressure Bump (19 Bar)',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(width: 6),
                    Text('(800+ Nm)', style: TextStyle(color: Colors.amberAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
                subtitle: const Text(
                  'Raises clutch clamping pressure to 19 Bar to prevent clutch slip on 800+ Nm high-torque builds.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.linePressureBump,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(linePressureBump: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 3. Custom Launch Control
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Custom Launch Control', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Switch(
                    value: tcu.customLaunchControlEnabled,
                    activeColor: Colors.amberAccent,
                    onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(customLaunchControlEnabled: val)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Custom launch control program with adjustable staging RPM, boost target, and torque punch bite.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              if (tcu.customLaunchControlEnabled) ...[
                const SizedBox(height: 14),
                // Launch RPM (2000 - 4500 RPM)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Launch RPM Target:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${tcu.launchRpm} RPM', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: tcu.launchRpm.toDouble(),
                  min: 2000,
                  max: 4500,
                  divisions: 50,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(launchRpm: val.round())),
                ),
                // Boost Target (0.0 - 20.0 PSI)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Launch Boost Target:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${tcu.launchBoostPsi.toStringAsFixed(1)} PSI', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: tcu.launchBoostPsi,
                  min: 0.0,
                  max: 20.0,
                  divisions: 40,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(launchBoostPsi: val)),
                ),
                // Torque Punch (1 - 5)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Torque Punch (Upshift Clamp Sharpness):', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('Level ${tcu.torquePunch} / 5', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [1, 2, 3, 4, 5].map((lvl) {
                    final isSel = tcu.torquePunch == lvl;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text('Lvl $lvl'),
                        selected: isSel,
                        selectedColor: Colors.amberAccent,
                        backgroundColor: Colors.white10,
                        labelStyle: TextStyle(
                          color: isSel ? Colors.black : Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                        onSelected: (val) {
                          if (val) setState(() => _options.tcuOptions = tcu.copyWith(torquePunch: lvl));
                        },
                      ),
                    );
                  }).toList(),
                ),
              ],

              const Divider(color: Colors.white12, height: 28),

              // 4. Kickdown Lockout in Manual Mode
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kickdown Lockout in Manual Mode', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Inhibits kickdown in M mode to prevent unwanted automatic downshifts during aggressive acceleration.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.kickdownManualDisabled,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(kickdownManualDisabled: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 5. 2nd Gear Take-Off
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('2nd Gear Take-Off (D & M Mode)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Launch in 2nd gear in D and M modes to maximize traction and eliminate wheelspin off the line.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.takeOffIn2ndGear,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(takeOffIn2ndGear: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 6. True Manual Mode (Rev Limiter Hold)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('True Manual Rev-Limiter Hold', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Prevents auto-upshifting at rev limiter in M mode, allowing the engine to hold and bounce at the hard cut limiter.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.trueManualMode,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(trueManualMode: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 7. Downshift Throttle Blips
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Downshift Throttle Blip %:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('${tcu.throttleBlipAggressiveness}%', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Adjusts rev-matching downshift throttle blip aggressiveness from 80% up to 150%.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              Slider(
                value: tcu.throttleBlipAggressiveness.toDouble(),
                min: 80,
                max: 150,
                divisions: 14,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(throttleBlipAggressiveness: val.round())),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 8. Kombi Gear Display
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Kombi Gear Display (D1..D8 / S1..S8)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Enables active D1..D8 and S1..S8 gear indication on instrument cluster in all driving modes.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.gearDisplayKombi,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(gearDisplayKombi: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 9. Max Shift RPM
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Max Shift RPM:', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  Text('${tcu.maxShiftRpm} RPM', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Extends full-throttle upshift points (6000 to 7500 RPM) to match raised engine rev limits.',
                style: TextStyle(color: Colors.white60, fontSize: 11),
              ),
              Slider(
                value: tcu.maxShiftRpm.toDouble(),
                min: 6000,
                max: 7500,
                divisions: 15,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(maxShiftRpm: val.round())),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 10. Torque Limiters Removal Per Gear
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Torque Limits Removal Per Gear', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Removes internal TCU torque limiters on 1st-8th gears for maximum torque transfer.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.torqueLimitsPerGearRemoved,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(torqueLimitsPerGearRemoved: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 11. Standstill Decoupling Disabled
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disable Standstill Decoupling', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Disables clutch drag decoupling at red lights for instant take-off response.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.standstillDecouplingDisabled,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(standstillDecouplingDisabled: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 12. Transmission Warmup Disabled
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Transmission Warmup Bypass', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Disables cold transmission warmup program that holds gears unnecessarily high when engine is cold.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.transmissionWarmupDisabled,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(transmissionWarmupDisabled: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 13. Drag Race Staging Mode
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Drag Race Staging Mode', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Optimizes clutch pre-fill and torque staging for drag strip launches.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.dragRaceMode,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(dragRaceMode: val)),
              ),
              if (tcu.dragRaceMode) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Staging RPM Threshold:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${tcu.dragRaceActivationThreshold} RPM', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: tcu.dragRaceActivationThreshold.toDouble(),
                  min: 2000,
                  max: 4500,
                  divisions: 50,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(dragRaceActivationThreshold: val.round())),
                ),
              ],

              const Divider(color: Colors.white12, height: 28),

              // 14. Brake Boost Protection
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Brake Boost Protection', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Allows 2-foot brake boosting off the line without DME torque reduction intervention.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.brakeBoostProtection,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(brakeBoostProtection: val)),
              ),
              if (tcu.brakeBoostProtection) ...[
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Allowed Brake Boost Target:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    Text('${tcu.brakeBoostProtectionValue.toStringAsFixed(1)} PSI', style: const TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                  ],
                ),
                Slider(
                  value: tcu.brakeBoostProtectionValue,
                  min: 5.0,
                  max: 25.0,
                  divisions: 40,
                  activeColor: Colors.amberAccent,
                  onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(brakeBoostProtectionValue: val)),
                ),
              ],

              const Divider(color: Colors.white12, height: 28),

              // 15. Coasting Mode Suppression
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Suppress Highway Coasting Mode', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Prevents transmission from disconnecting into neutral when coasting on highway for instant throttle response.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.coastingModeDisabled,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(coastingModeDisabled: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 16. Disable OBD Port Alarm
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Silence OBD Port Alarm', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Disables factory vehicle siren trigger when an OBD/ENET logger adapter remains plugged in after locking.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.disableObdAlarm,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(disableObdAlarm: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 17. Track / Dyno High-Temp Bypass
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Track / Dyno High-Temp Bypass', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Extends TCU transmission oil thermal intervention limit to prevent premature limp mode during track sessions.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.disableTempMonitoring,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(disableTempMonitoring: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 18. Custom Creep Suppression
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Disable Automatic Idle Crawl / Creep', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Vehicle remains completely stationary at a stop without having to hold the brake pedal.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.customCreepDisabled,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(customCreepDisabled: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 19. Valet Mode Transmission Lockout
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Valet Mode Transmission Lockout', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Locks gearbox to maximum 3rd gear and 3000 RPM ceiling to safeguard against abuse.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.valetModeEnabled,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(valetModeEnabled: val)),
              ),

              const Divider(color: Colors.white12, height: 28),

              // 20. Spark Cut Upshift (Ignition Cut Shifting)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ignition Cut Shifting (Motorsport Upshifts)', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text(
                  'Momentary spark cut during full-throttle upshifts for fastest possible gear changes and exhaust bark.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: tcu.ignitionCutShifting,
                activeColor: Colors.amberAccent,
                onChanged: (val) => setState(() => _options.tcuOptions = tcu.copyWith(ignitionCutShifting: val)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ==========================================
  // TAB 3: LIVE ACTUATORS (ZERO FLASH MEMORY WEAR)
  // ==========================================

  Widget _buildLiveActuatorsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.cyan.withValues(alpha: 0.3)),
          ),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.cyanAccent, size: 22),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Live Actuations control DME physical components via UDS Service 0x2F in real-time WITHOUT writing to flash memory.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.3),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Max Cooling Actuation Tile
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _maxCoolingActive ? Colors.cyanAccent.withValues(alpha: 0.5) : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _maxCoolingActive ? Colors.cyan.withValues(alpha: 0.2) : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.ac_unit,
                      color: _maxCoolingActive ? Colors.cyanAccent : Colors.white60,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Max Cooling Mode (Live Actuation)',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Forces electric water pump & radiator fan to 100% duty cycle for rapid cooldown on track or dyno.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _maxCoolingActive,
                    activeColor: Colors.cyanAccent,
                    onChanged: _isActuatorLoading ? null : (_) => _toggleMaxCooling(),
                  ),
                ],
              ),
              if (_maxCoolingActive) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.cyanAccent, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Kühlmittelpumpe (Water pump) & Fan running at 100%',
                        style: TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Exhaust Flap Control Tile
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _exhaustFlapOpen ? Colors.greenAccent.withValues(alpha: 0.5) : Colors.white12,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _exhaustFlapOpen ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.volume_up,
                      color: _exhaustFlapOpen ? Colors.greenAccent : Colors.white60,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Exhaust Flap Control (Abgasklappe)',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Lock exhaust flap 100% OPEN for maximum sound regardless of driving mode.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _exhaustFlapOpen,
                    activeColor: Colors.greenAccent,
                    onChanged: _isActuatorLoading ? null : (_) => _toggleExhaustFlap(),
                  ),
                ],
              ),
              if (_exhaustFlapOpen) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle, color: Colors.greenAccent, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'Exhaust valve locked OPEN (Maximum acoustics)',
                        style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Wastegate Duty Cycle Actuation
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_input_component, color: Colors.orangeAccent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Wastegate PWM Actuator (Live DC)',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Manual pneumatic wastegate solenoid control via UDS 0x2F 0xD022.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$_wastegateActuationDc%',
                    style: const TextStyle(color: Colors.orangeAccent, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Slider(
                value: _wastegateActuationDc.toDouble(),
                min: 0,
                max: 100,
                divisions: 20,
                activeColor: Colors.orangeAccent,
                onChanged: (val) => setState(() => _wastegateActuationDc = val.toInt()),
              ),
              ElevatedButton.icon(
                onPressed: _isActuatorLoading ? null : () => _actuateWastegateDutyCycle(_wastegateActuationDc),
                icon: const Icon(Icons.bolt, size: 16, color: Colors.black),
                label: const Text(
                  'Actuate Wastegate Solenoid Now',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, color: Colors.greenAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
