import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/settings/domain/app_settings.dart';

/// The app's signal indicator, in the same three shapes the Android status-bar
/// icon can take. `IndicatorIcons.kt` draws the same geometry natively — change
/// the two together so the in-app meter and the status-bar icon agree.
class SignalBars extends StatelessWidget {
  const SignalBars({
    super.key,
    required this.bars,
    this.theme = BarTheme.bars,
    this.size = 96,
    this.color,
    this.animate = true,
  });

  final int bars;
  final BarTheme theme;
  final double size;
  final Color? color;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final active = color ?? AppColors.of(context).forBars(bars);
    final inactive = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14);

    final painter = CustomPaint(
      size: Size(size, size * 0.82),
      painter: _SignalBarsPainter(
        bars: bars.clamp(0, 5).toDouble(),
        theme: theme,
        active: active,
        inactive: inactive,
      ),
    );

    if (!animate) return painter;

    // Animating the fill rather than snapping keeps a one-bar drop from reading
    // as a glitch, and matches the hysteresis in the scoring model.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: bars.clamp(0, 5).toDouble()),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      builder: (context, value, _) => CustomPaint(
        size: Size(size, size * 0.82),
        painter: _SignalBarsPainter(
          bars: value,
          theme: theme,
          active: active,
          inactive: inactive,
        ),
      ),
    );
  }
}

class _SignalBarsPainter extends CustomPainter {
  _SignalBarsPainter({
    required this.bars,
    required this.theme,
    required this.active,
    required this.inactive,
  });

  final double bars;
  final BarTheme theme;
  final Color active;
  final Color inactive;

  @override
  void paint(Canvas canvas, Size size) {
    switch (theme) {
      case BarTheme.bars:
        _paintBars(canvas, size);
      case BarTheme.dots:
        _paintDots(canvas, size);
      case BarTheme.wave:
        _paintWave(canvas, size);
    }
  }

  /// Fractional fill: a bar mid-transition is drawn partly lit, so the
  /// animation reads as a level changing rather than blocks blinking.
  Color _colorFor(int index) {
    final fill = (bars - index).clamp(0.0, 1.0);
    return Color.lerp(inactive, active, fill)!;
  }

  void _paintBars(Canvas canvas, Size size) {
    const count = 5;
    final gap = size.width * 0.055;
    final barWidth = (size.width - gap * (count - 1)) / count;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < count; i++) {
      final heightFactor = 0.32 + (i / (count - 1)) * 0.68;
      final barHeight = size.height * heightFactor;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          i * (barWidth + gap),
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        Radius.circular(barWidth * 0.3),
      );
      canvas.drawRRect(rect, paint..color = _colorFor(i));
    }
  }

  void _paintDots(Canvas canvas, Size size) {
    const count = 5;
    final gap = size.width * 0.06;
    final slot = (size.width - gap * (count - 1)) / count;
    final paint = Paint()..style = PaintingStyle.fill;
    final centreY = size.height * 0.62;

    for (var i = 0; i < count; i++) {
      final radius = slot * (0.28 + (i / (count - 1)) * 0.22);
      canvas.drawCircle(
        Offset(i * (slot + gap) + slot / 2, centreY),
        radius,
        paint..color = _colorFor(i),
      );
    }
  }

  void _paintWave(Canvas canvas, Size size) {
    const count = 5;
    final origin = Offset(size.width / 2, size.height * 0.94);
    final maxRadius = size.height * 0.92;
    final stroke = size.height * 0.1;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    // The innermost mark is a filled dot — a zero-radius arc would vanish.
    canvas.drawCircle(origin, stroke * 0.62, Paint()..color = _colorFor(0));

    for (var i = 1; i < count; i++) {
      final radius = maxRadius * (i / (count - 1)) * 0.92;
      canvas.drawArc(
        Rect.fromCircle(center: origin, radius: radius),
        math.pi * 1.22,
        math.pi * 0.56,
        false,
        paint..color = _colorFor(i),
      );
    }
  }

  @override
  bool shouldRepaint(_SignalBarsPainter old) =>
      old.bars != bars ||
      old.theme != theme ||
      old.active != active ||
      old.inactive != inactive;
}
