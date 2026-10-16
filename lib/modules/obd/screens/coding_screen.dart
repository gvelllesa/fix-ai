import 'dart:async';
import 'package:flutter/material.dart';
import '../services/protocols/enet_hsfz_protocol.dart';
import '../services/bmw_coding_service.dart';
import '../services/bmw_ecu_scanner.dart';
import '../widgets/advanced_connection_dialog.dart';
import '../widgets/slide_to_confirm.dart';
import '../widgets/link_status_bar.dart';

/// BMW 1-Tap FDL Cheat-Code Coding & Deep Diagnostics Screen
///
/// Ports BimmerGeeks ProTool and EDIABAS/PSDZData coding capabilities to FIX AI:
/// 1. 1-Tap FDL Cheat Codes (Start-Stop Memory, Folding Mirrors, Speedometer, VIM, etc.)
/// 2. Shadow Fault Memory (Infospeicher 0x19 0x04) with Environmental Freeze Frame extraction
/// 3. Pristine NCD Raw Coding Backups and 1-Tap Rollback
class CodingScreen extends StatefulWidget {
  final EnetHsfzProtocol? activeProtocol;

  const CodingScreen({super.key, this.activeProtocol});

  @override
  State<CodingScreen> createState() => _CodingScreenState();
}

class _CodingScreenState extends State<CodingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late BmwCodingService _service;

  bool _isConnected = false;
  double? _liveVoltage;
  String _detectedVin = 'Detecting...';
  bool _isBusy = false;
  String _busyMessage = '';
  double _busyProgress = 0.0;

  // Tab 1: Cheat Codes State
  List<FdlCheatCode> _cheatCodes = [];
  String _selectedCategory = 'All';
  String _cheatCodeSearchQuery = '';
  final TextEditingController _cheatCodeSearchController = TextEditingController();
  final Map<String, bool> _pendingToggleStates = {};

  // Tab 2: Vehicle Order (VO / FA) State
  BmwVehicleOrder? _vehicleOrder;
  bool _isLoadingVo = false;
  String _voSearchQuery = '';
  String _selectedVoCategory = 'All';
  List<VehicleOrderBackup> _voBackupsList = [];
  final Set<String> _pendingAddedOptions = {};
  final Set<String> _pendingRemovedOptions = {};
  final TextEditingController _voSearchController = TextEditingController();

  // Tab 3: Shadow Memory State
  List<ShadowDtcRecord> _shadowDtcList = [];
  bool _isShadowScanning = false;
  final Set<String> _expandedDtcKeys = {};

  // Tab 4: Backups State
  List<NcdBackup> _backupsList = [];
  bool _isLoadingBackups = false;

  // Dark Neon Theme Palette
  static const Color _bgDark = Color(0xFF0D1117);
  static const Color _cardDark = Color(0xFF161B22);
  static const Color _cardBorder = Color(0xFF30363D);
  static const Color _neonCyan = Color(0xFF00E5FF);
  static const Color _neonGreen = Color(0xFF00E676);
  static const Color _neonPurple = Color(0xFFD500F9);
  static const Color _neonAmber = Color(0xFFFFAB00);
  static const Color _neonRed = Color(0xFFFF5252);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _service = BmwCodingService(protocol: widget.activeProtocol);
    _cheatCodes = _service.getAvailableCheatCodes();
    for (final c in _cheatCodes) {
      _pendingToggleStates[c.id] = c.isCurrentlyActive;
    }

    _initializeVehicleLink();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _voSearchController.dispose();
    _cheatCodeSearchController.dispose();
    super.dispose();
  }

  Future<void> _initializeVehicleLink() async {
    final connected = await _service.ensureConnected();
    if (mounted) {
      setState(() => _isConnected = connected);
    }
    if (connected) {
      await _refreshVehicleVitals();
      await _loadBackups();
      await _loadVehicleOrder();
    }
  }

  Future<void> _refreshVehicleVitals() async {
    final volt = await _service.readBatteryVoltage();
    final vin = await _service.readVehicleVin();
    if (mounted) {
      setState(() {
        _liveVoltage = volt;
        if (vin != null && vin.isNotEmpty) {
          _detectedVin = vin;
        }
      });
    }
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoadingBackups = true);
    final list = await _service.getBackups();
    if (mounted) {
      setState(() {
        _backupsList = list;
        _isLoadingBackups = false;
      });
    }
  }

  // ==========================================================
  // Vehicle Order (VO / FA) Actions & Handlers
  // ==========================================================

  Future<void> _loadVehicleOrder() async {
    setState(() => _isLoadingVo = true);
    try {
      final vo = await _service.readVehicleOrder();
      final voBackups = await _service.getVoBackups();
      if (mounted) {
        setState(() {
          _vehicleOrder = vo;
          _voBackupsList = voBackups;
          _isLoadingVo = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingVo = false);
      }
      _showToast('Error loading Vehicle Order: $e', isError: true);
    }
  }

  void _addOptionToVo(String optionCode) {
    if (_vehicleOrder == null) return;
    final updated = _service.addCustomOption(_vehicleOrder!, optionCode);
    setState(() {
      _vehicleOrder = updated;
      final clean = optionCode.toUpperCase().startsWith(r'$')
          ? optionCode.toUpperCase()
          : '\$${optionCode.toUpperCase()}';
      _pendingAddedOptions.add(clean);
      _pendingRemovedOptions.remove(clean);
    });
    _showToast('Option $optionCode added to Vehicle Order.');
  }

  void _removeOptionFromVo(String optionCode) {
    if (_vehicleOrder == null) return;
    final updated = _service.removeOption(_vehicleOrder!, optionCode);
    setState(() {
      _vehicleOrder = updated;
      final clean = optionCode.toUpperCase().startsWith(r'$')
          ? optionCode.toUpperCase()
          : '\$${optionCode.toUpperCase()}';
      _pendingRemovedOptions.add(clean);
      _pendingAddedOptions.remove(clean);
    });
    _showToast('Option $optionCode removed from Vehicle Order.');
  }

  Future<void> _writeVoToVehicle() async {
    if (_vehicleOrder == null) return;

    final confirm = await _showVoSafetyDialog();
    if (confirm != true) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Writing Vehicle Order to CAS & FEM/BDC...';
      _busyProgress = 0.1;
    });

    try {
      final result = await _service.writeVehicleOrder(
        _vehicleOrder!,
        onProgress: (step, prog) {
          if (mounted) {
            setState(() {
              _busyMessage = step;
              _busyProgress = prog;
            });
          }
        },
      );

      if (result.success) {
        setState(() {
          _pendingAddedOptions.clear();
          _pendingRemovedOptions.clear();
        });
        await _loadVehicleOrder();
        _showSuccessDialog(result);
        _promptForFactoryDefaultCoding();
      } else {
        _showErrorDialog(result);
      }
    } catch (e) {
      _showToast('Error writing Vehicle Order: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  void _promptForFactoryDefaultCoding() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonPurple.withValues(alpha: 0.8)),
        ),
        title: const Row(
          children: [
            Icon(Icons.auto_fix_high, color: _neonPurple),
            SizedBox(width: 10),
            Text('Run Factory Default Coding?', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: const Text(
          'Vehicle Order has been saved to vehicle controllers. To activate the new options in all ECUs, Factory Default Coding (SG_CODIEREN) should be applied to affected modules.',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('LATER', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showFactoryDefaultCodingDialog();
            },
            style: ElevatedButton.styleFrom(backgroundColor: _neonPurple),
            child: const Text('DEFAULT CODE NOW', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showFactoryDefaultCodingDialog() async {
    if (_vehicleOrder == null) return;

    final optionsToConsider = (_pendingAddedOptions.isNotEmpty || _pendingRemovedOptions.isNotEmpty)
        ? [..._pendingAddedOptions, ..._pendingRemovedOptions]
        : _vehicleOrder!.options;

    final plans = _service.calculateFactoryCodingPlan(_vehicleOrder!, optionsToConsider);

    if (plans.isEmpty) {
      _showToast('No affected ECUs found for current options.');
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final volt = _liveVoltage;
            final isVoltageLow = volt != null && volt < 12.0;
            final anySelected = plans.any((p) => p.isSelected);

            return AlertDialog(
              backgroundColor: _cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _neonPurple.withValues(alpha: 0.8), width: 1.5),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _neonPurple.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.settings_suggest, color: _neonPurple, size: 24),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Factory Default Coding',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Select ECUs to calculate and flash factory default NCD parameters matching active Vehicle Order:',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 14),
                      ...plans.map((plan) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: _bgDark,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: plan.isSelected ? _neonPurple.withValues(alpha: 0.6) : Colors.white12,
                            ),
                          ),
                          child: CheckboxListTile(
                            value: plan.isSelected,
                            activeColor: _neonPurple,
                            checkColor: Colors.white,
                            onChanged: (val) {
                              setDialogState(() {
                                plan.isSelected = val ?? false;
                              });
                            },
                            title: Text(
                              plan.ecuName,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text(
                                  'Triggered by: ${plan.triggeredByOptions.join(", ")}',
                                  style: const TextStyle(color: _neonCyan, fontSize: 11, fontFamily: 'monospace'),
                                ),
                                Text(
                                  'Coding DID: 0x${plan.primaryDid.toRadixString(16).toUpperCase()}',
                                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
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
                              'Pre-Coding Checklist:',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            _buildSafetyItem('Ignition ON (Terminal 15 active)'),
                            _buildSafetyItem('Engine OFF'),
                            _buildSafetyItem(
                              'Voltage: ${volt != null ? "${volt.toStringAsFixed(2)}V" : "Monitoring active"}',
                              isWarning: isVoltageLow,
                            ),
                            _buildSafetyItem('Automatic NCD rollback backup will be created for each ECU'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton(
                  onPressed: anySelected
                      ? () {
                          Navigator.pop(dialogCtx);
                          _executeFactoryDefaultCoding(plans);
                        }
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _neonPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('START FACTORY CODING', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _executeFactoryDefaultCoding(List<FactoryCodingPlan> plans) async {
    if (_vehicleOrder == null) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Executing Factory Default Coding...';
      _busyProgress = 0.05;
    });

    try {
      final result = await _service.executeFactoryDefaultCoding(
        plans,
        _vehicleOrder!,
        onProgress: (step, prog) {
          if (mounted) {
            setState(() {
              _busyMessage = step;
              _busyProgress = prog;
            });
          }
        },
      );

      if (result.success) {
        _showSuccessDialog(result);
        await _scanVehicleCodingStatus();
      } else {
        _showErrorDialog(result);
      }
    } catch (e) {
      _showToast('Factory coding error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  Future<bool> _showVoSafetyDialog() async {
    final volt = _liveVoltage;
    final isVoltageLow = volt != null && volt < 12.0;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isVoltageLow ? _neonRed.withValues(alpha: 0.8) : _neonGreen.withValues(alpha: 0.8),
              width: 1.5,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isVoltageLow ? _neonRed : _neonGreen).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVoltageLow ? Icons.warning_rounded : Icons.save_alt,
                  color: isVoltageLow ? _neonRed : _neonGreen,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Write VO to Vehicle (res_saveVO)',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Target Modules: CAS & FEM/BDC (0x40 DID 0xFA01)',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  'Active Options: ${_vehicleOrder?.options.length ?? 0} SALAPA codes',
                  style: const TextStyle(color: _neonCyan, fontSize: 12, fontFamily: 'monospace'),
                ),
                const SizedBox(height: 12),
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
                        'Workshop Safety Checklist:',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildSafetyItem('Ignition ON (Terminal 15 active)'),
                      _buildSafetyItem('Engine OFF (Do not start engine during write)'),
                      _buildSafetyItem(
                        'Battery Voltage: ${volt != null ? "${volt.toStringAsFixed(2)}V" : "Monitoring active"}',
                        isWarning: isVoltageLow,
                      ),
                      _buildSafetyItem('Security access (0x27) unlock will be performed'),
                      _buildSafetyItem('Automatic Vehicle Order backup snapshot will be saved to disk'),
                    ],
                  ),
                ),
                if (isVoltageLow) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _neonRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: _neonRed.withValues(alpha: 0.4), width: 1),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.bolt, color: _neonRed, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: Low battery voltage (<12.0V). Connecting a 12V charger is mandatory to prevent CAS flash failure.',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SlideToConfirm(
                    label: 'SLIDE TO WRITE VO TO CAS/FEM',
                    confirmedLabel: 'VO WRITE AUTHORIZED',
                    sliderColor: _neonGreen,
                    icon: Icons.save_alt,
                    isEnabled: !isVoltageLow,
                    onConfirmed: () => Navigator.pop(ctx, true),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _showAddOptionDialog() async {
    final customController = TextEditingController();
    final catalog = BmwCodingService.getSalapaCatalog();
    String filterText = '';
    String selectedCat = 'All';

    final popularRetrofits = [
      r'$2TB', r'$6NS', r'$5A1', r'$8S4', r'$609',
      r'$2VF', r'$322', r'$6WB', r'$3AG', r'$688',
    ];

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final activeOptions = _vehicleOrder?.options ?? [];
            final filteredCatalog = catalog.where((opt) {
              final matchesText = filterText.isEmpty ||
                  opt.code.toLowerCase().contains(filterText.toLowerCase()) ||
                  opt.name.toLowerCase().contains(filterText.toLowerCase()) ||
                  opt.description.toLowerCase().contains(filterText.toLowerCase());
              final matchesCat = selectedCat == 'All' || opt.category == selectedCat;
              return matchesText && matchesCat;
            }).toList();

            return AlertDialog(
              backgroundColor: _cardDark,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: _neonCyan.withValues(alpha: 0.6), width: 1.5),
              ),
              title: const Row(
                children: [
                  Icon(Icons.add_circle_outline, color: _neonCyan, size: 24),
                  SizedBox(width: 10),
                  Text('Add Vehicle Option (res_addCusVO)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              content: SizedBox(
                width: 520,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: customController,
                            onChanged: (val) => setDialogState(() {}),
                            style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                            decoration: InputDecoration(
                              labelText: 'Option Code (e.g. \$2TB, \$6NS, \$609)',
                              labelStyle: const TextStyle(color: Colors.white60, fontSize: 12),
                              hintText: r'$2TB',
                              hintStyle: const TextStyle(color: Colors.white30),
                              filled: true,
                              fillColor: _bgDark,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              prefixIcon: const Icon(Icons.code, color: _neonCyan, size: 20),
                            ),
                            textCapitalization: TextCapitalization.characters,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            final code = customController.text.trim();
                            if (code.isNotEmpty) {
                              _addOptionToVo(code);
                              Navigator.pop(dialogCtx);
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _neonCyan,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),

                    // Live Auto-complete Suggestions & Description from E-Sys SALAPA Dictionary
                    if (customController.text.trim().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Builder(
                        builder: (_) {
                          final input = customController.text.trim();
                          final exact = _service.lookupSalapaCode(input);
                          final liveMatches = _service.searchSalapaOptions(input).take(4).toList();

                          if (exact != null) {
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: _neonCyan.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _neonCyan.withValues(alpha: 0.6)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _neonCyan.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          exact.code,
                                          style: const TextStyle(color: _neonCyan, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          exact.name,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.white10,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          exact.category,
                                          style: const TextStyle(color: Colors.white70, fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    exact.description,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11, height: 1.3),
                                  ),
                                  if (exact.affectedEcus.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 4,
                                      runSpacing: 4,
                                      children: exact.affectedEcus.map((ecu) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: _neonPurple.withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                        child: Text(
                                          ecu,
                                          style: const TextStyle(color: _neonPurple, fontSize: 9, fontWeight: FontWeight.bold),
                                        ),
                                      )).toList(),
                                    ),
                                  ],
                                ],
                              ),
                            );
                          } else if (liveMatches.isNotEmpty) {
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _bgDark,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('E-Sys Suggestions (Tap to select):', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: liveMatches.map((opt) {
                                      return InkWell(
                                        onTap: () {
                                          customController.text = opt.code;
                                          setDialogState(() {});
                                        },
                                        borderRadius: BorderRadius.circular(6),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withValues(alpha: 0.06),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: _neonCyan.withValues(alpha: 0.4)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(opt.code, style: const TextStyle(color: _neonCyan, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
                                              const SizedBox(width: 6),
                                              Text(opt.name, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                            ],
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            return const SizedBox.shrink();
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('Popular BMW Retrofits:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: popularRetrofits.map((optCode) {
                        final isAlreadyAdded = activeOptions.contains(optCode);
                        final optMeta = _service.findSalapaOption(optCode);
                        return ActionChip(
                          backgroundColor: isAlreadyAdded ? _cardBorder : _neonCyan.withValues(alpha: 0.15),
                          side: BorderSide(color: isAlreadyAdded ? Colors.white24 : _neonCyan.withValues(alpha: 0.6)),
                          label: Text(
                            '$optCode ${optMeta?.name ?? ""}',
                            style: TextStyle(
                              color: isAlreadyAdded ? Colors.white38 : _neonCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: isAlreadyAdded
                              ? null
                              : () {
                                  _addOptionToVo(optCode);
                                  Navigator.pop(dialogCtx);
                                },
                        );
                      }).toList(),
                    ),
                    const Divider(color: Colors.white12, height: 20),
                    TextField(
                      onChanged: (val) => setDialogState(() => filterText = val),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Search catalog by code, name or description...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        isDense: true,
                        filled: true,
                        fillColor: _bgDark,
                        prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 18),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: filteredCatalog.isEmpty
                          ? const Center(
                              child: Text('No options matching search', style: TextStyle(color: Colors.white38, fontSize: 12)),
                            )
                          : ListView.builder(
                              itemCount: filteredCatalog.length,
                              itemBuilder: (c, idx) {
                                final opt = filteredCatalog[idx];
                                final isAdded = activeOptions.contains(opt.code);

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: _bgDark,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: isAdded ? _neonGreen.withValues(alpha: 0.4) : Colors.white12),
                                  ),
                                  child: ListTile(
                                    dense: true,
                                    leading: Text(
                                      opt.code,
                                      style: TextStyle(
                                        color: isAdded ? _neonGreen : _neonCyan,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        fontSize: 13,
                                      ),
                                    ),
                                    title: Text(opt.name, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(opt.description, style: const TextStyle(color: Colors.white60, fontSize: 10)),
                                        const SizedBox(height: 2),
                                        Text('ECUs: ${opt.affectedEcuNames.join(", ")}', style: const TextStyle(color: Colors.white38, fontSize: 9)),
                                      ],
                                    ),
                                    trailing: isAdded
                                        ? const Icon(Icons.check_circle, color: _neonGreen, size: 18)
                                        : IconButton(
                                            icon: const Icon(Icons.add, color: _neonCyan, size: 20),
                                            onPressed: () {
                                              _addOptionToVo(opt.code);
                                              Navigator.pop(dialogCtx);
                                            },
                                          ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditRawVoDialog() async {
    if (_vehicleOrder == null) return;

    final seriesCtrl = TextEditingController(text: _vehicleOrder!.series);
    final typeKeyCtrl = TextEditingController(text: _vehicleOrder!.typeKey);
    final dateCtrl = TextEditingController(text: _vehicleOrder!.productionDate);
    final paintCtrl = TextEditingController(text: _vehicleOrder!.paintCode);
    final uphCtrl = TextEditingController(text: _vehicleOrder!.upholsteryCode);
    final rawFaCtrl = TextEditingController(text: _vehicleOrder!.toFaString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonAmber.withValues(alpha: 0.8), width: 1.5),
        ),
        title: const Row(
          children: [
            Icon(Icons.edit_note, color: _neonAmber),
            SizedBox(width: 10),
            Text('Edit Raw Vehicle Order (res_editRawVO)', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: seriesCtrl,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(labelText: 'Series (e.g. F030)', labelStyle: TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: typeKeyCtrl,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(labelText: 'Type Key (e.g. 3B93)', labelStyle: TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(labelText: 'Date (MMYY e.g. 0315)', labelStyle: TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: paintCtrl,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(labelText: 'Paint (e.g. 475)', labelStyle: TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: uphCtrl,
                        style: const TextStyle(color: Colors.white, fontFamily: 'monospace'),
                        decoration: const InputDecoration(labelText: 'Upholstery (e.g. LCSW)', labelStyle: TextStyle(color: Colors.white60, fontSize: 12)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Complete FA String:', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                TextField(
                  controller: rawFaCtrl,
                  maxLines: 4,
                  style: const TextStyle(color: _neonCyan, fontSize: 12, fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _bgDark,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              final newVo = BmwVehicleOrder.fromFaString(
                rawFaCtrl.text.trim(),
                vin: _vehicleOrder!.vin,
              ).copyWith(
                series: seriesCtrl.text.trim(),
                typeKey: typeKeyCtrl.text.trim(),
                productionDate: dateCtrl.text.trim(),
                paintCode: paintCtrl.text.trim(),
                upholsteryCode: uphCtrl.text.trim(),
              );
              final fixed = _service.fixVehicleOrder(newVo);
              setState(() {
                _vehicleOrder = fixed.fixedVo;
              });
              Navigator.pop(ctx);
              _showToast('Raw Vehicle Order updated.');
            },
            style: ElevatedButton.styleFrom(backgroundColor: _neonAmber),
            child: const Text('APPLY CHANGES', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _runVoFix() {
    if (_vehicleOrder == null) return;
    final fixResult = _service.fixVehicleOrder(_vehicleOrder!);
    setState(() {
      _vehicleOrder = fixResult.fixedVo;
    });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonGreen.withValues(alpha: 0.8)),
        ),
        title: const Row(
          children: [
            Icon(Icons.verified, color: _neonGreen),
            SizedBox(width: 10),
            Text('VO Validation & Fix (res_VoFix)', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fixResult.wasModified
                  ? 'Vehicle Order syntax was inspected and corrected.'
                  : 'Vehicle Order passed all syntax and consistency checks with zero errors.',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (fixResult.fixesApplied.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Fixes Applied:', style: TextStyle(color: _neonGreen, fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 6),
              ...fixResult.fixesApplied.map((f) => Text('• $f', style: const TextStyle(color: Colors.white, fontSize: 11))),
            ],
            const SizedBox(height: 12),
            Text(
              'Total Options: ${fixResult.fixedVo.options.length} | Model: ${fixResult.fixedVo.modelName}',
              style: const TextStyle(color: _neonCyan, fontSize: 11, fontFamily: 'monospace'),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: _neonGreen),
            child: const Text('OK', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _showVoBackupsDialog() async {
    final backups = await _service.getVoBackups();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardDark,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (bottomCtx, setBottomState) => Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Vehicle Order Backups',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      if (_vehicleOrder != null) {
                        await _service.backupVehicleOrder(_vehicleOrder!);
                        setBottomState(() {});
                        _showToast('Manual VO backup snapshot created.');
                      }
                    },
                    icon: const Icon(Icons.add, size: 16, color: _neonCyan),
                    label: const Text('CREATE SNAPSHOT', style: TextStyle(color: _neonCyan, fontSize: 11)),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: backups.isEmpty
                    ? const Center(
                        child: Text('No saved Vehicle Order backups yet.', style: TextStyle(color: Colors.white38)),
                      )
                    : ListView.builder(
                        itemCount: backups.length,
                        itemBuilder: (c, idx) {
                          final b = backups[idx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _bgDark,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white12),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.history_edu, color: _neonCyan, size: 24),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${b.typeKey} (${b.options.length} options)',
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                      Text(
                                        'Date: ${b.timestamp.toLocal()}',
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                      ),
                                      Text(
                                        b.description,
                                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                ElevatedButton(
                                  onPressed: () async {
                                    Navigator.pop(bottomCtx);
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (alertCtx) => AlertDialog(
                                        backgroundColor: _cardDark,
                                        title: const Text('Restore VO Backup?', style: TextStyle(color: Colors.white)),
                                        content: Text('Restore vehicle order from ${b.timestamp.toLocal()} (${b.options.length} options)?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(alertCtx, false),
                                            child: const Text('CANCEL'),
                                          ),
                                          ElevatedButton(
                                            onPressed: () => Navigator.pop(alertCtx, true),
                                            child: const Text('RESTORE'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setState(() {
                                        _isBusy = true;
                                        _busyMessage = 'Restoring VO to vehicle...';
                                      });
                                      final res = await _service.restoreVehicleOrder(b);
                                      setState(() => _isBusy = false);
                                      if (res.success) {
                                        _showSuccessDialog(res);
                                        await _loadVehicleOrder();
                                      } else {
                                        _showErrorDialog(res);
                                      }
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _neonAmber,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  ),
                                  child: const Text('RESTORE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Scans live vehicle coding status for all cheat codes
  Future<void> _scanVehicleCodingStatus() async {
    if (_isBusy) return;
    setState(() {
      _isBusy = true;
      _busyMessage = 'Reading vehicle FDL coding data...';
      _busyProgress = 0.1;
    });

    try {
      final statuses = await _service.readAllCheatCodeStatuses();
      if (mounted) {
        setState(() {
          for (final code in _cheatCodes) {
            if (statuses.containsKey(code.id)) {
              code.isCurrentlyActive = statuses[code.id]!;
              _pendingToggleStates[code.id] = statuses[code.id]!;
            }
          }
        });
      }
      _showToast('Vehicle coding state read successfully');
    } catch (e) {
      _showToast('Error reading coding status: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// Safety confirmation dialog prior to writing coding parameters
  Future<bool> _showCodingSafetyDialog({
    required FdlCheatCode code,
    required bool enableTarget,
  }) async {
    final volt = _liveVoltage;
    final isVoltageLow = volt != null && volt < 12.0;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: _cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isVoltageLow
                  ? _neonRed.withValues(alpha: 0.8)
                  : _neonCyan.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isVoltageLow ? _neonRed : _neonCyan)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isVoltageLow ? Icons.warning_rounded : Icons.code_rounded,
                  color: isVoltageLow ? _neonRed : _neonCyan,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Confirm Coding: ${code.name}',
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
                  'Target Action: ${enableTarget ? "ACTIVATE" : "DEACTIVATE"}',
                  style: TextStyle(
                    color: enableTarget ? _neonGreen : Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Target ECU: ${code.targetEcuName} (DID 0x${code.did.toRadixString(16).toUpperCase()})',
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
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
                        'Workshop Safety Checklist:',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildSafetyItem('Ignition ON (Terminal 15 active)'),
                      _buildSafetyItem('Engine OFF (Do not start engine during write)'),
                      _buildSafetyItem(
                        'Battery Voltage: ${volt != null ? "${volt.toStringAsFixed(2)}V" : "Monitoring active"}',
                        isWarning: isVoltageLow,
                      ),
                      _buildSafetyItem('Automatic NCD raw backup will be created'),
                    ],
                  ),
                ),
                if (isVoltageLow) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: _neonRed.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: _neonRed.withValues(alpha: 0.4), width: 1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt, color: _neonRed, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Warning: Low battery voltage (<12.0V). Connecting a 12V charger is highly recommended before coding.',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: enableTarget ? _neonCyan : _cardBorder,
                foregroundColor: enableTarget ? Colors.black : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('PROCEED WITH CODING',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Widget _buildSafetyItem(String text, {bool isWarning = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.error_outline : Icons.check_circle_outline,
            size: 15,
            color: isWarning ? _neonRed : _neonGreen,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: isWarning ? _neonRed : Colors.white70,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Executes 1-Tap Cheat Coding
  Future<void> _executeCoding(FdlCheatCode code, bool targetState) async {
    final confirmed = await _showCodingSafetyDialog(
      code: code,
      enableTarget: targetState,
    );
    if (!confirmed) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Coding ${code.name}...';
      _busyProgress = 0.1;
    });

    try {
      final result = await _service.applyCheatCode(
        code,
        targetState,
        onProgress: (step, prog) {
          if (mounted) {
            setState(() {
              _busyMessage = step;
              _busyProgress = prog;
            });
          }
        },
      );

      if (result.success) {
        setState(() {
          code.isCurrentlyActive = targetState;
          _pendingToggleStates[code.id] = targetState;
        });
        await _loadBackups();
        _showSuccessDialog(result);
      } else {
        _showErrorDialog(result);
      }
    } catch (e) {
      _showToast('Coding error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
        _refreshVehicleVitals();
      }
    }
  }

  /// Scans Shadow Fault Memory (Infospeicher 0x19 0x04)
  Future<void> _scanShadowMemory() async {
    if (_isShadowScanning) return;
    setState(() {
      _isShadowScanning = true;
      _busyMessage = 'Scanning ECU Infospeicher & Freeze Frames...';
      _busyProgress = 0.1;
    });

    try {
      final records = await _service.scanShadowMemoryForAllEcus(
        onProgress: (ecuName, progress) {
          if (mounted) {
            setState(() {
              _busyMessage = 'Scanning Infospeicher: $ecuName';
              _busyProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _shadowDtcList = records;
        });
      }
      _showToast('Infospeicher scan completed. Found ${records.length} shadow faults.');
    } catch (e) {
      _showToast('Failed to scan Infospeicher: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isShadowScanning = false);
      }
    }
  }

  /// Clears Shadow Fault Memory with safety confirmation
  Future<void> _clearShadowMemory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonRed.withValues(alpha: 0.6)),
        ),
        title: Row(
          children: [
            Icon(Icons.delete_sweep, color: _neonRed),
            const SizedBox(width: 10),
            const Text('Clear Infospeicher', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'This will clear silent shadow memory fault logs across DME, EGS, DSC, FEM/BDC, and KOMBI (UDS 0x14 0xFF 0xFF 0xFF).',
          style: TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _neonRed),
            child: const Text('CLEAR ALL SHADOW DTCS',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Clearing Infospeicher on all ECUs...';
      _busyProgress = 0.3;
    });

    try {
      final cleared = await _service.clearAllShadowMemory();
      setState(() {
        _shadowDtcList.clear();
      });
      _showToast('Successfully cleared Infospeicher across $cleared ECUs.');
    } catch (e) {
      _showToast('Error clearing shadow memory: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// Restores pristine original NCD bytes from an NcdBackup (1-Tap Rollback)
  Future<void> _restoreOriginalBackup(NcdBackup backup) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonAmber.withValues(alpha: 0.8)),
        ),
        title: Row(
          children: [
            Icon(Icons.restore, color: _neonAmber),
            const SizedBox(width: 10),
            const Text('Rollback to Factory NCD',
                style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Module: ${backup.ecuName} (DID 0x${backup.did.toRadixString(16).toUpperCase()})',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 6),
            Text(
              'Backup Date: ${backup.timestamp.toLocal()}',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 6),
            Text(
              'Payload Size: ${backup.originalBytes.length} bytes original NCD',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 14),
            const Text(
              'This will overwrite current coding block with the pristine original bytes stored prior to coding.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _neonAmber),
            child: const Text('FLASH ORIGINAL NCD',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isBusy = true;
      _busyMessage = 'Restoring original NCD on ${backup.ecuName}...';
      _busyProgress = 0.2;
    });

    try {
      final result = await _service.restoreBackup(
        backup,
        onProgress: (step, prog) {
          if (mounted) {
            setState(() {
              _busyMessage = step;
              _busyProgress = prog;
            });
          }
        },
      );

      if (result.success) {
        _showToast(result.message);
        await _scanVehicleCodingStatus();
      } else {
        _showErrorDialog(result);
      }
    } catch (e) {
      _showToast('Restore error: $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isBusy = false);
      }
    }
  }

  /// Deletes backup
  Future<void> _deleteBackup(NcdBackup backup) async {
    final ok = await _service.deleteBackup(backup.id);
    if (ok) {
      setState(() {
        _backupsList.removeWhere((b) => b.id == backup.id);
      });
      _showToast('Backup deleted.');
    }
  }

  void _showSuccessDialog(CodingResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonGreen.withValues(alpha: 0.8)),
        ),
        title: Row(
          children: [
            Icon(Icons.check_circle, color: _neonGreen, size: 28),
            const SizedBox(width: 12),
            Text(result.title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (result.backupId != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _bgDark,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_clock, color: _neonGreen, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Rollback snapshot saved: ${result.backupId}',
                        style: const TextStyle(
                            color: Colors.white54,
                            fontFamily: 'monospace',
                            fontSize: 10),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: _neonGreen),
            child: const Text('DISMISS',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(CodingResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardDark,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _neonRed.withValues(alpha: 0.8)),
        ),
        title: Row(
          children: [
            Icon(Icons.error_outline, color: _neonRed, size: 28),
            const SizedBox(width: 12),
            Text(result.title, style: const TextStyle(color: Colors.white)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(result.message,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
            if (result.nrcDescription != null) ...[
              const SizedBox(height: 12),
              Text(
                'Diagnostic Error: ${result.nrcDescription}',
                style: TextStyle(
                    color: _neonRed,
                    fontWeight: FontWeight.bold,
                    fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CLOSE', style: TextStyle(color: Colors.white54)),
          ),
        ],
      ),
    );
  }

  void _showToast(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _neonRed : _cardDark,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgDark,
      appBar: AppBar(
        backgroundColor: _cardDark,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Flexible(
                  child: Text(
                    'BMW CODING',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: _neonPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _neonPurple.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: const Text(
                    'PROTOOL',
                    style: TextStyle(
                      color: _neonPurple,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'VIN: $_detectedVin | ${_liveVoltage != null ? "${_liveVoltage!.toStringAsFixed(1)}V" : "Active"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: _isConnected ? _neonGreen : Colors.white54,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              Icons.cable,
              color: _isConnected ? _neonGreen : Colors.white38,
            ),
            tooltip: 'Adapter Link Options',
            onPressed: () {
              showDialog(
                context: context,
                builder: (c) => const AdvancedConnectionDialog(),
              ).then((_) => _initializeVehicleLink());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Refresh Status',
            onPressed: () async {
              await _refreshVehicleVitals();
              await _scanVehicleCodingStatus();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _neonCyan,
          indicatorWeight: 3,
          labelColor: _neonCyan,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(
              icon: Icon(Icons.tune, size: 20),
              text: '1-Tap Cheat Codes',
            ),
            Tab(
              icon: Icon(Icons.directions_car, size: 20),
              text: 'Vehicle Order (VO / FA)',
            ),
            Tab(
              icon: Icon(Icons.history_toggle_off, size: 20),
              text: 'Shadow Memory',
            ),
            Tab(
              icon: Icon(Icons.backup, size: 20),
              text: 'Coding Backups',
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              LinkStatusBar(
                flashProgress: _isBusy && _busyProgress > 0 ? _busyProgress : null,
                flashStage: _isBusy ? _busyMessage : null,
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildCheatCodesTab(),
                    _buildVehicleOrderTab(),
                    _buildShadowMemoryTab(),
                    _buildBackupsTab(),
                  ],
                ),
              ),
            ],
          ),
          if (_isBusy || _isShadowScanning) _buildBusyOverlay(),
        ],
      ),
    );
  }

  // ==========================================================
  // TAB 1: 1-Tap Cheat Codes
  // ==========================================================
  Widget _buildCheatCodesTab() {
    final categories = [
      'All',
      'Lighting & Visibility',
      'Cockpit & Cluster',
      'Safety & Chimes',
      'Comfort & Convenience',
      'Infotainment & Media',
      'Drivetrain & Performance',
      'Engine & Start-Stop',
    ];

    final query = _cheatCodeSearchQuery.toLowerCase().trim();
    final filteredCodes = _cheatCodes.where((c) {
      final matchesCategory = _selectedCategory == 'All' || c.category == _selectedCategory;
      if (!matchesCategory) return false;
      if (query.isEmpty) return true;
      final didHex = '0x${c.did.toRadixString(16).toLowerCase()}';
      final secDidHex = c.secondaryDid != null ? '0x${c.secondaryDid!.toRadixString(16).toLowerCase()}' : '';
      return c.name.toLowerCase().contains(query) ||
          c.id.toLowerCase().contains(query) ||
          c.description.toLowerCase().contains(query) ||
          c.targetEcuName.toLowerCase().contains(query) ||
          (c.secondaryEcuName?.toLowerCase().contains(query) ?? false) ||
          c.category.toLowerCase().contains(query) ||
          didHex.contains(query) ||
          secDidHex.contains(query);
    }).toList();

    return Column(
      children: [
        // Top Toolbar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: _cardDark.withValues(alpha: 0.6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedCategory != 'All' || query.isNotEmpty
                      ? '${filteredCodes.length} of ${_cheatCodes.length} Cheat Codes'
                      : '${_cheatCodes.length} Cheat Codes Available',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (_selectedCategory != 'All' || query.isNotEmpty) ...[
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedCategory = 'All';
                      _cheatCodeSearchQuery = '';
                      _cheatCodeSearchController.clear();
                    });
                  },
                  icon: const Icon(Icons.clear_all, size: 16, color: _neonAmber),
                  label: const Text(
                    'Reset',
                    style: TextStyle(
                      color: _neonAmber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                onPressed: _scanVehicleCodingStatus,
                icon: const Icon(Icons.radar, size: 16, color: _neonCyan),
                label: const Text(
                  'Scan Vehicle Coding',
                  style: TextStyle(
                    color: _neonCyan,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _neonCyan.withValues(alpha: 0.6)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // Search Input Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: _bgDark,
          child: TextField(
            controller: _cheatCodeSearchController,
            onChanged: (val) {
              setState(() {
                _cheatCodeSearchQuery = val;
              });
            },
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search by name, ECU, DID, or description...',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
              isDense: true,
              filled: true,
              fillColor: _cardDark,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              prefixIcon: const Icon(Icons.search, color: _neonCyan, size: 20),
              suffixIcon: _cheatCodeSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                      onPressed: () {
                        setState(() {
                          _cheatCodeSearchQuery = '';
                          _cheatCodeSearchController.clear();
                        });
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _cardBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _cardBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _neonCyan, width: 1.5),
              ),
            ),
          ),
        ),

        // Category Filter Chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: categories.map((cat) {
              final isSelected = _selectedCategory == cat;
              final count = cat == 'All'
                  ? _cheatCodes.length
                  : _cheatCodes.where((c) => c.category == cat).length;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: ChoiceChip(
                  label: Text(
                    '$cat ($count)',
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white70,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: _neonCyan,
                  backgroundColor: _cardDark,
                  side: BorderSide(
                    color: isSelected ? _neonCyan : _cardBorder,
                  ),
                  onSelected: (val) {
                    if (val) setState(() => _selectedCategory = cat);
                  },
                ),
              );
            }).toList(),
          ),
        ),

        // Cheat Codes List / Empty State
        Expanded(
          child: filteredCodes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off, size: 54, color: Colors.white24),
                        const SizedBox(height: 14),
                        Text(
                          _cheatCodeSearchQuery.isNotEmpty
                              ? 'No cheat codes match "$_cheatCodeSearchQuery"'
                              : 'No cheat codes in "$_selectedCategory"',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Try adjusting your search terms or selecting another category.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _selectedCategory = 'All';
                              _cheatCodeSearchQuery = '';
                              _cheatCodeSearchController.clear();
                            });
                          },
                          icon: const Icon(Icons.filter_alt_off, size: 16, color: _neonCyan),
                          label: const Text('Reset All Filters', style: TextStyle(color: _neonCyan)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _neonCyan.withValues(alpha: 0.5)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: filteredCodes.length,
                  itemBuilder: (context, index) {
                    final code = filteredCodes[index];
                    return _buildCheatCodeCard(code);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCheatCodeCard(FdlCheatCode code) {
    final currentToggle = _pendingToggleStates[code.id] ?? code.isCurrentlyActive;
    final isModified = currentToggle != code.isCurrentlyActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isModified
              ? _neonAmber.withValues(alpha: 0.8)
              : currentToggle
                  ? _neonCyan.withValues(alpha: 0.4)
                  : _cardBorder,
          width: isModified ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Tags & Toggle Switch
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Category Chip
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          code.category,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Target ECU badge
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _neonPurple.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _neonPurple.withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          code.targetEcuName,
                          style: const TextStyle(
                            color: _neonPurple,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      if (code.secondaryEcuName != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _neonAmber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: _neonAmber.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: Text(
                            code.secondaryEcuName!,
                            style: const TextStyle(
                              color: _neonAmber,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Active/Disabled indicator and Switch
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      currentToggle ? 'ACTIVE' : 'DISABLED',
                      style: TextStyle(
                        color: currentToggle ? _neonGreen : Colors.white38,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Switch(
                      value: currentToggle,
                      activeThumbColor: _neonGreen,
                      activeTrackColor: _neonGreen.withValues(alpha: 0.3),
                      inactiveThumbColor: Colors.white38,
                      inactiveTrackColor: Colors.white12,
                      onChanged: (val) {
                        setState(() {
                          _pendingToggleStates[code.id] = val;
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            // Cheat Code Name
            Text(
              code.name,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),

            // Parameter identifier & DID
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Text(
                  code.id,
                  style: const TextStyle(
                    color: _neonCyan,
                    fontSize: 11,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '• DID 0x${code.did.toRadixString(16).toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                if (code.secondaryDid != null)
                  Text(
                    '• Sec DID 0x${code.secondaryDid!.toRadixString(16).toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white38,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),

            // Description
            Text(
              code.description,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                height: 1.35,
              ),
            ),

            const SizedBox(height: 12),

            // Action Button Row
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isModified)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _neonAmber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.edit, size: 12, color: _neonAmber),
                        SizedBox(width: 4),
                        Text(
                          'Pending Write',
                          style: TextStyle(
                            color: _neonAmber,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  const SizedBox.shrink(),
                ElevatedButton.icon(
                  onPressed: () => _executeCoding(code, currentToggle),
                  icon: const Icon(Icons.flash_on, size: 16),
                  label: Text(
                    'Code (${currentToggle ? "Enable" : "Disable"})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentToggle ? _neonGreen : _neonCyan,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // TAB 2: Vehicle Order (VO / FA) Manager
  // ==========================================================
  Widget _buildVehicleOrderTab() {
    if (_isLoadingVo && _vehicleOrder == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _neonCyan),
            SizedBox(height: 16),
            Text(
              'Reading Vehicle Order from CAS & FEM/BDC (DID 0xFA01)...',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_vehicleOrder == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_car_outlined, size: 48, color: Colors.white38),
            const SizedBox(height: 16),
            const Text(
              'Vehicle Order not loaded.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _loadVehicleOrder,
              icon: const Icon(Icons.refresh),
              label: const Text('Read Vehicle Order from Car'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _neonCyan,
                foregroundColor: Colors.black,
              ),
            ),
          ],
        ),
      );
    }

    final vo = _vehicleOrder!;
    final query = _voSearchQuery.toLowerCase().trim();

    final filteredOptions = vo.options.where((code) {
      final optMeta = _service.findSalapaOption(code);
      final matchesQuery = query.isEmpty ||
          code.toLowerCase().contains(query) ||
          (optMeta != null &&
              (optMeta.name.toLowerCase().contains(query) ||
                  optMeta.description.toLowerCase().contains(query)));
      final matchesCategory = _selectedVoCategory == 'All' ||
          (optMeta != null && optMeta.category == _selectedVoCategory);
      return matchesQuery && matchesCategory;
    }).toList();

    return RefreshIndicator(
      onRefresh: _loadVehicleOrder,
      color: _neonCyan,
      backgroundColor: _cardDark,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildVoIdentityHeader(vo),
          const SizedBox(height: 14),
          if (_pendingAddedOptions.isNotEmpty || _pendingRemovedOptions.isNotEmpty) ...[
            _buildVoPendingChangesBanner(),
            const SizedBox(height: 14),
          ],
          _buildVoActionToolbar(vo),
          const SizedBox(height: 14),
          _buildVoSearchBar(),
          const SizedBox(height: 8),
          _buildVoCategoryFilterChips(),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Active Options (${filteredOptions.length} of ${vo.options.length})',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Text(
                'Chassis: ${vo.series} | ${vo.modelName}',
                style: const TextStyle(
                  color: _neonCyan,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (filteredOptions.isEmpty)
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: _cardDark,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: const Center(
                child: Text(
                  'No option codes matching search or category filter.',
                  style: TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ),
            )
          else
            ...filteredOptions.map((code) => _buildVoOptionCard(code, vo)),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildVoIdentityHeader(BmwVehicleOrder vo) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _neonCyan.withValues(alpha: 0.5), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _neonCyan.withValues(alpha: 0.05),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _neonCyan.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.directions_car, color: _neonCyan, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          vo.modelName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _neonGreen.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _neonGreen.withValues(alpha: 0.6)),
                          ),
                          child: const Text(
                            'CAS / BDC MASTER',
                            style: TextStyle(
                              color: _neonGreen,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'VIN: ${vo.vin}  |  Chassis: ${vo.series}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 24),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildVoBadge('Type Key', '*${vo.typeKey}', _neonCyan),
              _buildVoBadge('Zeitkriterium', '#${vo.productionDate} (${vo.formattedDate})', _neonAmber),
              _buildVoBadge('Paint Code', '${vo.paintCode} (${vo.paintDescription})', Colors.white70),
              _buildVoBadge('Upholstery', '${vo.upholsteryCode} (${vo.upholsteryDescription})', Colors.white70),
              _buildVoBadge('Total SALAPA', '${vo.options.length} Elements', _neonPurple),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _loadVehicleOrder,
                icon: const Icon(Icons.refresh, size: 14, color: _neonCyan),
                label: const Text('Read from Car', style: TextStyle(color: _neonCyan, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _neonCyan.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showEditRawVoDialog,
                icon: const Icon(Icons.edit_note, size: 14, color: _neonAmber),
                label: const Text('Edit Raw FA', style: TextStyle(color: _neonAmber, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _neonAmber.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _runVoFix,
                icon: const Icon(Icons.verified, size: 14, color: _neonGreen),
                label: const Text('Verify & Fix (res_VoFix)', style: TextStyle(color: _neonGreen, fontSize: 11)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _neonGreen.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _showVoBackupsDialog,
                icon: const Icon(Icons.folder_zip, size: 14, color: Colors.white70),
                label: Text(
                  _voBackupsList.isEmpty ? 'VO Backups' : 'VO Backups (${_voBackupsList.length})',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVoBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _bgDark,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: const TextStyle(color: Colors.white38, fontSize: 10)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVoPendingChangesBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _neonAmber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _neonAmber.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: _neonAmber, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Pending Vehicle Order Changes',
                  style: TextStyle(
                    color: _neonAmber,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _pendingAddedOptions.clear();
                    _pendingRemovedOptions.clear();
                  });
                  _loadVehicleOrder();
                },
                child: const Text('DISCARD', style: TextStyle(color: Colors.white54, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_pendingAddedOptions.length} option(s) added (${_pendingAddedOptions.join(", ")}), ${_pendingRemovedOptions.length} option(s) removed (${_pendingRemovedOptions.join(", ")}). Flash VO to CAS & FEM/BDC, then execute Factory Default Coding to activate in vehicle ECUs.',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildVoActionToolbar(BmwVehicleOrder vo) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        ElevatedButton.icon(
          onPressed: _showAddOptionDialog,
          icon: const Icon(Icons.add_circle, size: 16),
          label: const Text(
            '+ Add Option Code',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _neonCyan,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _writeVoToVehicle,
          icon: const Icon(Icons.save_alt, size: 16),
          label: const Text(
            'Write VO to CAS & FEM/BDC',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _neonGreen,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _showFactoryDefaultCodingDialog,
          icon: const Icon(Icons.settings_suggest, size: 16),
          label: const Text(
            'Factory Default-Code Selected ECUs',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: _neonPurple,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildVoSearchBar() {
    return TextField(
      controller: _voSearchController,
      onChanged: (val) => setState(() => _voSearchQuery = val),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: 'Search active options by code or description (e.g. 2TB, Bluetooth, Fog)...',
        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: _cardDark,
        prefixIcon: const Icon(Icons.search, color: _neonCyan, size: 20),
        suffixIcon: _voSearchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear, color: Colors.white54, size: 18),
                onPressed: () {
                  _voSearchController.clear();
                  setState(() => _voSearchQuery = '');
                },
              )
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _neonCyan),
        ),
      ),
    );
  }

  Widget _buildVoCategoryFilterChips() {
    final categories = [
      'All',
      'Drivetrain & Performance',
      'Infotainment & Media',
      'Lighting & Visibility',
      'Comfort & Convenience',
      'Driver Assistance',
      'Chassis & Suspension',
      'Cockpit & Cluster',
      'Audio & Acoustics',
      'Interior & Styling',
      'Safety & Chimes',
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: categories.map((cat) {
          final isSelected = _selectedVoCategory == cat;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text(
                cat,
                style: TextStyle(
                  color: isSelected ? Colors.black : Colors.white70,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              selected: isSelected,
              selectedColor: _neonCyan,
              backgroundColor: _cardDark,
              side: BorderSide(color: isSelected ? _neonCyan : _cardBorder),
              onSelected: (val) {
                if (val) setState(() => _selectedVoCategory = cat);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoOptionCard(String code, BmwVehicleOrder vo) {
    final optMeta = _service.findSalapaOption(code);
    final isPendingAdd = _pendingAddedOptions.contains(code);
    final isPendingRemove = _pendingRemovedOptions.contains(code);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPendingAdd
              ? _neonGreen.withValues(alpha: 0.8)
              : (isPendingRemove ? _neonRed.withValues(alpha: 0.8) : _cardBorder),
          width: (isPendingAdd || isPendingRemove) ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: _bgDark,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _neonCyan.withValues(alpha: 0.4)),
            ),
            child: Text(
              code,
              style: const TextStyle(
                color: _neonCyan,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
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
                    Expanded(
                      child: Text(
                        optMeta?.name ?? 'BMW Option $code',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (isPendingAdd)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _neonGreen.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _neonGreen),
                        ),
                        child: const Text('NEW', style: TextStyle(color: _neonGreen, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    if (isPendingRemove)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _neonRed.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: _neonRed),
                        ),
                        child: const Text('QUEUED DELETE', style: TextStyle(color: _neonRed, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                if (optMeta != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    optMeta.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _bgDark,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          optMeta.category,
                          style: const TextStyle(color: Colors.white38, fontSize: 9),
                        ),
                      ),
                      ...optMeta.affectedEcuNames.map((ecu) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _neonPurple.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: _neonPurple.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            ecu,
                            style: const TextStyle(color: _neonPurple, fontSize: 9, fontWeight: FontWeight.bold),
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 20),
            tooltip: 'Remove Option',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (alertCtx) => AlertDialog(
                  backgroundColor: _cardDark,
                  title: Text('Remove $code?', style: const TextStyle(color: Colors.white, fontSize: 16)),
                  content: Text(
                    'Remove ${optMeta?.name ?? code} from Vehicle Order? Affected ECUs: ${optMeta?.affectedEcuNames.join(", ") ?? "CAS/FEM"}.',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(alertCtx, false),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(alertCtx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: _neonRed),
                      child: const Text('REMOVE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                _removeOptionFromVo(code);
              }
            },
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TAB 3: Shadow Memory & Freeze Frames
  // ==========================================================
  Widget _buildShadowMemoryTab() {
    return Column(
      children: [
        // Controls Banner
        Container(
          padding: const EdgeInsets.all(14),
          color: _cardDark.withValues(alpha: 0.8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'BMW Infospeicher (Shadow Memory)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Deep manufacturer shadow fault logs that do NOT illuminate Check Engine Light (UDS 0x19 0x04).',
                          style: TextStyle(color: Colors.white54, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isShadowScanning ? null : _scanShadowMemory,
                      icon: const Icon(Icons.radar, size: 18),
                      label: const Text('Scan Shadow Memory'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _neonCyan,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    onPressed: _shadowDtcList.isEmpty ? null : _clearShadowMemory,
                    icon: const Icon(Icons.delete_sweep, size: 18, color: _neonRed),
                    label: const Text('Clear',
                        style: TextStyle(color: _neonRed, fontWeight: FontWeight.bold)),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: _neonRed.withValues(alpha: 0.6)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Result Count Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: _bgDark,
          child: Row(
            children: [
              Icon(
                _shadowDtcList.isEmpty ? Icons.check_circle : Icons.warning_amber,
                size: 16,
                color: _shadowDtcList.isEmpty ? _neonGreen : _neonAmber,
              ),
              const SizedBox(width: 8),
              Text(
                _shadowDtcList.isEmpty
                    ? 'No shadow DTCs detected in memory'
                    : '${_shadowDtcList.length} Silent Shadow DTCs Logged in Infospeicher',
                style: TextStyle(
                  color: _shadowDtcList.isEmpty ? _neonGreen : _neonAmber,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // Shadow DTC List
        Expanded(
          child: _shadowDtcList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.memory_outlined,
                          size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      const Text(
                        'Infospeicher is Clean or Unscanned',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Tap "Scan Shadow Memory" to extract silent DME/EGS/DSC shadow codes.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  itemCount: _shadowDtcList.length,
                  itemBuilder: (context, index) {
                    final item = _shadowDtcList[index];
                    return _buildShadowDtcCard(item);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShadowDtcCard(ShadowDtcRecord record) {
    final key = '${record.ecuAddress}_${record.hexCode}';
    final isExpanded = _expandedDtcKeys.contains(key);
    final ff = record.freezeFrame;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _neonAmber.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            title: Row(
              children: [
                // DTC Hex badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _neonAmber.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _neonAmber.withValues(alpha: 0.6),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    record.hexCode,
                    style: const TextStyle(
                      color: _neonAmber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  record.standardDtc,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                // ECU badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _neonPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    record.ecuName,
                    style: const TextStyle(
                      color: _neonPurple,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          record.statusDescription,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 10),
                        ),
                      ),
                      if (ff != null && ff.mileageKm != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          'Freeze: ${ff.mileageKm} km',
                          style: const TextStyle(
                              color: _neonCyan,
                              fontSize: 11,
                              fontFamily: 'monospace'),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            trailing: IconButton(
              icon: Icon(
                isExpanded ? Icons.expand_less : Icons.expand_more,
                color: Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  if (isExpanded) {
                    _expandedDtcKeys.remove(key);
                  } else {
                    _expandedDtcKeys.add(key);
                  }
                });
              },
            ),
          ),

          // Expandable Freeze Frame Details
          if (isExpanded) ...[
            const Divider(color: _cardBorder, height: 1),
            Container(
              padding: const EdgeInsets.all(14),
              color: _bgDark.withValues(alpha: 0.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.camera_alt_outlined,
                          size: 16, color: _neonCyan),
                      const SizedBox(width: 8),
                      const Text(
                        'Extended Environmental Freeze Frame Snapshot (0x19 0x04):',
                        style: TextStyle(
                          color: _neonCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (ff == null ||
                      (ff.mileageKm == null &&
                          ff.engineRpm == null &&
                          ff.coolantTempC == null)) ...[
                    const Text(
                      'No specific snapshot environment record returned by ECU for this shadow entry.',
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ] else ...[
                    // Environmental Grid
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        if (ff.mileageKm != null)
                          _buildFreezeFrameMetric(
                              'Mileage', '${ff.mileageKm} km', Icons.route),
                        if (ff.engineRpm != null)
                          _buildFreezeFrameMetric(
                              'Engine RPM', '${ff.engineRpm} RPM', Icons.speed),
                        if (ff.coolantTempC != null)
                          _buildFreezeFrameMetric(
                              'Coolant Temp',
                              '${ff.coolantTempC!.toStringAsFixed(1)} °C',
                              Icons.thermostat),
                        if (ff.railPressureBar != null)
                          _buildFreezeFrameMetric(
                              'Rail Pressure',
                              '${ff.railPressureBar!.toStringAsFixed(1)} bar',
                              Icons.compress),
                        if (ff.batteryVoltage != null)
                          _buildFreezeFrameMetric(
                              'Voltage',
                              '${ff.batteryVoltage!.toStringAsFixed(2)} V',
                              Icons.battery_charging_full),
                        if (ff.faultFrequency != null)
                          _buildFreezeFrameMetric('Frequency',
                              '${ff.faultFrequency} times', Icons.repeat),
                      ],
                    ),
                  ],

                  if (ff != null && ff.rawSnapshotBytes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'Raw Snapshot Frame Dump:',
                      style: TextStyle(color: Colors.white38, fontSize: 10),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _cardDark,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        ff.rawSnapshotBytes
                            .map((b) => b
                                .toRadixString(16)
                                .toUpperCase()
                                .padLeft(2, '0'))
                            .join(' '),
                        style: const TextStyle(
                          color: Colors.white60,
                          fontSize: 10,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFreezeFrameMetric(String label, String value, IconData icon) {
    return Container(
      width: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: _neonCyan),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(color: Colors.white54, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================================
  // TAB 3: Coding Backups & 1-Tap Rollback
  // ==========================================================
  Widget _buildBackupsTab() {
    if (_isLoadingBackups) {
      return const Center(child: CircularProgressIndicator(color: _neonCyan));
    }

    return Column(
      children: [
        // Backup Header
        Container(
          padding: const EdgeInsets.all(16),
          color: _cardDark.withValues(alpha: 0.6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NCD Raw Coding Backups',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_backupsList.length} Factory NCD snapshots saved on local device storage.',
                      style:
                          const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: _neonCyan),
                onPressed: _loadBackups,
              ),
            ],
          ),
        ),

        // Backups List
        Expanded(
          child: _backupsList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.backup_outlined,
                          size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      const Text(
                        'No NCD Backups Yet',
                        style: TextStyle(
                            color: Colors.white70,
                            fontWeight: FontWeight.bold,
                            fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'A factory NCD snapshot is automatically saved whenever you code a feature.',
                        style: TextStyle(color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _backupsList.length,
                  itemBuilder: (context, index) {
                    final backup = _backupsList[index];
                    return _buildBackupCard(backup);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildBackupCard(NcdBackup backup) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _cardDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Module badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _neonPurple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: _neonPurple.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    backup.ecuName,
                    style: const TextStyle(
                      color: _neonPurple,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'DID 0x${backup.did.toRadixString(16).toUpperCase()}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const Spacer(),
                Text(
                  '${backup.originalBytes.length} bytes',
                  style: const TextStyle(
                    color: _neonGreen,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.white38),
                  onPressed: () => _deleteBackup(backup),
                  tooltip: 'Delete Backup',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              backup.cheatCodeName,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              backup.description,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.white38),
                const SizedBox(width: 4),
                Text(
                  backup.timestamp.toLocal().toString().split('.').first,
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => _restoreOriginalBackup(backup),
                  icon: const Icon(Icons.restore, size: 16),
                  label: const Text('Restore Original (Rollback)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _neonAmber,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================
  // BUSY / PROGRESS MODAL OVERLAY
  // ==========================================================
  Widget _buildBusyOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.8),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 32),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: _cardDark,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _neonCyan.withValues(alpha: 0.6),
              width: 1.5,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(
                color: _neonCyan,
                strokeWidth: 3,
              ),
              const SizedBox(height: 20),
              Text(
                _busyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: _busyProgress,
                  backgroundColor: _bgDark,
                  color: _neonCyan,
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Communicating with BMW ECU over ENET/UDS...\nDo not disconnect adapter or cycle ignition.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
