import 'dart:io';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../data/history_repository.dart';
import '../../domain/scoring.dart';

/// The scoring model, in plain language.
///
/// The whole product claim is "this number is honest", so the method is
/// documented inside the app rather than only in the store listing.
class HowItWorksScreen extends StatelessWidget {
  const HowItWorksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('How the score works')),
      body: ListView(
        padding: AppSpacing.page,
        children: [
          Text(
            'Your phone\'s signal icon shows how loudly the nearest mast or '
            'router is shouting. It says nothing about whether data is getting '
            'through. Honest Signal measures the connection instead of listening '
            'to the radio.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),
          const _Step(
            number: '1',
            title: 'Round-trip probes',
            body:
                'Four small HTTPS requests go to well-known connectivity-check '
                'endpoints run by Google and Cloudflare — the same ones your '
                'phone already uses to detect captive portals. The median '
                'round-trip time becomes the latency score.',
          ),
          const _Step(
            number: '2',
            title: 'Jitter',
            body:
                'How much those four round trips disagree with each other. '
                'Steady 90 ms is far better for calls than a connection that '
                'swings between 30 ms and 400 ms.',
          ),
          // Not const: the release figures are interpolated from the model so
          // the screen cannot quote a threshold the code no longer uses. Every
          // other rule on this screen names its exact number, and the product
          // claim is that the method is not a secret — so these two are named
          // rather than described.
          _Step(
            number: '3',
            title: 'Lost probes',
            body:
                'Any probe that times out counts as loss. Losing a third or '
                'more caps the score at one bar however fast the rest were. '
                'Slow round trips are capped too, even between download '
                'samples: 600 ms or more can never show above two bars, and '
                'one second or more never above one. Once one of those caps '
                'applies it holds until the round trip comes back below '
                '${SignalScoring.poorLatencyReleaseMs.round()} ms and '
                '${SignalScoring.unusableLatencyReleaseMs.round()} ms '
                'respectively, so a connection hovering right on the line does '
                'not make the indicator flicker.',
          ),
          const _Step(
            number: '4',
            title: 'A real transfer',
            body:
                'Periodically Honest Signal downloads a sized sample (about '
                '120 KB) and times it, discounting connection setup. This is '
                'what catches the connection that answers pings instantly and '
                'then stalls on anything real — if that download fails, the '
                'score is capped at '
                '${SignalScoring.transferFailureBarCap} bars no matter how good '
                'the pings looked.',
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Putting it together',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _WeightRow(
                    label: 'Lost probes',
                    weight: SignalScoring.lossWeight,
                  ),
                  _WeightRow(
                    label: 'Latency',
                    weight: SignalScoring.latencyWeight,
                  ),
                  _WeightRow(
                    label: 'Speed',
                    weight: SignalScoring.throughputWeight,
                  ),
                  _WeightRow(
                    label: 'Jitter',
                    weight: SignalScoring.jitterWeight,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Each part scores 0 to 100, then they are blended by these '
                    'weights and mapped to bars. A small margin either side of '
                    'each boundary stops the indicator flickering when you sit '
                    'right on the edge.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'What the bars mean',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          for (var bars = 5; bars >= 0; bars--)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    TextSpan(
                      text: '$bars — ${SignalScoring.verdict(bars)}. ',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    TextSpan(text: SignalScoring.verdictDetail(bars)),
                  ],
                ),
              ),
            ),
          if (Platform.isAndroid) ...[
            const SizedBox(height: 24),
            Text(
              'About the status-bar icon',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Android draws every status-bar icon in one colour it chooses '
              'itself — white on a dark bar, black on a light one — so a '
              'green, amber or red icon up there is not something any app can '
              'ask for. What we can do is shape: the icon sits on a solid '
              'plate so it stays readable over any wallpaper and looks nothing '
              'like your phone\'s own signal bars. You can turn the plate off '
              'in Settings. The score\'s colour still shows in the '
              'notification itself, and in the floating bubble if you use it. '
              'On Android 16 the indicator also appears as a small chip '
              'labelled HS next to the clock, which keeps it out of the icon '
              'row that gets cut short when a lot of apps are competing for '
              'space.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'The probes carry no identifiers and nothing about you or your '
            'network ever leaves your phone. Every reading is stored on this '
            'device and deleted within '
            '${HistoryRepository.defaultRetention.inHours} hours.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.title, required this.body});

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightRow extends StatelessWidget {
  const _WeightRow({required this.label, required this.weight});

  final String label;
  final double weight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: weight,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${(weight * 100).round()}%',
            style: theme.textTheme.bodySmall?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
