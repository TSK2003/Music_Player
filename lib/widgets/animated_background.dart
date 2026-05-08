import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

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
    with TickerProviderStateMixin {
  late AnimationController _particleController;
  late List<_Particle> _particles;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _particleController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();

    _particles = List.generate(15, (_) => _Particle.random(_random));
  }

  @override
  void dispose() {
    _particleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Base gradient
        Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(
                0.0 + (widget.scrollOffset * 0.001),
                -0.3 + (widget.scrollOffset * 0.0005),
              ),
              radius: 1.2,
              colors: [
                widget.accentColor?.withValues(alpha: 0.15) ??
                    AppColors.deepPurple,
                const Color(0xFF0F0A1A),
                AppColors.background,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        ),
        // Particle layer
        AnimatedBuilder(
          animation: _particleController,
          builder: (context, child) {
            return CustomPaint(
              painter: _ParticlePainter(
                particles: _particles,
                progress: _particleController.value,
                accentColor: widget.accentColor ?? AppColors.neonPurple,
              ),
              size: Size.infinite,
            );
          },
        ),
        // Content
        widget.child,
      ],
    );
  }
}

class _Particle {
  final double x;
  final double y;
  final double radius;
  final double speed;
  final double opacity;
  final double phase;

  _Particle({
    required this.x,
    required this.y,
    required this.radius,
    required this.speed,
    required this.opacity,
    required this.phase,
  });

  factory _Particle.random(Random random) {
    return _Particle(
      x: random.nextDouble(),
      y: random.nextDouble(),
      radius: 1.5 + random.nextDouble() * 3.0,
      speed: 0.2 + random.nextDouble() * 0.8,
      opacity: 0.1 + random.nextDouble() * 0.25,
      phase: random.nextDouble() * 2 * pi,
    );
  }
}

class _ParticlePainter extends CustomPainter {
  final List<_Particle> particles;
  final double progress;
  final Color accentColor;

  _ParticlePainter({
    required this.particles,
    required this.progress,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in particles) {
      final t = (progress * particle.speed + particle.phase) % 1.0;
      final dx = particle.x * size.width +
          sin(t * 2 * pi) * 30;
      final dy = (particle.y + t * 0.3) % 1.0 * size.height;

      final paint = Paint()
        ..color = accentColor.withValues(
          alpha: particle.opacity * (0.5 + 0.5 * sin(t * 2 * pi)),
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, particle.radius * 2);

      canvas.drawCircle(Offset(dx, dy), particle.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticlePainter oldDelegate) => true;
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
