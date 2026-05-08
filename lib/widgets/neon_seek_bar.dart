import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class NeonSeekBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final Duration bufferedPosition;
  final ValueChanged<Duration>? onChanged;
  final ValueChanged<Duration>? onChangeEnd;
  final Color? activeColor;

  const NeonSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.bufferedPosition,
    this.onChanged,
    this.onChangeEnd,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? AppColors.neonBlue;
    final total = duration.inMilliseconds.toDouble();
    final current = position.inMilliseconds.toDouble().clamp(0.0, total);
    final buffered = bufferedPosition.inMilliseconds.toDouble().clamp(0.0, total);

    return Column(
      children: [
        // Seek slider
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: _NeonThumbShape(color: color),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            overlayColor: color.withValues(alpha: 0.15),
            activeTrackColor: color,
            inactiveTrackColor: Colors.white.withValues(alpha: 0.08),
            secondaryActiveTrackColor: color.withValues(alpha: 0.25),
            trackShape: _NeonTrackShape(),
          ),
          child: Slider(
            min: 0,
            max: total > 0 ? total : 1.0,
            value: current,
            secondaryTrackValue: buffered,
            onChanged: (value) {
              onChanged?.call(Duration(milliseconds: value.toInt()));
            },
            onChangeEnd: (value) {
              onChangeEnd?.call(Duration(milliseconds: value.toInt()));
            },
          ),
        ),
        // Time labels
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
              ),
              Text(
                _formatDuration(duration),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontFeatures: [const FontFeature.tabularFigures()],
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}

class _NeonThumbShape extends SliderComponentShape {
  final Color color;

  _NeonThumbShape({required this.color});

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) {
    return const Size(16, 16);
  }

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    // Outer glow
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(center, 10, glowPaint);

    // Main circle
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, 7, paint);

    // Inner highlight
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center + const Offset(-1.5, -1.5), 2.5, highlightPaint);
  }
}

class _NeonTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final trackHeight = sliderTheme.trackHeight ?? 4;
    final trackLeft = offset.dx + 24;
    final trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final trackWidth = parentBox.size.width - 48;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
