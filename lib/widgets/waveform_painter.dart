import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class WaveformPainter extends StatefulWidget {
  final bool isPlaying;
  final Color? color;
  final double height;

  const WaveformPainter({
    super.key,
    this.isPlaying = false,
    this.color,
    this.height = 60,
  });

  @override
  State<WaveformPainter> createState() => _WaveformPainterState();
}

class _WaveformPainterState extends State<WaveformPainter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );
    if (widget.isPlaying) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(WaveformPainter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPlaying && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isPlaying && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _WaveformCustomPainter(
              progress: _controller.value,
              color: widget.color ?? AppColors.neonBlue,
              isPlaying: widget.isPlaying,
            ),
          );
        },
      ),
    );
  }
}

class _WaveformCustomPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isPlaying;

  _WaveformCustomPainter({
    required this.progress,
    required this.color,
    required this.isPlaying,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final barWidth = 3.0;
    final gap = 2.5;
    final totalBarWidth = barWidth + gap;
    final barCount = (size.width / totalBarWidth).floor();

    for (int i = 0; i < barCount; i++) {
      final x = i * totalBarWidth;
      final normalizedX = i / barCount;

      // Create wave pattern
      double amplitude;
      if (isPlaying) {
        amplitude = sin(normalizedX * pi * 4 + progress * 2 * pi) *
                sin(normalizedX * pi * 2 + progress * pi) *
                0.8 +
            sin(normalizedX * pi * 6 - progress * 3 * pi) * 0.2;
        amplitude = amplitude.abs();
        // Add some randomness feel
        amplitude *= (0.3 + 0.7 * sin(normalizedX * pi));
      } else {
        // Static small bars when paused
        amplitude = 0.15 + 0.1 * sin(normalizedX * pi * 3);
      }

      final barHeight = max(4.0, amplitude * size.height * 0.8);

      final gradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [
          color.withValues(alpha: 0.3),
          color.withValues(alpha: 0.8),
          color,
        ],
      );

      final rect = Rect.fromLTWH(x, centerY - barHeight / 2, barWidth, barHeight);
      final paint = Paint()
        ..shader = gradient.createShader(rect)
        ..style = PaintingStyle.fill;

      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rrect, paint);

      // Glow effect
      if (isPlaying && amplitude > 0.5) {
        final glowPaint = Paint()
          ..color = color.withValues(alpha: amplitude * 0.15)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
        canvas.drawRRect(rrect, glowPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformCustomPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.isPlaying != isPlaying;
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
