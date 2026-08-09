import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/utils/formatters.dart';
import '../../domain/measurement_state.dart';

/// How old the reading is, stated plainly.
///
/// This is a product requirement, not decoration: iOS cannot measure while the
/// app is closed, so a score with no timestamp would be a lie by omission.
class FreshnessLine extends StatefulWidget {
  const FreshnessLine({super.key, required this.state});

  final MeasurementState state;

  @override
  State<FreshnessLine> createState() => _FreshnessLineState();
}

class _FreshnessLineState extends State<FreshnessLine> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The age text has to move on its own even when no new sample arrives —
    // "just now" going stale silently is the failure mode this line exists to
    // prevent.
    _ticker = Timer.periodic(
      const Duration(seconds: 5),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;

    if (!state.hasReading) {
      return Text(
        'No reading yet',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      );
    }

    final age = Format.age(state.sample.timestamp);
    final stale = DateTime.now().difference(state.sample.timestamp) >
        const Duration(minutes: 2);

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              state.measuring ? Icons.sync : Icons.schedule,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            // Flexible, and allowed to wrap rather than ellipsize: at the top
            // of the iOS accessibility range this line is wider than a narrow
            // handset, and "Measured 3 min ago" truncated to "Measured 3 mi…"
            // would drop the one fact this widget exists to state.
            Flexible(
              child: Text(
                state.measuring ? 'Measuring now' : 'Measured $age',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: stale && !state.measuring
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        if (stale && !state.measuring && Platform.isIOS) ...[
          const SizedBox(height: 4),
          Text(
            'iOS stops apps measuring in the background. Pull down to refresh.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}
