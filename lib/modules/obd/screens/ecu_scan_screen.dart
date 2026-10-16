import 'package:flutter/material.dart';
import '../services/protocols/enet_hsfz_protocol.dart';
import '../services/bmw_ecu_scanner.dart';

class EcuScanScreen extends StatefulWidget {
  final EnetHsfzProtocol? activeProtocol;
  final String? initialVin;
  final String? initialChassis;
  final Function(List<String> faultCodes)? onSendToChat;

  const EcuScanScreen({
    super.key,
    this.activeProtocol,
    this.initialVin,
    this.initialChassis,
    this.onSendToChat,
  });

  @override
  State<EcuScanScreen> createState() => _EcuScanScreenState();
}

class _EcuScanScreenState extends State<EcuScanScreen> {
  static const Color bgColor = Color(0xFF121212);
  static const Color cardColor = Color(0xFF1E1E1E);
  static const Color neonGreen = Color(0xFF1DB954);
  static const Color alertRed = Color(0xFFE53935);
  static const Color amberColor = Color(0xFFFFB300);

  late EnetHsfzProtocol _protocol;
  bool _ownsProtocol = false;
  late BmwEcuScanner _scanner;

  bool _isScanning = false;
  bool _isClearing = false;
  String _scanStatus = 'Ready to scan';
  double _scanProgress = 0.0;

  DiagnosticScanResult? _scanResult;
  List<EcuInfo> _topology = [];
  String? _errorMessage;

  // Filter / Search for 32 modules
  String _searchQuery = '';
  String _filterCategory = 'ALL'; // ALL, FAULTY, ONLINE, OFFLINE

  @override
  void initState() {
    super.initState();
    if (widget.activeProtocol != null && widget.activeProtocol!.isConnected) {
      _protocol = widget.activeProtocol!;
      _ownsProtocol = false;
    } else {
      _protocol = EnetHsfzProtocol();
      _ownsProtocol = true;
    }
    _scanner = BmwEcuScanner(protocol: _protocol);
    _topology = BmwEcuScanner.getDefaultFSeriesTopology();

    // Proactively start scan
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startTopologyScan();
    });
  }

  @override
  void dispose() {
    if (_ownsProtocol) {
      _protocol.disconnect();
    }
    super.dispose();
  }

  Future<void> _startTopologyScan() async {
    if (_isScanning) return;

    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _scanStatus = 'Connecting to vehicle adapter...';
      _scanProgress = 0.05;
    });

    try {
      if (!_protocol.isConnected) {
        setState(() => _scanStatus = 'Detecting adapter (35000, 6801, 13400)...');
        final target = await _protocol.detectAdapter();
        if (target != null) {
          final ok = await _protocol.connect(
            host: target.host,
            port: target.port,
            useDoip: target.isDoip,
          );
          if (!ok) throw Exception('Adapter port ${target.port} connection rejected.');
        } else {
          // Attempt fast-path default directly
          final ok = await _protocol.connect(host: '192.168.16.101', port: 35000);
          if (!ok) {
            throw Exception('Vehicle not detected at 192.168.16.101 or broadcast. Check connection & ignition.');
          }
        }
      }

      setState(() => _scanStatus = 'Querying ECU Topology & Reading DTCs...');
      final result = await _scanner.performFullDiagnosticScan(
        onProgress: (stage, progress) {
          if (mounted) {
            setState(() {
              _scanStatus = stage;
              _scanProgress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _scanResult = result;
          _topology = result.ecuTopology;
          _isScanning = false;
          _scanProgress = 1.0;
          _scanStatus = 'Scan complete: ${result.totalFaults} faults across ${result.ecuTopology.where((e) => e.isResponding).length} modules';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _scanStatus = 'Scan failed';
        });
      }
    }
  }

  /// Clears fault codes specifically on an individual ECU (Single Clear)
  Future<void> _clearSingleEcu(EcuInfo ecu) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Clear DTCs on ${ecu.name}?',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'This will send UDS 0x14 0xFF 0xFF 0xFF specifically to ${ecu.name} (0x${ecu.address.toRadixString(16).toUpperCase()}).\nVehicle ignition must be ON.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: alertRed, foregroundColor: Colors.white),
            child: Text('CLEAR ${ecu.name} DTCs'),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Clearing fault codes on ${ecu.name}...'),
        duration: const Duration(seconds: 1),
      ),
    );

    try {
      final success = await _scanner.clearSingleEcuFaultCodes(ecu.address);
      if (mounted) {
        if (success) {
          setState(() {
            ecu.faultCodes.clear();
            ecu.shadowFaultCodes.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fault memory on ${ecu.name} cleared successfully.'),
              backgroundColor: neonGreen,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to clear ${ecu.name} DTCs. Check ignition & bus state.'),
              backgroundColor: alertRed,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error clearing ${ecu.name}: $e'),
            backgroundColor: alertRed,
          ),
        );
      }
    }
  }

  /// ISTA ECU Reset Control Dialog (ISO 14229 UDS Service 0x11 Reset Steuergerät)
  Future<void> _showEcuResetDialog(EcuInfo ecu) async {
    EcuResetType selectedReset = EcuResetType.hardReset;
    bool isResetting = false;

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              backgroundColor: cardColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.5)),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.restart_alt, color: Colors.orangeAccent, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RESET ${ecu.name}',
                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '0x${ecu.address.toRadixString(16).toUpperCase()} • UDS Service 0x11',
                          style: const TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'monospace'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'აირჩიეთ ECU-ს გადატვირთვის ტიპი (ISTA Reset Steuergerät):',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    ...EcuResetType.values.map((type) {
                      final isSelected = selectedReset == type;
                      return InkWell(
                        onTap: isResetting ? null : () => setDialogState(() => selectedReset = type),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Colors.orangeAccent.withValues(alpha: 0.12)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? Colors.orangeAccent : Colors.white12,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: isSelected ? Colors.orangeAccent : Colors.white38,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          type.label,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.white12,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            '0x0${type.subFunction}',
                                            style: const TextStyle(color: Colors.white70, fontSize: 10, fontFamily: 'monospace'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      type.description,
                                      style: const TextStyle(color: Colors.white54, fontSize: 11),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    if (isResetting) ...[
                      const SizedBox(height: 12),
                      const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orangeAccent),
                            ),
                            SizedBox(width: 10),
                            Text('გადატვირთვა მიმდინარეობს...', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isResetting ? null : () => Navigator.pop(ctx),
                  child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
                ),
                ElevatedButton.icon(
                  onPressed: isResetting
                      ? null
                      : () async {
                          setDialogState(() => isResetting = true);
                          final ok = await _scanner.resetControlUnit(ecu.address, selectedReset);
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                          }
                          if (mounted) {
                            if (ok) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('${ecu.name} successfully reset via UDS Service 0x11 (${selectedReset.label}).'),
                                  backgroundColor: neonGreen,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('ECU ${ecu.name} rejected reset (0x11 0x0${selectedReset.subFunction}). Check conditions.'),
                                  backgroundColor: alertRed,
                                ),
                              );
                            }
                          }
                        },
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text('RESET NOW'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Clears fault codes across all responding ECUs
  Future<void> _clearAllCodes() async {
    if (_scanResult == null || _isClearing) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear All Fault Codes?', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: const Text(
          'This will send UDS 0x14 0xFF 0xFF 0xFF to all responding ECUs. Ignition must be ON with engine OFF.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: alertRed, foregroundColor: Colors.white),
            child: const Text('CLEAR ALL DTCs'),
          ),
        ],
      ),
    );

    if (!mounted || confirm != true) return;

    setState(() {
      _isClearing = true;
      _scanStatus = 'Clearing DTCs across modules...';
    });

    try {
      final cleared = await _scanner.clearAllFaultCodes(_topology);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Cleared fault memory on $cleared responding ECUs.'),
            backgroundColor: neonGreen,
          ),
        );
        // Refresh scan to verify memory is clean
        await _startTopologyScan();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear DTCs: $e'), backgroundColor: alertRed),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isClearing = false);
      }
    }
  }

  /// Opens ECU Hardware & Software Identification modal (DIDs 0xF187..0xF190)
  Future<void> _showEcuInfoModal(EcuInfo ecu) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            bool isLoading = false;

            Future<void> loadIdentification() async {
              setModalState(() => isLoading = true);
              final id = await _scanner.readEcuIdentification(ecu.address, ecuName: ecu.name);
              if (mounted) {
                setState(() {
                  ecu.identification = id;
                });
                setModalState(() => isLoading = false);
              }
            }

            // Proactively trigger if not loaded and ecu is responding
            if (ecu.identification == null && !isLoading && ecu.isResponding) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                loadIdentification();
              });
            }

            final id = ecu.identification;

            return Container(
              height: MediaQuery.of(context).size.height * 0.75,
              decoration: const BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  ecu.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: neonGreen.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: neonGreen.withValues(alpha: 0.4)),
                                  ),
                                  child: Text(
                                    '0x${ecu.address.toRadixString(16).toUpperCase()}',
                                    style: const TextStyle(
                                      color: neonGreen,
                                      fontSize: 12,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              ecu.description,
                              style: const TextStyle(color: Colors.white60, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: neonGreen),
                        tooltip: 'Re-read DIDs',
                        onPressed: isLoading ? null : loadIdentification,
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  if (isLoading)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: neonGreen),
                            SizedBox(height: 16),
                            Text(
                              'Reading ECU DIDs (0xF187..0xF190)...',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (!ecu.isResponding)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.signal_cellular_connected_no_internet_0_bar, color: Colors.white38, size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'ECU is Offline',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'This module did not respond to session requests.\nIdentification cannot be retrieved.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (id == null)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: alertRed, size: 40),
                            const SizedBox(height: 12),
                            const Text(
                              'No identification data returned',
                              style: TextStyle(color: Colors.white, fontSize: 15),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: loadIdentification,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Try Again'),
                              style: ElevatedButton.styleFrom(backgroundColor: neonGreen, foregroundColor: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: [
                          _buildIdCard(
                            title: 'BMW Sachnummer (Part #)',
                            value: id.partNumber,
                            didHex: '0xF187',
                            icon: Icons.numbers_rounded,
                            subtitle: '7-Digit OEM Factory Hardware Part Number',
                          ),
                          _buildIdCard(
                            title: 'HWEL (Hardware Electronics)',
                            value: id.hwelVersion,
                            didHex: '0xF188',
                            icon: Icons.developer_board,
                            subtitle: 'Physical Hardware PCB & Microcontroller Revision',
                          ),
                          _buildIdCard(
                            title: 'SWFL (Software Application)',
                            value: id.swflVersion,
                            didHex: '0xF189',
                            icon: Icons.system_update_alt_rounded,
                            subtitle: 'Active Application Operating Software Version',
                          ),
                          _buildIdCard(
                            title: 'Codierindex (Coding Index)',
                            value: id.codingIndex,
                            didHex: '0xF18B',
                            icon: Icons.tune_rounded,
                            subtitle: 'Factory NCD Variant Coding Configuration Index',
                          ),
                          _buildIdCard(
                            title: 'Registered Vehicle VIN',
                            value: id.vin,
                            didHex: '0xF190',
                            icon: Icons.badge_outlined,
                            subtitle: 'Chassis VIN Stored Inside Non-Volatile Memory',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (ecu.isResponding)
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(ctx);
                              _clearSingleEcu(ecu);
                            },
                            icon: const Icon(Icons.delete_sweep, color: alertRed, size: 18),
                            label: Text('CLEAR ${ecu.name} DTCs', style: const TextStyle(color: alertRed)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: alertRed.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      if (ecu.isResponding) const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white12,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('CLOSE'),
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

  Widget _buildIdCard({
    required String title,
    required String value,
    required String didHex,
    required IconData icon,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: neonGreen, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(title, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        didHex,
                        style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Opens I/M Emissions Readiness dialog / modal
  Future<void> _showEmissionsReadinessModal() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            bool isLoading = false;
            EmissionsReadinessResult? currentResult;

            Future<void> queryReadiness() async {
              setModalState(() => isLoading = true);
              final result = await _scanner.readEmissionsReadiness(dmeAddress: 0x12);
              if (mounted) {
                setModalState(() {
                  currentResult = result;
                  isLoading = false;
                });
              }
            }

            // Trigger automatically upon opening
            if (currentResult == null && !isLoading) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                queryReadiness();
              });
            }

            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: const BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'I/M Emissions Readiness',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'OBD-II Mode 01 PID 01 / UDS DID 0xF401 • DME (0x12)',
                            style: TextStyle(color: Colors.white60, fontSize: 12),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: neonGreen),
                        tooltip: 'Re-query DME',
                        onPressed: isLoading ? null : queryReadiness,
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12, height: 24),
                  if (isLoading)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: neonGreen),
                            SizedBox(height: 16),
                            Text(
                              'Querying DME (0x12) Emissions Bitmask...',
                              style: TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (currentResult == null)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.sensors_off_rounded, color: alertRed, size: 48),
                            const SizedBox(height: 14),
                            const Text(
                              'No Response from DME',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Ensure vehicle ignition is ON (Engine OFF or Idling).\nAdapter must be connected to BMW ENET / OBD-II.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.white54, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: queryReadiness,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry Query'),
                              style: ElevatedButton.styleFrom(backgroundColor: neonGreen, foregroundColor: Colors.black),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        children: [
                          // Overall Banner
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: currentResult!.isReady
                                  ? neonGreen.withValues(alpha: 0.12)
                                  : alertRed.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: currentResult!.isReady ? neonGreen : alertRed,
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  currentResult!.isReady
                                      ? Icons.check_circle_rounded
                                      : Icons.warning_amber_rounded,
                                  color: currentResult!.isReady ? neonGreen : alertRed,
                                  size: 32,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        currentResult!.isReady
                                            ? 'READY FOR EMISSIONS TEST'
                                            : 'NOT READY FOR EMISSIONS TEST',
                                        style: TextStyle(
                                          color: currentResult!.isReady ? neonGreen : alertRed,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        currentResult!.isReady
                                            ? 'ყველა აქტიური მონიტორი წარმატებით დასრულებულია. MIL გამორთულია.'
                                            : 'ზოგიერთი მონიტორი დაუსრულებელია ან აღმოჩენილია აქტიური ხარვეზი.',
                                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Quick Status Metrics
                          Row(
                            children: [
                              _buildReadinessMetric(
                                label: 'MIL Status',
                                value: currentResult!.milOn ? 'MIL ON' : 'MIL OFF',
                                color: currentResult!.milOn ? alertRed : neonGreen,
                              ),
                              const SizedBox(width: 8),
                              _buildReadinessMetric(
                                label: 'Emissions DTCs',
                                value: '${currentResult!.dtcCount}',
                                color: currentResult!.dtcCount > 0 ? alertRed : neonGreen,
                              ),
                              const SizedBox(width: 8),
                              _buildReadinessMetric(
                                label: 'Passed',
                                value: '${currentResult!.passedCount}',
                                color: neonGreen,
                              ),
                              const SizedBox(width: 8),
                              _buildReadinessMetric(
                                label: 'Incomplete',
                                value: '${currentResult!.incompleteCount}',
                                color: currentResult!.incompleteCount > 0 ? amberColor : Colors.white38,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          const Text(
                            'EMISSIONS SYSTEM MONITORS',
                            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0),
                          ),
                          const SizedBox(height: 8),

                          // Monitors list
                          ...currentResult!.monitors.map((m) => _buildMonitorCard(m)),
                        ],
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

  Widget _buildReadinessMetric({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 10),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonitorCard(EmissionsMonitor monitor) {
    Color statusColor;
    String statusText;
    IconData statusIcon;

    switch (monitor.status) {
      case MonitorStatus.passed:
        statusColor = neonGreen;
        statusText = 'PASSED';
        statusIcon = Icons.check_circle_rounded;
        break;
      case MonitorStatus.failed:
        statusColor = alertRed;
        statusText = 'FAILED';
        statusIcon = Icons.cancel_rounded;
        break;
      case MonitorStatus.incomplete:
        statusColor = amberColor;
        statusText = 'INCOMPLETE';
        statusIcon = Icons.hourglass_bottom_rounded;
        break;
      case MonitorStatus.unsupported:
        statusColor = Colors.white38;
        statusText = 'N/A';
        statusIcon = Icons.remove_circle_outline;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: monitor.status == MonitorStatus.unsupported
              ? Colors.white.withValues(alpha: 0.06)
              : statusColor.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, color: statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        monitor.name,
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: statusColor, width: 1.0),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  monitor.description,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _sendFaultsToAi() {
    final allCodes = _scanResult?.getAllFaultCodes() ?? [];
    if (allCodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No fault codes found to analyze!'), backgroundColor: neonGreen),
      );
      return;
    }

    if (widget.onSendToChat != null) {
      widget.onSendToChat!(allCodes);
      Navigator.pop(context);
    } else {
      Navigator.pop(context, allCodes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalFaults = _topology.fold<int>(0, (sum, ecu) => sum + ecu.faultCodes.length);
    final respondingCount = _topology.where((e) => e.isResponding).length;
    final faultyCount = _topology.where((e) => e.faultCodes.isNotEmpty).length;

    // Filter topology by search and filter category
    final filteredTopology = _topology.where((ecu) {
      if (_filterCategory == 'FAULTY' && ecu.faultCodes.isEmpty) return false;
      if (_filterCategory == 'ONLINE' && !ecu.isResponding) return false;
      if (_filterCategory == 'OFFLINE' && ecu.isResponding) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchesName = ecu.name.toLowerCase().contains(q);
        final matchesHex = '0x${ecu.address.toRadixString(16).toLowerCase()}'.contains(q) ||
            ecu.address.toRadixString(16).toLowerCase().contains(q);
        final matchesDesc = ecu.description.toLowerCase().contains(q);
        return matchesName || matchesHex || matchesDesc;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: bgColor,
        elevation: 0,
        title: const Text(
          'ECU Topology',
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.fact_check_outlined, color: neonGreen),
            tooltip: 'I/M Emissions Readiness',
            onPressed: _showEmissionsReadinessModal,
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: neonGreen),
            tooltip: 'Rescan Vehicle',
            onPressed: _isScanning ? null : _startTopologyScan,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Vehicle Information & Progress Header
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _scanResult?.vin ?? widget.initialVin ?? 'VIN: Detecting...',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Chassis: ${_scanResult?.chassis ?? widget.initialChassis ?? "BMW F-Series"} • Modules: $respondingCount/${_topology.length}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: totalFaults > 0 ? alertRed.withValues(alpha: 0.15) : neonGreen.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: totalFaults > 0 ? alertRed : neonGreen,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          totalFaults > 0 ? '$totalFaults Faults' : 'All Clear',
                          style: TextStyle(
                            color: totalFaults > 0 ? alertRed : neonGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_isScanning) ...[
                    const SizedBox(height: 14),
                    LinearProgressIndicator(
                      value: _scanProgress,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(neonGreen),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _scanStatus,
                      style: const TextStyle(color: neonGreen, fontSize: 12),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: alertRed.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: alertRed, size: 16),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: const TextStyle(color: alertRed, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Search Bar & Filter Chips
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: TextField(
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          hintText: 'Search 32 modules (e.g. DME, 0x12, VTG)...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                          prefixIcon: Icon(Icons.search, color: Colors.white38, size: 18),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  DropdownButton<String>(
                    value: _filterCategory,
                    dropdownColor: cardColor,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(value: 'ALL', child: Text('ALL (${_topology.length})')),
                      DropdownMenuItem(value: 'FAULTY', child: Text('FAULTY ($faultyCount)')),
                      DropdownMenuItem(value: 'ONLINE', child: Text('ONLINE ($respondingCount)')),
                      DropdownMenuItem(value: 'OFFLINE', child: Text('OFFLINE (${_topology.length - respondingCount})')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _filterCategory = val);
                    },
                  ),
                ],
              ),
            ),

            // ECU Module Topology List (Supports all 32 modules)
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: filteredTopology.length,
                itemBuilder: (context, index) {
                  final ecu = filteredTopology[index];
                  final hasFaults = ecu.faultCodes.isNotEmpty;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: !ecu.isResponding
                            ? Colors.white10
                            : (hasFaults ? alertRed.withValues(alpha: 0.4) : neonGreen.withValues(alpha: 0.3)),
                        width: 1.0,
                      ),
                    ),
                    child: Material(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          leading: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: !ecu.isResponding
                                  ? Colors.white.withValues(alpha: 0.05)
                                  : (hasFaults ? alertRed.withValues(alpha: 0.15) : neonGreen.withValues(alpha: 0.15)),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Icon(
                                !ecu.isResponding
                                    ? Icons.signal_cellular_connected_no_internet_0_bar
                                    : (hasFaults ? Icons.warning_rounded : Icons.check_circle_rounded),
                                color: !ecu.isResponding ? Colors.white38 : (hasFaults ? alertRed : neonGreen),
                                size: 20,
                              ),
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  ecu.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '0x${ecu.address.toRadixString(16).toUpperCase()}',
                                  style: const TextStyle(
                                    color: Colors.white54,
                                    fontSize: 11,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            ecu.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!ecu.isResponding)
                                const Text('Offline', style: TextStyle(color: Colors.white38, fontSize: 12))
                              else if (hasFaults)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: alertRed,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${ecu.faultCodes.length}',
                                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                )
                              else
                                const Text('OK', style: TextStyle(color: neonGreen, fontSize: 12, fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              const Icon(Icons.expand_more, color: Colors.white38),
                            ],
                          ),
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              color: Colors.black26,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Action bar inside expanded tile
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _showEcuInfoModal(ecu),
                                        icon: const Icon(Icons.developer_board, size: 14),
                                        label: const Text('MODULE INFO', style: TextStyle(fontSize: 11)),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: neonGreen,
                                          side: BorderSide(color: neonGreen.withValues(alpha: 0.4)),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        ),
                                      ),
                                      if (ecu.isResponding) ...[
                                        OutlinedButton.icon(
                                          onPressed: () => _showEcuResetDialog(ecu),
                                          icon: const Icon(Icons.restart_alt, size: 14),
                                          label: const Text('RESET ECU', style: TextStyle(fontSize: 11)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Colors.orangeAccent,
                                            side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.4)),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                        ),
                                        OutlinedButton.icon(
                                          onPressed: () => _clearSingleEcu(ecu),
                                          icon: const Icon(Icons.delete_sweep, size: 14),
                                          label: const Text('CLEAR THIS ECU', style: TextStyle(fontSize: 11)),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: alertRed,
                                            side: BorderSide(color: alertRed.withValues(alpha: 0.4)),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                const SizedBox(height: 8),

                                if (ecu.faultCodes.isNotEmpty)
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: ecu.faultCodes
                                        .map((code) => Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 4),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Padding(
                                                    padding: EdgeInsets.only(top: 4),
                                                    child: Icon(Icons.fiber_manual_record, color: alertRed, size: 8),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      code,
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13,
                                                        fontFamily: 'monospace',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ))
                                        .toList(),
                                  )
                                else if (ecu.isResponding)
                                  const Text(
                                    'No fault codes stored in this ECU memory.',
                                    style: TextStyle(color: Colors.white54, fontSize: 13),
                                  )
                                else
                                  const Text(
                                    'ECU did not respond to UDS 0x10 session request. (Module may not be fitted or sleeping).',
                                    style: TextStyle(color: Colors.white38, fontSize: 13),
                                  ),

                                // Shadow faults section if present
                                if (ecu.shadowFaultCodes.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Text(
                                    'INFOSPEICHER (SHADOW MEMORY) - ${ecu.shadowFaultCodes.length} CODES',
                                    style: const TextStyle(
                                      color: amberColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  ...ecu.shadowFaultCodes.map((s) => Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 3),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${s.standardDtc} (${s.hexCode}): ${s.description}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 12),
                                            ),
                                            if (s.freezeFrame != null)
                                              Text(
                                                'Snapshot: ${s.freezeFrame!.summary}',
                                                style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
                                              ),
                                          ],
                                        ),
                                      )),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              ),
            ),

            // Action Buttons at Bottom
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor,
                border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isScanning || _isClearing
                          ? null
                          : () {
                              if (totalFaults == 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('✓ მეხსიერება სუფთაა — აქტიური შეცდომები (DTCs) არ ფიქსირდება.'),
                                    backgroundColor: neonGreen,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              } else {
                                _clearAllCodes();
                              }
                            },
                      icon: Icon(
                        totalFaults == 0 ? Icons.check_circle_outline : Icons.delete_sweep,
                        size: 18,
                        color: totalFaults == 0 ? neonGreen : alertRed,
                      ),
                      label: Text(
                        totalFaults == 0 ? '0 DTCs (CLEAN)' : 'CLEAR $totalFaults DTCs',
                        style: TextStyle(
                          color: totalFaults == 0 ? neonGreen : alertRed,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: (totalFaults == 0 ? neonGreen : alertRed).withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        if (totalFaults > 0) {
                          _sendFaultsToAi();
                        } else {
                          // Allow consulting AI even when 0 faults detected
                          if (widget.onSendToChat != null) {
                            widget.onSendToChat!([]);
                            Navigator.pop(context);
                          } else {
                            Navigator.pop(context, []);
                          }
                        }
                      },
                      icon: const Icon(Icons.psychology, size: 20),
                      label: Text(
                        totalFaults > 0 ? 'ANALYZE WITH FIX AI ($totalFaults)' : 'CONSULT FIX AI',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: neonGreen,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
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
