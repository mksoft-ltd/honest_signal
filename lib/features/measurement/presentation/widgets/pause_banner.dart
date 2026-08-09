import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/measurement_state.dart';

/// Explains why measuring stopped, and offers the one action that resumes it.
class PauseBanner extends StatelessWidget {
  const PauseBanner({super.key, required this.pause, required this.onOpenSettings});

  final MeasurementPause pause;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    if (pause == MeasurementPause.none || pause == MeasurementPause.appBackgrounded) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final (message, action) = switch (pause) {
      MeasurementPause.cellularOptOut => (
          'Measuring on mobile data is off, so the score below is from your last '
              'Wi-Fi reading.',
          'Turn on',
        ),
      MeasurementPause.budgetExhausted => (
          "Today's probe data budget is spent. Latency still updates; speed "
              'samples resume at midnight.',
          'Raise limit',
        ),
      _ => ('', ''),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
            TextButton(onPressed: onOpenSettings, child: Text(action)),
          ],
        ),
      ),
    );
  }
}
