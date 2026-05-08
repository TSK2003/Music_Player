import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GlassCard extends StatefulWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final Color? glowColor;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final bool enableLiftEffect;
  final double? width;
  final double? height;

  const GlassCard({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.opacity = 0.05,
    this.glowColor,
    this.borderRadius = 20.0,
    this.padding,
    this.margin,
    this.onTap,
    this.enableLiftEffect = true,
    this.width,
    this.height,
  });

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _elevationAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _elevationAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (widget.enableLiftEffect) {
      setState(() => _isPressed = true);
      _controller.forward();
    }
  }

  void _handleTapUp(TapUpDetails details) {
    if (widget.enableLiftEffect) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  void _handleTapCancel() {
    if (widget.enableLiftEffect) {
      setState(() => _isPressed = false);
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _GlassAnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.enableLiftEffect ? _scaleAnimation.value : 1.0,
          child: GestureDetector(
            onTapDown: _handleTapDown,
            onTapUp: _handleTapUp,
            onTapCancel: _handleTapCancel,
            onTap: widget.onTap,
            child: Container(
              width: widget.width,
              height: widget.height,
              margin: widget.margin,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                boxShadow: [
                  // Base shadow
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2 + (_isPressed ? 0.15 : 0.0)),
                    blurRadius: 16 + _elevationAnimation.value,
                    offset: Offset(0, 4 + _elevationAnimation.value / 2),
                    spreadRadius: _isPressed ? 2 : 0,
                  ),
                  // Glow effect
                  if (widget.glowColor != null)
                    BoxShadow(
                      color: widget.glowColor!.withValues(
                        alpha: 0.15 + (_isPressed ? 0.15 : 0.0),
                      ),
                      blurRadius: 24 + _elevationAnimation.value,
                      spreadRadius: _isPressed ? 4 : 0,
                    ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: widget.blur,
                    sigmaY: widget.blur,
                  ),
                  child: Container(
                    padding: widget.padding ??
                        const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withValues(alpha: widget.opacity + 0.05),
                          Colors.white.withValues(alpha: widget.opacity),
                        ],
                      ),
                      border: Border.all(
                        color: AppColors.glassBorder,
                        width: 1,
                      ),
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// AnimatedWidget-based builder used internally by GlassCard
class _GlassAnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const _GlassAnimatedBuilder({
    required Animation<double> animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}

