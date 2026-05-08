import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlowButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final Color? color;
  final VoidCallback? onPressed;
  final bool enableGlow;

  const GlowButton({
    super.key,
    required this.icon,
    this.size = 64,
    this.color,
    this.onPressed,
    this.enableGlow = true,
  });

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    if (widget.enableGlow) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(GlowButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enableGlow && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (!widget.enableGlow && _glowController.isAnimating) {
      _glowController.stop();
      _glowController.value = 0.0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? AppColors.neonBlue;

    return GestureDetector(
      onTap: widget.onPressed,
      child: NeonAnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glowIntensity = widget.enableGlow
              ? 0.3 + (_glowController.value * 0.3)
              : 0.2;

          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.3),
                  color.withValues(alpha: 0.1),
                ],
              ),
              border: Border.all(
                color: color.withValues(alpha: 0.5),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: glowIntensity),
                  blurRadius: 20 + (_glowController.value * 10),
                  spreadRadius: 2 + (_glowController.value * 4),
                ),
                BoxShadow(
                  color: color.withValues(alpha: glowIntensity * 0.5),
                  blurRadius: 40 + (_glowController.value * 15),
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              widget.icon,
              color: Colors.white,
              size: widget.size * 0.5,
            ),
          );
        },
      ),
    );
  }
}

class ControlButton extends StatefulWidget {
  final IconData icon;
  final double size;
  final VoidCallback? onPressed;

  const ControlButton({
    super.key,
    required this.icon,
    this.size = 48,
    this.onPressed,
  });

  @override
  State<ControlButton> createState() => _ControlButtonState();
}

class _ControlButtonState extends State<ControlButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
      lowerBound: 0.9,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _scaleController.reverse(),
      onTapUp: (_) {
        _scaleController.forward();
        widget.onPressed?.call();
      },
      onTapCancel: () => _scaleController.forward(),
      child: ScaleTransition(
        scale: _scaleController,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Icon(
            widget.icon,
            color: AppColors.textPrimary,
            size: widget.size * 0.5,
          ),
        ),
      ),
    );
  }
}

/// NeonAnimatedBuilder using AnimatedWidget pattern
class NeonAnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const NeonAnimatedBuilder({
    super.key,
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
