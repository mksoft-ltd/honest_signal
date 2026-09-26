import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/pro_lock.dart';
import '../../data/history_repository.dart';
import '../../domain/signal_sample.dart';
import '../../domain/history_stats.dart';
import '../widgets/history_chart.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  Duration _window = const Duration(hours: 1);

  @override
  Widget build(BuildContext context) {
    final isPro = ref.watch(isProProvider);
    final controller = ref.watch(measurementControllerProvider);
    final settings = ref.watch(effectiveSettingsProvider);
    final indicator = ref.watch(indicatorControllerProvider);
    final expectedInterval = HistoryInterval.expectedInterval(
      foreground: settings.foregroundInterval,
      background: settings.backgroundInterval,
      persistentIndicatorActive:
          Platform.isAndroid &&
          settings.notificationIndicatorEnabled &&
          indicator.status.notificationsAllowed &&
          indicator.status.serviceRunning,
    );
    final maxHold = HistoryInterval.maximumHold(expectedInterval);
    final now = DateTime.now();
    final samples = controller.historySince(_window);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (isPro)
            IconButton(
              tooltip: 'Clear history',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      body: isPro
          ? _HistoryBody(
              window: _window,
              samples: samples,
              now: now,
              maxHold: maxHold,
              onWindowChanged: (value) => setState(() => _window = value),
            )
          : ProLock(
              title: 'History is a Pro feature',
              body:
                  'See how your connection held up over the last hour or day, '
                  'so you can prove the drop-outs you keep noticing are real.',
              onUnlock: () => context.push('/pro'),
            ),
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'All stored samples on this device will be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await ref.read(measurementControllerProvider).clearHistory();
      if (mounted) setState(() {});
    }
  }
}

class _HistoryBody extends StatelessWidget {
  const _HistoryBody({
    required this.window,
    required this.samples,
    required this.now,
    required this.maxHold,
    required this.onWindowChanged,
  });

  final Duration window;
  final List<SignalSample> samples;
  final DateTime now;
  final Duration maxHold;
  final ValueChanged<Duration> onWindowChanged;

  @override
  Widget build(BuildContext context) {
    final stats = HistoryStats.from(samples, end: now, maxHold: maxHold);
    final scores = AppColors.of(context);

    return ListView(
      padding: AppSpacing.page,
      children: [
        SegmentedButton<Duration>(
          segments: const [
            ButtonSegment(value: Duration(hours: 1), label: Text('Last hour')),
            ButtonSegment(value: Duration(hours: 24), label: Text('Last 24 h')),
          ],
          selected: {window},
          onSelectionChanged: (values) => onWindowChanged(values.first),
        ),
        const SizedBox(height: 24),
        HistoryChart(
          samples: samples,
          window: window,
          now: now,
          maxHold: maxHold,
        ),
        const SizedBox(height: 28),
        if (samples.isNotEmpty) ...[
          _StatRow(
            label: 'Time at 4–5 bars',
            value: Format.percent(stats.goodFraction),
            colour: scores.great,
          ),
          _StatRow(
            label: 'Time at 0–1 bars',
            value: Format.percent(stats.badFraction),
            colour: scores.dead,
          ),
          _StatRow(
            label: 'Median latency',
            value: Format.latency(stats.medianLatency),
          ),
          _StatRow(
            label: 'Best speed seen',
            value: Format.throughput(stats.bestThroughput),
          ),
          _StatRow(label: 'Samples stored', value: '${samples.length}'),
          const SizedBox(height: 20),
          Text(
            'While open, samples are recorded on score or network changes and '
            'at least every 30 seconds. '
            '${Platform.isAndroid ? 'Android background history keeps bar and network changes plus a one-minute steady reading. ' : ''}'
            'Samples '
            'stay here for up to '
            '${HistoryRepository.defaultRetention.inHours} hours.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.colour});

  final String label;
  final String value;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          if (colour != null) ...[
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
