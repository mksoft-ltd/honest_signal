import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/signal_sample.dart';

/// Score-over-time chart, hand-drawn rather than pulled from a charting
/// package: the series is one bounded integer against time, and a CustomPainter
/// keeps the app free of a dependency whose only job would be this one view.
class HistoryChart extends StatelessWidget {
  const HistoryChart({
    super.key,
    required this.samples,
    required this.window,
    required this.now,
  });

  final List<SignalSample> samples;
  final Duration window;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (samples.isEmpty) {
      return SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'No samples in this window yet.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 180,
          child: CustomPaint(
            painter: _HistoryPainter(
              samples: samples,
              start: now.subtract(window),
              end: now,
              gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.45),
              scores: AppColors.of(context),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              Format.clockTime(now.subtract(window)),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            Text(
              'now',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ],
    );
  }
}

class _HistoryPainter extends CustomPainter {
  _HistoryPainter({
    required this.samples,
    required this.start,
    required this.end,
    required this.gridColor,
    required this.scores,
  });

  final List<SignalSample> samples;
  final DateTime start;
  final DateTime end;
  final Color gridColor;
  final ScoreColors scores;

  @override
  void paint(Canvas canvas, Size size) {
    final span = end.difference(start).inMilliseconds;
    if (span <= 0) return;

    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var level = 0; level <= 5; level++) {
      final y = size.height - (level / 5) * size.height;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    double xFor(DateTime t) =>
        (t.difference(start).inMilliseconds / span).clamp(0.0, 1.0) * size.width;

    // Each sample holds until the next one, so the series is drawn as steps.
    // Interpolating between them would invent readings the app never took.
    final paint = Paint()..style = PaintingStyle.fill;
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final left = xFor(sample.timestamp);
      final right =
          i == samples.length - 1 ? size.width : xFor(samples[i + 1].timestamp);
      final width = (right - left).clamp(1.0, size.width);
      final height = (sample.bars / 5) * size.height;

      canvas.drawRect(
        Rect.fromLTWH(left, size.height - height, width, height),
        paint..color = scores.forBars(sample.bars).withValues(alpha: 0.85),
      );
    }
  }

  @override
  bool shouldRepaint(_HistoryPainter old) =>
      old.samples != samples ||
      old.start != start ||
      old.end != end ||
      old.gridColor != gridColor ||
      old.scores != scores;
}
