import 'package:flutter/material.dart';

/// Automotive Destructive Action Safeguard with Physical Motion Interlocks (P3.4).
///
/// Prevents accidental taps during driving or bench testing.
/// Requires an intentional, continuous slide gesture across the track.
///
/// **Physical Motion Interlocks:**
/// - Fails closed if engine is running ([currentRpm] > 0).
/// - Fails closed if vehicle is moving ([currentSpeed] > 0).
class SlideToConfirm extends StatefulWidget {
  final String label;
  final String confirmedLabel;
  final VoidCallback onConfirmed;
  final double? currentRpm;
  final double? currentSpeed;
  final bool isEnabled;
  final bool isDestructive;
  final Color? sliderColor;
  final Color? backgroundColor;
  final IconData icon;

  const SlideToConfirm({
    super.key,
    required this.label,
    required this.onConfirmed,
    this.confirmedLabel = 'CONFIRMED',
    this.currentRpm,
    this.currentSpeed,
    this.isEnabled = true,
    this.isDestructive = true,
    this.sliderColor,
    this.backgroundColor,
    this.icon = Icons.double_arrow_rounded,
  });

  @override
  State<SlideToConfirm> createState() => _SlideToConfirmState();
}

class _SlideToConfirmState extends State<SlideToConfirm> with SingleTickerProviderStateMixin {
  double _dragPosition = 0.0;
  bool _isConfirmed = false;
  late AnimationController _animController;
  Animation<double>? _resetAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        if (_resetAnimation != null) {
          setState(() {
            _dragPosition = _resetAnimation!.value;
          });
        }
      });
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  String? _getMotionInterlockReason() {
    if (widget.currentRpm != null && widget.currentRpm! > 0) {
      return 'ENGINE RUNNING (${widget.currentRpm!.toStringAsFixed(0)} RPM) — Turn off engine before proceeding';
    }
    if (widget.currentSpeed != null && widget.currentSpeed! > 0) {
      return 'VEHICLE IN MOTION (${widget.currentSpeed!.toStringAsFixed(0)} km/h) — Vehicle must be stationary';
    }
    return null;
  }

  void _onDragUpdate(DragUpdateDetails details, double maxDrag) {
    if (!widget.isEnabled || _getMotionInterlockReason() != null || _isConfirmed) return;
    setState(() {
      _dragPosition = (_dragPosition + details.delta.dx).clamp(0.0, maxDrag);
    });
  }

  void _onDragEnd(DragEndDetails details, double maxDrag) {
    if (!widget.isEnabled || _getMotionInterlockReason() != null || _isConfirmed) return;

    if (_dragPosition >= maxDrag * 0.88) {
      // Confirmed!
      setState(() {
        _dragPosition = maxDrag;
        _isConfirmed = true;
      });
      widget.onConfirmed();
    } else {
      // Snap back smoothly
      _resetAnimation = Tween<double>(begin: _dragPosition, end: 0.0).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
      );
      _animController.forward(from: 0.0);
    }
  }

  void reset() {
    setState(() {
      _dragPosition = 0.0;
      _isConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final interlockError = _getMotionInterlockReason();
    final isBlocked = !widget.isEnabled || interlockError != null;

    final primaryColor = widget.sliderColor ??
        (widget.isDestructive ? const Color(0xFFE53935) : const Color(0xFF29B6F6));
    final bgColor = widget.backgroundColor ?? const Color(0xFF1E1E1E);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (interlockError != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE53935).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFE53935).withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.block, color: Color(0xFFE53935), size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    interlockError,
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final trackWidth = constraints.maxWidth;
            const thumbWidth = 56.0;
            const trackHeight = 56.0;
            final maxDrag = (trackWidth - thumbWidth).clamp(0.0, trackWidth);

            final progress = maxDrag > 0 ? (_dragPosition / maxDrag).clamp(0.0, 1.0) : 0.0;

            return Container(
              height: trackHeight,
              decoration: BoxDecoration(
                color: isBlocked ? Colors.white10 : bgColor,
                borderRadius: BorderRadius.circular(trackHeight / 2),
                border: Border.all(
                  color: isBlocked
                      ? Colors.white12
                      : primaryColor.withValues(alpha: 0.3 + 0.4 * progress),
                  width: 1.5,
                ),
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Shimmer progress track behind thumb
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: _dragPosition + thumbWidth,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isBlocked
                            ? Colors.transparent
                            : primaryColor.withValues(alpha: 0.15 + 0.15 * progress),
                        borderRadius: BorderRadius.circular(trackHeight / 2),
                      ),
                    ),
                  ),

                  // Center Prompt Label
                  Center(
                    child: Opacity(
                      opacity: (1.0 - progress * 1.5).clamp(0.0, 1.0),
                      child: Text(
                        _isConfirmed ? widget.confirmedLabel : widget.label,
                        style: TextStyle(
                          color: isBlocked ? Colors.white38 : Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),

                  // Draggable Thumb Knob
                  Positioned(
                    left: _dragPosition,
                    child: GestureDetector(
                      onHorizontalDragUpdate: (details) => _onDragUpdate(details, maxDrag),
                      onHorizontalDragEnd: (details) => _onDragEnd(details, maxDrag),
                      child: Container(
                        width: thumbWidth,
                        height: trackHeight,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isBlocked ? Colors.white24 : primaryColor,
                          boxShadow: [
                            if (!isBlocked)
                              BoxShadow(
                                color: primaryColor.withValues(alpha: 0.4),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            _isConfirmed ? Icons.check : widget.icon,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
