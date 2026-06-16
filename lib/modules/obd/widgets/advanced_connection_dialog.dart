import 'package:flutter/material.dart';

class AdvancedConnectionDialog extends StatefulWidget {
  const AdvancedConnectionDialog({Key? key}) : super(key: key);

  @override
  State<AdvancedConnectionDialog> createState() => _AdvancedConnectionDialogState();
}

class _AdvancedConnectionDialogState extends State<AdvancedConnectionDialog> {
  // Constants for theme
  static const Color bgColor = Color(0xFF121212);
  static const Color neonGreen = Color(0xFF1DB954);

  int _selectedIndex = 3; // Default to ENET
  bool _isConnecting = false;
  String _selectedChassis = 'Auto-Detect';

  final List<String> _interfaces = ['USB', 'Bluetooth', 'Wi-Fi', 'ENET'];
  final List<IconData> _interfaceIcons = [
    Icons.usb,
    Icons.bluetooth,
    Icons.wifi,
    Icons.settings_ethernet,
  ];

  Future<void> _handleConnect() async {
    setState(() => _isConnecting = true);

    // Simulate connection delay
    await Future.delayed(const Duration(seconds: 2));

    if (mounted) {
      setState(() => _isConnecting = false);
      
      // Construct payload
      final payload = {
        "status": "connected",
        "interface": _interfaces[_selectedIndex],
        "chassis": "F26", // Mock auto-detected chassis
        "vin": "WBA1234567890ABCD",
      };
      
      Navigator.pop(context, payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Interface: ${_interfaces[_selectedIndex]}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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
            const SizedBox(height: 24),

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
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: isActive ? neonGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(7),
                          border: Border(
                            right: index < _interfaces.length - 1 && !isActive
                                ? BorderSide(color: neonGreen.withValues(alpha: 0.3), width: 1)
                                : BorderSide.none,
                          ),
                        ),
                        child: Icon(
                          _interfaceIcons[index],
                          color: isActive ? Colors.black : Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 24),

            // Chassis Dropdown
            const Text(
              'Chassis',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedChassis,
              dropdownColor: bgColor,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              icon: const Icon(Icons.arrow_drop_down, color: neonGreen),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.black,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: neonGreen.withValues(alpha: 0.5)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: neonGreen, width: 2),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              items: ['Auto-Detect', 'E90', 'F30', 'F26', 'G20']
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
            const SizedBox(height: 32),

            // Connect Button
            SizedBox(
              height: 56,
              child: ElevatedButton(
                onPressed: _isConnecting ? null : _handleConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: neonGreen,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor: neonGreen.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 5,
                  shadowColor: neonGreen.withValues(alpha: 0.5),
                ),
                child: _isConnecting
                    ? const SizedBox(
                        height: 24,
                        width: 24,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 3,
                        ),
                      )
                    : const Text(
                        'CONNECT',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
