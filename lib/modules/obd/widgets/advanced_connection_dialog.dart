import 'package:flutter/material.dart';
import '../services/connection_manager.dart';
import '../services/protocols/kdcan_protocol.dart';

class AdvancedConnectionDialog extends StatefulWidget {
  const AdvancedConnectionDialog({super.key});

  @override
  State<AdvancedConnectionDialog> createState() => _AdvancedConnectionDialogState();
}

class _AdvancedConnectionDialogState extends State<AdvancedConnectionDialog> {
  // Theme constants
  static const Color bgColor = Color(0xFF121212);
  static const Color surfaceColor = Color(0xFF1E1E1E);
  static const Color neonGreen = Color(0xFF1DB954);
  static const Color errorRed = Color(0xFFE53935);

  int _selectedIndex = 3; // Default to ENET
  bool _isConnecting = false;
  String _statusMessage = '';
  String? _errorMessage;
  String _selectedChassis = 'Auto-Detect';

  final TextEditingController _ipController = TextEditingController(text: '192.168.16.101');
  final TextEditingController _portController = TextEditingController(text: '35000');
  bool _autoDetect = true;
  DcanMode _selectedDcanMode = DcanMode.dCan;

  final List<String> _interfaces = ['USB', 'Bluetooth', 'Wi-Fi', 'ENET'];
  final List<IconData> _interfaceIcons = [
    Icons.usb,
    Icons.bluetooth,
    Icons.wifi,
    Icons.settings_ethernet,
  ];

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _statusMessage = 'Connecting to vehicle adapter...';
    });

    final protocol = ConnectionManager.instance.protocol;

    try {
      bool connected = false;
      String connectedHost = _ipController.text.trim();
      int connectedPort = int.tryParse(_portController.text.trim()) ?? 35000;
      bool isDoip = connectedPort == 13400;

      if (_selectedIndex == 0) {
        // USB INPA K+DCAN (FTDI FT232RL) Mode
        setState(() => _statusMessage = 'Initializing USB FTDI K+DCAN (${_selectedDcanMode.description})...');
        final kdcan = KdcanProtocol(initialMode: _selectedDcanMode);
        connected = await ConnectionManager.instance.connectKdcanAdapter(
          kdcan,
          mode: _selectedDcanMode,
        );
        connectedHost = 'USB-KDCAN-${_selectedDcanMode.name.toUpperCase()}';
        connectedPort = kdcan.baudrate;
        isDoip = false;
        if (!connected) {
          throw Exception('USB FTDI K+DCAN cable not found or permission denied. Check OTG adapter.');
        }
      } else if (_autoDetect) {
        setState(() => _statusMessage = 'Broadcasting UDP 6811 & sweeping ports (35000, 6801, 13400, 50160)...');
        final target = await protocol.detectAdapter(preferredHost: connectedHost.isNotEmpty ? connectedHost : null);
        if (target != null) {
          connectedHost = target.host;
          connectedPort = target.port;
          isDoip = target.isDoip;
          setState(() => _statusMessage = 'Adapter detected at $connectedHost:$connectedPort! Handshaking...');
          connected = await ConnectionManager.instance.connect(
            host: connectedHost,
            port: connectedPort,
            useDoip: isDoip,
          );
        } else {
          throw Exception('No OBD adapter found on network. Ensure adapter Wi-Fi/Ethernet is connected.');
        }
      } else {
        setState(() => _statusMessage = 'Direct connecting to $connectedHost:$connectedPort...');
        connected = await ConnectionManager.instance.connect(
          host: connectedHost,
          port: connectedPort,
          useDoip: isDoip,
        );
      }

      if (!connected) {
        throw Exception('TCP handshake rejected by $connectedHost:$connectedPort.');
      }

      // Step 2: Read Vehicle VIN directly via UDS 0x22 0xF1 0x90
      setState(() => _statusMessage = 'Querying DME (0x12) for Vehicle Identification (VIN)...');
      String? realVin = await protocol.readVin(0x12);
      if (realVin == null || realVin.isEmpty) {
        setState(() => _statusMessage = 'DME query timed out. Querying Central Gateway (0x10)...');
        realVin = await protocol.readVin(0x10);
      }

      // If still no response to VIN query, vehicle ignition may be off
      if (realVin == null || realVin.isEmpty) {
        realVin = 'VIN_READ_TIMEOUT (Ignition OFF?)';
      }

      // Detect chassis from VIN
      String detectedChassis = _selectedChassis;
      if (_selectedChassis == 'Auto-Detect') {
        if (realVin.startsWith('5UX') || realVin.contains('N55') || realVin.contains('X4')) {
          detectedChassis = 'F26 (X4)';
        } else if (realVin.startsWith('WBA') || realVin.startsWith('WBY')) {
          detectedChassis = 'F-Series';
        } else {
          detectedChassis = 'BMW F-Series';
        }
      }

      if (mounted) {
        setState(() {
          _isConnecting = false;
          _statusMessage = 'Connected! VIN: $realVin';
        });

        final payload = {
          "status": "connected",
          "interface": _interfaces[_selectedIndex],
          "host": connectedHost,
          "port": connectedPort,
          "isDoip": isDoip,
          "chassis": detectedChassis,
          "vin": realVin,
          "protocol": protocol, // keep instance alive for session
        };

        Navigator.pop(context, payload);
      }
    } catch (e) {
      protocol.disconnect();
      if (mounted) {
        setState(() {
          _isConnecting = false;
          _errorMessage = e.toString().replaceAll('Exception: ', '');
          _statusMessage = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: neonGreen.withValues(alpha: 0.5), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: neonGreen.withValues(alpha: 0.15),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      children: [
                        Icon(_interfaceIcons[_selectedIndex], color: neonGreen, size: 24),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Interface: ${_interfaces[_selectedIndex]}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Interface Selector
              Container(
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white12),
                ),
                child: Row(
                  children: List.generate(_interfaces.length, (index) {
                    final isActive = index == _selectedIndex;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedIndex = index),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isActive ? neonGreen : Colors.transparent,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Icon(
                            _interfaceIcons[index],
                            color: isActive ? Colors.black : Colors.white70,
                            size: 22,
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 18),

              // Network or USB K+DCAN Adapter Configuration
              if (_selectedIndex == 0) ...[
                const Text(
                  'USB INPA K+DCAN (FTDI FT232RL) Mode',
                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<DcanMode>(
                  initialValue: _selectedDcanMode,
                  dropdownColor: surfaceColor,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  icon: const Icon(Icons.arrow_drop_down, color: neonGreen),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: surfaceColor,
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: neonGreen),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  items: DcanMode.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.description, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedDcanMode = val);
                  },
                ),
              ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Network Settings',
                    style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Row(
                    children: [
                      Text(
                        'Auto-Detect',
                        style: TextStyle(
                          color: _autoDetect ? neonGreen : Colors.white38,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Switch(
                        value: _autoDetect,
                        activeThumbColor: neonGreen,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        onChanged: (val) => setState(() => _autoDetect = val),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        labelText: 'Adapter IP',
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                        filled: true,
                        fillColor: surfaceColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: neonGreen),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      enabled: !_autoDetect,
                      style: TextStyle(
                        color: _autoDetect ? Colors.white38 : Colors.white,
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Port',
                        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
                        filled: true,
                        fillColor: surfaceColor,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: neonGreen),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              ],
              const SizedBox(height: 16),

              // Chassis Selector
              const Text(
                'BMW Chassis Profile',
                style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _selectedChassis,
                dropdownColor: surfaceColor,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                icon: const Icon(Icons.arrow_drop_down, color: neonGreen),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: surfaceColor,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: neonGreen),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: ['Auto-Detect', 'F26 (X4 N55)', 'F30 (3-Series)', 'F10 (5-Series)', 'G20 (3-Series)', 'E90 (3-Series)']
                    .map((chassis) => DropdownMenuItem(
                          value: chassis,
                          child: Text(chassis),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedChassis = value);
                  }
                },
              ),
              const SizedBox(height: 20),

              // Live Status / Error Message
              if (_statusMessage.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: neonGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: neonGreen.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: neonGreen),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: const TextStyle(color: neonGreen, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              if (_errorMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: errorRed.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: errorRed.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: errorRed, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: errorRed, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Connect Button
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _isConnecting ? null : _handleConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: neonGreen,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: neonGreen.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 4,
                  ),
                  child: _isConnecting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.black,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'CONNECT TO VEHICLE',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
