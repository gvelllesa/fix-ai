import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Motion & Animation choreography for FIX AI
/// Provides smooth 60-120fps micro-interactions, spring curves, and staggered entrances.
class FixAiMotion {
  FixAiMotion._();

  // Durations
  static const Duration durationFast = Duration(milliseconds: 150);
  static const Duration durationMedium = Duration(milliseconds: 280);
  static const Duration durationSlow = Duration(milliseconds: 450);

  // Curves
  static const Curve curveSpring = Curves.easeOutCubic;
  static const Curve curveExpressive = Curves.fastLinearToSlowEaseIn;
  static const Curve curveEnter = Curves.easeOutQuart;
}

/// Interactive tactile pressable container with subtle scale compression
class BouncyPressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;
  final BorderRadius? borderRadius;
  final Duration duration;
  final bool enabled;

  const BouncyPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.965,
    this.borderRadius,
    this.duration = const Duration(milliseconds: 110),
    this.enabled = true,
  });

  @override
  State<BouncyPressable> createState() => _BouncyPressableState();
}

class _BouncyPressableState extends State<BouncyPressable> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      reverseDuration: const Duration(milliseconds: 160),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.pressedScale,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeOutBack,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails _) {
    if (!widget.enabled) return;
    _controller.forward();
  }

  void _onTapUp(TapUpDetails _) {
    if (!widget.enabled) return;
    _controller.reverse();
    widget.onTap?.call();
  }

  void _onTapCancel() {
    if (!widget.enabled) return;
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: widget.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onTapCancel: _onTapCancel,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedBuilder(
          animation: _scaleAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value * (_isHovered && widget.enabled ? 1.01 : 1.0),
              child: child,
            );
          },
          child: widget.borderRadius != null
              ? ClipRRect(borderRadius: widget.borderRadius!, child: widget.child)
              : widget.child,
        ),
      ),
    );
  }
}

/// Staggered Entrance Animation (Fade + Upward Slide) using pure Interval curves (no Timers)
class StaggeredSlideFade extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final double offsetDistance;
  final Curve curve;

  const StaggeredSlideFade({
    super.key,
    required this.child,
    this.index = 0,
    this.duration = const Duration(milliseconds: 400),
    this.offsetDistance = 16.0,
    this.curve = Curves.easeOutCubic,
  });

  @override
  Widget build(BuildContext context) {
    final beginInterval = (index * 0.08).clamp(0.0, 0.6);

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: duration,
      curve: Interval(beginInterval, 1.0, curve: curve),
      builder: (context, progress, animChild) {
        return Opacity(
          opacity: progress.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, (1.0 - progress) * offsetDistance),
            child: animChild,
          ),
        );
      },
      child: child,
    );
  }
}

/// Breathing / Pulsing Glow Halo for active vehicle status or telemetry
class PulsingStatusGlow extends StatefulWidget {
  final Widget child;
  final Color glowColor;
  final double maxRadius;
  final Duration period;
  final bool isPulsing;

  const PulsingStatusGlow({
    super.key,
    required this.child,
    required this.glowColor,
    this.maxRadius = 8.0,
    this.period = const Duration(milliseconds: 1800),
    this.isPulsing = true,
  });

  @override
  State<PulsingStatusGlow> createState() => _PulsingStatusGlowState();
}

class _PulsingStatusGlowState extends State<PulsingStatusGlow> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.period);
    _glowAnimation = Tween<double>(begin: 0.2, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulsingStatusGlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing != oldWidget.isPulsing) {
      if (widget.isPulsing) {
        _controller.repeat(reverse: true);
      } else {
        _controller.stop();
        _controller.value = 0.4;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isPulsing) return widget.child;

    return AnimatedBuilder(
      animation: _glowAnimation,
      builder: (context, child) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withValues(alpha: 0.35 * _glowAnimation.value),
                blurRadius: widget.maxRadius * _glowAnimation.value,
                spreadRadius: (widget.maxRadius / 3) * _glowAnimation.value,
              ),
            ],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// Shimmering Border Animation for high-priority hero elements
class ShimmerGlowBorder extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final Color primaryColor;
  final Color secondaryColor;
  final double borderWidth;

  const ShimmerGlowBorder({
    super.key,
    required this.child,
    required this.borderRadius,
    required this.primaryColor,
    required this.secondaryColor,
    this.borderWidth = 1.4,
  });

  @override
  State<ShimmerGlowBorder> createState() => _ShimmerGlowBorderState();
}

class _ShimmerGlowBorderState extends State<ShimmerGlowBorder> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final angle = _controller.value * 2 * math.pi;
        return Container(
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: SweepGradient(
              center: Alignment.center,
              startAngle: 0.0,
              endAngle: math.pi * 2,
              transform: GradientRotation(angle),
              colors: [
                widget.primaryColor.withValues(alpha: 0.8),
                widget.secondaryColor.withValues(alpha: 0.3),
                Colors.transparent,
                widget.primaryColor.withValues(alpha: 0.8),
              ],
              stops: const [0.0, 0.25, 0.6, 1.0],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.all(widget.borderWidth),
            child: child,
          ),
        );
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(
          math.max(0, widget.borderRadius.topLeft.x - widget.borderWidth),
        ),
        child: widget.child,
      ),
    );
  }
}

/// Smooth page route with subtle slide, scale, and fade transition
class SmoothSlidePageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothSlidePageRoute({required this.page})
      : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: const Duration(milliseconds: 260),
          reverseTransitionDuration: const Duration(milliseconds: 220),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            final curvedIn = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );

            final slideAnimation = Tween<Offset>(
              begin: const Offset(0.04, 0),
              end: Offset.zero,
            ).animate(curvedIn);

            final scaleAnimation = Tween<double>(
              begin: 0.985,
              end: 1.0,
            ).animate(curvedIn);

            final fadeAnimation = Tween<double>(
              begin: 0.0,
              end: 1.0,
            ).animate(curvedIn);

            return SlideTransition(
              position: slideAnimation,
              child: ScaleTransition(
                scale: scaleAnimation,
                child: FadeTransition(
                  opacity: fadeAnimation,
                  child: child,
                ),
              ),
            );
          },
        );
}

/// Global PageTransitionsBuilder for smooth, elegant transitions across all routes
class FixAiPageTransitionsBuilder extends PageTransitionsBuilder {
  const FixAiPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curvedIn = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final curvedSecondary = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final slideIn = Tween<Offset>(
      begin: const Offset(0.05, 0),
      end: Offset.zero,
    ).animate(curvedIn);

    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.02, 0),
    ).animate(curvedSecondary);

    final fadeIn = Tween<double>(begin: 0.0, end: 1.0).animate(curvedIn);
    final fadeOut = Tween<double>(begin: 1.0, end: 0.88).animate(curvedSecondary);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: fadeIn,
            child: child,
          ),
        ),
      ),
    );
  }
}
