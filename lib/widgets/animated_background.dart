import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';

class AnimatedBackground extends StatefulWidget {
  final double scrollOffset;
  final Color? accentColor;
  final Widget child;

  const AnimatedBackground({
    super.key,
    this.scrollOffset = 0.0,
    this.accentColor,
    required this.child,
  });

  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    // Apple-style base colors
    final baseColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    
    // Liquid blob colors based on accent color
    final color1 = widget.accentColor ?? (isDark ? const Color(0xFF7B2FBE) : const Color(0xFFFF2D55)); // Apple Music pink
    
    // Generate a complementary/analogous color for the second blob
    final hsl = HSLColor.fromColor(color1);
    final color2 = hsl.withHue((hsl.hue + 40) % 360).toColor();

    return Stack(
      children: [
        // Base solid color
        Container(color: baseColor),
        
        // Liquid Blobs
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return CustomPaint(
              painter: _LiquidPainter(
                progress: _controller.value,
                color1: color1,
                color2: color2,
                isDark: isDark,
              ),
              size: Size.infinite,
            );
          },
        ),
        
        // Massive blur overlay to create the mesh gradient effect
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
            child: Container(
              color: Colors.transparent,
            ),
          ),
        ),
        
        // Content
        widget.child,
      ],
    );
  }
}

class _LiquidPainter extends CustomPainter {
  final double progress;
  final Color color1;
  final Color color2;
  final bool isDark;

  _LiquidPainter({
    required this.progress,
    required this.color1,
    required this.color2,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Opacity based on theme (Light mode needs slightly lighter blobs to not overpower)
    final alpha1 = isDark ? 0.7 : 0.4;
    final alpha2 = isDark ? 0.6 : 0.3;
    final alpha3 = isDark ? 0.5 : 0.25;

    final paint1 = Paint()
      ..color = color1.withValues(alpha: alpha1)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final paint2 = Paint()
      ..color = color2.withValues(alpha: alpha2)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final paint3 = Paint()
      ..color = color1.withValues(alpha: alpha3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    final cx = size.width / 2;
    final cy = size.height / 2;

    // Blob 1: Large circular orbit
    final x1 = cx + cos(progress * 2 * pi) * cx * 0.8;
    final y1 = cy + sin(progress * 2 * pi) * cy * 0.8;
    canvas.drawCircle(Offset(x1, y1), size.width * 0.7, paint1);

    // Blob 2: Opposite circular orbit, slightly slower
    final x2 = cx + cos(progress * -1.5 * pi + pi) * cx * 0.6;
    final y2 = cy + sin(progress * -1.5 * pi + pi) * cy * 0.6;
    canvas.drawCircle(Offset(x2, y2), size.width * 0.8, paint2);

    // Blob 3: Figure 8 motion in the center
    final x3 = cx + sin(progress * 4 * pi) * cx * 0.4;
    final y3 = cy + sin(progress * 2 * pi) * cy * 0.6;
    canvas.drawCircle(Offset(x3, y3), size.width * 0.6, paint3);
  }

  @override
  bool shouldRepaint(covariant _LiquidPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.color1 != color1 ||
      oldDelegate.isDark != isDark;
}

/// AnimatedBuilder using AnimatedWidget pattern
class AnimatedBuilder extends AnimatedWidget {
  final Widget Function(BuildContext context, Widget? child) builder;
  final Widget? child;

  const AnimatedBuilder({
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
