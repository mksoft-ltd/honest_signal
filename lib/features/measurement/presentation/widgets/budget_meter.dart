import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../domain/data_budget.dart';

/// Today's probe data spend.
///
/// The app spends the user's data unattended, so the counter is always on
/// screen rather than buried in settings.
class BudgetMeter extends StatelessWidget {
  const BudgetMeter({super.key, required this.budget});

  final DataBudget budget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final exhausted = budget.isExhausted;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The figure is capped at 60% of the row and laid out first, so it
        // keeps its natural width (and stays flush right) at ordinary text
        // sizes but can never push the row past its constraints; the label
        // then takes whatever is left.
        //
        // A flex figure would have been simpler and is wrong: `Flexible` makes
        // it share the free space by flex factor, so it stops sitting against
        // the right edge as soon as it is narrower than its share. `Spacer` is
        // wrong for the opposite reason — it shrinks to zero but cannot make
        // either label give way.
        LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Icon(
                Icons.data_usage,
                size: 15,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Probe data today',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.6),
                child: Text(
                  '${Format.bytes(budget.bytesUsed)} / ${Format.bytes(budget.limitBytes)}',
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: exhausted
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: budget.fraction,
            minHeight: 7,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              exhausted ? theme.colorScheme.error : theme.colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          exhausted
              ? 'Transfer samples paused until midnight. Latency probes continue.'
              : 'An estimate of the bytes Honest Signal spent measuring.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
