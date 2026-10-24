import 'package:flutter/material.dart';
import '../../../core/animations/fix_ai_motion.dart';
import '../../../core/theme/fix_ai_tokens.dart';
import '../services/connection_manager.dart';
import '../services/protocols/kdcan_protocol.dart';

/// EvoCare-Inspired High-Tech Automotive Vehicle Connection Hub.
///
/// Features:
/// 1. Single App-Wide Connection Orchestration via [ConnectionManager.instance.connectVehicle].
/// 2. Live Animated Discovery of all 32 ECU Modules with real-time response latency (ms).
/// 3. Precise Link-Break Analysis ("სად გაწყდა კავშირი") with actionable diagnostics.
/// 4. Tactile, luxury dark-obsidian UI with fluid 60-120fps micro-animations.
class AdvancedConnectionDialog extends StatefulWidget {
  const AdvancedConnectionDialog({super.key});

  @override
  State<AdvancedConnectionDialog> createState() => _AdvancedConnectionDialogState();
}

class _AdvancedConnectionDialogState extends State<AdvancedConnectionDialog>
    with SingleTickerProviderStateMixin {
  int _selectedIndex = 2; // Default to Wi-Fi
  String _selectedChassis = 'Auto-Detect';

  final TextEditingController _ipController = TextEditingController(text: '192.168.16.101');
  final TextEditingController _portController = TextEditingController(text: '35000');
  bool _autoDetect = true;
  DcanMode _selectedDcanMode = DcanMode.dCan;

  final List<String> _interfaces = ['USB', 'Bluetooth', 'Wi-Fi', 'ENET'];
  final List<IconData> _interfaceIcons = [
    Icons.usb_rounded,
    Icons.bluetooth_rounded,
    Icons.wifi_rounded,
    Icons.settings_ethernet_rounded,
  ];

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _handleConnect() async {
    final cm = ConnectionManager.instance;
    final isUsb = _selectedIndex == 0;
    final kdcan = isUsb ? KdcanProtocol(initialMode: _selectedDcanMode) : null;

    final success = await cm.connectVehicle(
      host: _ipController.text.trim(),
      port: int.tryParse(_portController.text.trim()) ?? 35000,
      autoDetect: _autoDetect,
      kdcan: kdcan,
      kdcanMode: _selectedDcanMode,
      probeModules: true,
    );

    if (success && mounted) {
      final snap = cm.snapshot;
      final payload = {
        "status": "connected",
        "interface": _interfaces[_selectedIndex],
        "host": snap.host ?? _ipController.text.trim(),
        "port": snap.port ?? 35000,
        "isDoip": snap.isDoip,
        "chassis": _selectedChassis,
        "vin": snap.activeVin ?? 'WBA_DETECTED',
        "protocol": cm.protocol,
      };
      // Brief pause to display all green modules before dismissing
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) Navigator.pop(context, payload);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: ValueListenableBuilder<ConnectionProgress>(
        valueListenable: ConnectionManager.instance.progressNotifier,
        builder: (context, progress, _) {
          final isBusy = progress.isBusy;
          final hasFailed = progress.phase == ConnectionPhase.failed ||
              progress.phase == ConnectionPhase.lost;

          return Container(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 680),
            decoration: BoxDecoration(
              color: FixAiTokens.canvas,
              borderRadius: FixAiTokens.borderRadiusLg,
              border: Border.all(
                color: isBusy
                    ? FixAiTokens.accentCyan.withValues(alpha: 0.5)
                    : (hasFailed
                        ? FixAiTokens.accentRose.withValues(alpha: 0.5)
                        : FixAiTokens.accentEmerald.withValues(alpha: 0.35)),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isBusy ? FixAiTokens.accentCyan : FixAiTokens.accentEmerald)
                      .withValues(alpha: 0.12),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: FixAiTokens.borderRadiusLg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Header with Vehicle Connection Status
                  _buildHeader(progress),

                  // 2. Main Content (Settings or Animated Live Scanner)
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!isBusy && !hasFailed && progress.modules.isEmpty) ...[
                            _buildInterfaceSelector(),
                            const SizedBox(height: 16),
                            if (_selectedIndex == 0)
                              _buildUsbDcanSection()
                            else
                              _buildNetworkSettingsSection(),
                            const SizedBox(height: 16),
                            _buildChassisSelector(),
                          ] else ...[
                            // Live Animated Connection Stage & Progress
                            _buildLiveScanningView(progress),
                          ],

                          if (hasFailed && progress.failureStage != null) ...[
                            const SizedBox(height: 14),
                            _buildFailureCard(progress),
                          ],

                          const SizedBox(height: 20),

                          // Action Button
                          _buildActionButton(progress),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader(ConnectionProgress progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: FixAiTokens.surfacePrimary,
        border: Border(bottom: BorderSide(color: FixAiTokens.borderSubtle)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: FixAiTokens.accentCyan.withValues(alpha: 0.12),
                  borderRadius: FixAiTokens.borderRadiusSm,
                  border: Border.all(color: FixAiTokens.accentCyan.withValues(alpha: 0.25)),
                ),
                child: const Icon(Icons.wifi_tethering_rounded, color: FixAiTokens.accentCyan, size: 20),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ავტომობილთან დაკავშირება',
                    style: TextStyle(
                      color: FixAiTokens.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  Text(
                    'ONE-TIME VEHICLE SESSION',
                    style: TextStyle(
                      color: FixAiTokens.textMuted,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                    ),
                  ),
                ],
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.close, color: FixAiTokens.textSecondary, size: 20),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildInterfaceSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ინტერფეისი (ADAPTER PROTOCOL)',
          style: FixAiTokens.sectionHeader,
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: FixAiTokens.surfacePrimary,
            borderRadius: FixAiTokens.borderRadiusMd,
            border: Border.all(color: FixAiTokens.borderSubtle),
          ),
          child: Row(
            children: List.generate(_interfaces.length, (index) {
              final isActive = index == _selectedIndex;
              return Expanded(
                child: BouncyPressable(
                  onTap: () => setState(() => _selectedIndex = index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive ? FixAiTokens.accentEmerald : Colors.transparent,
                      borderRadius: FixAiTokens.borderRadiusMd,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _interfaceIcons[index],
                          color: isActive ? Colors.black : FixAiTokens.textSecondary,
                          size: 20,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _interfaces[index],
                          style: TextStyle(
                            color: isActive ? Colors.black : FixAiTokens.textSecondary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  Widget _buildNetworkSettingsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('ქსელის პარამეტრები (ENET / DOIP)', style: FixAiTokens.sectionHeader),
            Row(
              children: [
                Text(
                  'ავტო-ძებნა',
                  style: TextStyle(
                    color: _autoDetect ? FixAiTokens.accentEmerald : FixAiTokens.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Transform.scale(
                  scale: 0.8,
                  child: Switch(
                    value: _autoDetect,
                    activeTrackColor: FixAiTokens.accentEmerald.withValues(alpha: 0.5),
                    activeThumbColor: FixAiTokens.accentEmerald,
                    onChanged: (val) => setState(() => _autoDetect = val),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _ipController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'ადაპტერის IP',
                  labelStyle: TextStyle(color: FixAiTokens.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: FixAiTokens.surfacePrimary,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: FixAiTokens.borderRadiusSm,
                    borderSide: BorderSide(color: FixAiTokens.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: FixAiTokens.borderRadiusSm,
                    borderSide: const BorderSide(color: FixAiTokens.accentCyan),
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
                  color: _autoDetect ? FixAiTokens.textDisabled : Colors.white,
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  labelText: 'პორტი',
                  labelStyle: TextStyle(color: FixAiTokens.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: FixAiTokens.surfacePrimary,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: FixAiTokens.borderRadiusSm,
                    borderSide: BorderSide(color: FixAiTokens.borderSubtle),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: FixAiTokens.borderRadiusSm,
                    borderSide: const BorderSide(color: FixAiTokens.accentCyan),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildUsbDcanSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('USB K+DCAN რეჟიმი', style: FixAiTokens.sectionHeader),
        const SizedBox(height: 6),
        DropdownButtonFormField<DcanMode>(
          initialValue: _selectedDcanMode,
          dropdownColor: FixAiTokens.surfaceElevated,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: FixAiTokens.accentCyan),
          decoration: InputDecoration(
            filled: true,
            fillColor: FixAiTokens.surfacePrimary,
            enabledBorder: OutlineInputBorder(
              borderRadius: FixAiTokens.borderRadiusSm,
              borderSide: BorderSide(color: FixAiTokens.borderSubtle),
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
      ],
    );
  }

  Widget _buildChassisSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('შასი / მოდელის პროფილი', style: FixAiTokens.sectionHeader),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: _selectedChassis,
          dropdownColor: FixAiTokens.surfaceElevated,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: FixAiTokens.accentCyan),
          decoration: InputDecoration(
            filled: true,
            fillColor: FixAiTokens.surfacePrimary,
            enabledBorder: OutlineInputBorder(
              borderRadius: FixAiTokens.borderRadiusSm,
              borderSide: BorderSide(color: FixAiTokens.borderSubtle),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          items: ['Auto-Detect', 'F26 (X4 N55)', 'F30 (3-Series)', 'F10 (5-Series)', 'G20 (3-Series)', 'E90 (3-Series)']
              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedChassis = val);
          },
        ),
      ],
    );
  }

  // Live Animated Discovery View of 32 ECU Modules
  Widget _buildLiveScanningView(ConnectionProgress progress) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Radar Pulse + Stage Title
        Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: progress.isBusy
                  ? CircularProgressIndicator(
                      value: progress.progress > 0 ? progress.progress : null,
                      strokeWidth: 2.5,
                      color: FixAiTokens.accentEmerald,
                    )
                  : const Icon(Icons.check_circle_rounded, color: FixAiTokens.accentEmerald, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.message.isNotEmpty ? progress.message : 'დაკავშირება მიმდინარეობს...',
                    style: TextStyle(
                      color: FixAiTokens.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'პროგრესი: ${(progress.progress * 100).toInt()}% • ონლაინ ბლოკები: ${progress.onlineCount}/32',
                    style: TextStyle(color: FixAiTokens.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Progress Bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.progress.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: FixAiTokens.surfaceElevated,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress.phase == ConnectionPhase.failed || progress.phase == ConnectionPhase.lost
                  ? FixAiTokens.accentRose
                  : FixAiTokens.accentEmerald,
            ),
          ),
        ),
        const SizedBox(height: 14),

        // 2. 32-Module Animated Badge Grid
        Text(
          'საკონტროლო ბლოკების სტატუსი (32 MODULE TOPOLOGY)',
          style: FixAiTokens.sectionHeader,
        ),
        const SizedBox(height: 8),

        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: FixAiTokens.surfacePrimary,
            borderRadius: FixAiTokens.borderRadiusMd,
            border: Border.all(color: FixAiTokens.borderSubtle),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 2.1,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemCount: progress.modules.length,
            itemBuilder: (context, idx) {
              final mod = progress.modules[idx];
              Color bg;
              Color border;
              Color text;

              switch (mod.state) {
                case ModuleProbeState.online:
                  bg = FixAiTokens.accentEmerald.withValues(alpha: 0.16);
                  border = FixAiTokens.accentEmerald.withValues(alpha: 0.6);
                  text = FixAiTokens.accentEmerald;
                  break;
                case ModuleProbeState.probing:
                  bg = FixAiTokens.accentCyan.withValues(alpha: 0.22);
                  border = FixAiTokens.accentCyan;
                  text = Colors.white;
                  break;
                case ModuleProbeState.silent:
                  bg = FixAiTokens.surfaceElevated;
                  border = FixAiTokens.borderSubtle;
                  text = FixAiTokens.textMuted;
                  break;
                case ModuleProbeState.pending:
                  bg = FixAiTokens.canvas;
                  border = FixAiTokens.borderSubtle.withValues(alpha: 0.5);
                  text = FixAiTokens.textDisabled;
                  break;
              }

              return Container(
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: FixAiTokens.borderRadiusSm,
                  border: Border.all(color: border, width: 1),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      mod.name,
                      style: TextStyle(
                        color: text,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      mod.state == ModuleProbeState.online && mod.latencyMs != null
                          ? '${mod.latencyMs}ms'
                          : mod.hexAddress,
                      style: TextStyle(
                        color: mod.state == ModuleProbeState.online
                            ? FixAiTokens.accentEmerald.withValues(alpha: 0.85)
                            : FixAiTokens.textMuted,
                        fontSize: 8,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // Exact Failure Card: Clearly explains where connection broke
  Widget _buildFailureCard(ConnectionProgress progress) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: FixAiTokens.accentRose.withValues(alpha: 0.1),
        borderRadius: FixAiTokens.borderRadiusMd,
        border: Border.all(color: FixAiTokens.accentRose.withValues(alpha: 0.5), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: FixAiTokens.accentRose, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'კავშირი გაწყდა',
                  style: const TextStyle(
                    color: FixAiTokens.accentRose,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.35),
              children: [
                const TextSpan(
                  text: 'სად გაწყდა: ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: '${progress.failureStage}\n\n',
                  style: const TextStyle(color: FixAiTokens.accentAmber, fontWeight: FontWeight.w600),
                ),
                const TextSpan(
                  text: 'მიზეზი / რეკომენდაცია: ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
                TextSpan(text: progress.failureDetail ?? 'დაკავშირება ვერ მოხერხდა.'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(ConnectionProgress progress) {
    final isBusy = progress.isBusy;
    final hasFailed = progress.phase == ConnectionPhase.failed ||
        progress.phase == ConnectionPhase.lost;

    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: isBusy ? null : _handleConnect,
        style: ElevatedButton.styleFrom(
          backgroundColor: hasFailed ? FixAiTokens.accentAmber : FixAiTokens.accentEmerald,
          foregroundColor: Colors.black,
          disabledBackgroundColor: FixAiTokens.accentEmerald.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(borderRadius: FixAiTokens.borderRadiusMd),
          elevation: 0,
        ),
        child: isBusy
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2.2),
                  ),
                  SizedBox(width: 10),
                  Text(
                    'დაკავშირება მიმდინარეობს...',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
                  ),
                ],
              )
            : Text(
                hasFailed ? 'თავიდან ცდა' : 'ავტომობილთან დაკავშირება',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
      ),
    );
  }
}
