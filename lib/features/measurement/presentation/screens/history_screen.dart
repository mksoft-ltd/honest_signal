import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/pro_lock.dart';
import '../../data/history_export.dart';
import '../../data/history_repository.dart';
import '../../domain/history_insights.dart';
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
    final now = DateTime.now();
    final samples = controller.historySince(_window);
    // Beyond a day, rows are compacted to one per five minutes, so each one
    // has to be allowed to cover its bucket.
    final maxHold = _window > HistoryRepository.defaultRetention
        ? HistoryInterval.maximumFreshness
        : HistoryInterval.maximumHold(expectedInterval);

    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (isPro)
            PopupMenuButton<_ExportFormat>(
              tooltip: 'Export',
              icon: const Icon(Icons.ios_share),
              enabled: samples.isNotEmpty,
              onSelected: (format) =>
                  _export(format, samples, now: now, maxHold: maxHold),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _ExportFormat.pdf,
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf_outlined),
                    title: Text('Report (PDF)'),
                    subtitle: Text('Chart, drop-outs and times'),
                  ),
                ),
                PopupMenuItem(
                  value: _ExportFormat.csv,
                  child: ListTile(
                    leading: Icon(Icons.table_chart_outlined),
                    title: Text('Readings (CSV)'),
                    subtitle: Text('Every stored reading'),
                  ),
                ),
              ],
            ),
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
          : _LockedHistory(
              samples: controller.historySince(const Duration(hours: 24)),
              now: now,
              maxHold: maxHold,
            ),
    );
  }

  Future<void> _export(
    _ExportFormat format,
    List<SignalSample> samples, {
    required DateTime now,
    required Duration maxHold,
  }) async {
    final stamp = HistoryExport.fileStamp(now);
    final period = _windowLabel(_window);
    try {
      switch (format) {
        case _ExportFormat.pdf:
          await HistoryExport.share(
            bytes: await HistoryExport.pdfReport(
              samples: samples,
              window: _window,
              now: now,
              maxHold: maxHold,
            ),
            fileName: 'honest-signal-report-$stamp.pdf',
            mimeType: 'application/pdf',
            subject: 'Connection report, $period',
          );
        case _ExportFormat.csv:
          await HistoryExport.share(
            bytes: Uint8List.fromList(utf8.encode(HistoryExport.csv(samples))),
            fileName: 'honest-signal-readings-$stamp.csv',
            mimeType: 'text/csv',
            subject: 'Connection readings, $period',
          );
      }
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create the export.')),
      );
    }
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

/// The free tier's history screen. Samples are recorded on every tier, so the
/// lock shows the user's own last day, blurred, and says what it contains —
/// "you already have this, here is how to see it" rather than a bare padlock.
class _LockedHistory extends ConsumerWidget {
  const _LockedHistory({
    required this.samples,
    required this.now,
    required this.maxHold,
  });

  final List<SignalSample> samples;
  final DateTime now;
  final Duration maxHold;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teaser = ref.watch(proTeaserProvider);
    final body = teaser == null
        ? 'See how your connection held up over the last hour, day, week or '
              'month, and export a report of the drop-outs you keep noticing to send '
              'to your provider.'
        : teaser.dropouts > 0
        ? 'Honest Signal has already recorded ${teaser.dropoutPhrase} on this '
              'phone in the last 24 hours. Pro shows when each one happened and '
              'how long it lasted, so you can prove the drop-outs are real.'
        : 'Honest Signal has already recorded ${teaser.readings} readings on '
              'this phone in the last 24 hours. Pro shows them as a chart, so '
              'you can prove the drop-outs you notice are real.';
    return ProLock(
      title: 'History is a Pro feature',
      body: body,
      onUnlock: () => context.push('/pro'),
      preview: teaser == null
          ? null
          : ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: IgnorePointer(
                    child: HistoryChart(
                      samples: samples,
                      window: const Duration(hours: 24),
                      now: now,
                      maxHold: maxHold,
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

enum _ExportFormat { pdf, csv }

String _windowLabel(Duration window) => switch (window.inHours) {
  1 => 'last hour',
  24 => 'last 24 hours',
  _ => 'last ${window.inDays} days',
};

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

  static const windows = [
    Duration(hours: 1),
    Duration(hours: 24),
    Duration(days: 7),
    Duration(days: 30),
  ];

  @override
  Widget build(BuildContext context) {
    final stats = HistoryStats.from(samples, end: now, maxHold: maxHold);
    final drops = HistoryInsights.dropouts(samples, end: now, maxHold: maxHold);
    final networks = HistoryInsights.byNetwork(
      samples,
      end: now,
      maxHold: maxHold,
    );
    final scores = AppColors.of(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListView(
      padding: AppSpacing.page,
      children: [
        SegmentedButton<Duration>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: Duration(hours: 1), label: Text('1 h')),
            ButtonSegment(value: Duration(hours: 24), label: Text('24 h')),
            ButtonSegment(value: Duration(days: 7), label: Text('7 d')),
            ButtonSegment(value: Duration(days: 30), label: Text('30 d')),
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
            label: 'Drop-outs',
            value: '${drops.length}',
            colour: drops.isEmpty ? null : scores.dead,
          ),
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
          if (networks.length > 1 ||
              (networks.isNotEmpty && networks.first.dropouts > 0)) ...[
            const _Heading('By network'),
            for (final network in networks) _NetworkRow(network: network),
          ],
          const _Heading('Drop-outs'),
          if (drops.isEmpty)
            Text('None in the ${_windowLabel(window)}.', style: muted)
          else
            for (final drop in drops.reversed.take(50))
              _DropoutRow(drop: drop, showDate: window > windows[1]),
          if (drops.length > 50)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '${drops.length - 50} earlier drop-outs are in the PDF report.',
                style: muted,
              ),
            ),
          const SizedBox(height: 20),
          Text(
            'While open, samples are recorded on score or network changes and '
            'at least every 30 seconds. '
            '${Platform.isAndroid ? 'Android background history keeps bar and network changes plus a one-minute steady reading. ' : ''}'
            'A drop-out is a stretch at 0–1 bars; gaps with no fresh reading '
            'end one rather than being guessed. The last '
            '${HistoryRepository.defaultRetention.inHours} hours are kept in '
            'full; older readings, up to '
            '${HistoryRepository.proRetention.inDays} days, are kept as the '
            'worst reading in each '
            '${HistoryRepository.compactionBucket.inMinutes} minutes.',
            style: muted,
          ),
        ],
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 6),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}

class _DropoutRow extends StatelessWidget {
  const _DropoutRow({required this.drop, required this.showDate});

  final Dropout drop;
  final bool showDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final start = Format.clockTime(drop.start);
    final day = showDate ? '${Format.shortDate(drop.start)} ' : '';
    final until = drop.ongoing ? 'now' : Format.clockTime(drop.end);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: AppColors.of(context).forBars(drop.worstBars),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$day$start – $until · ${drop.kind.label}',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          Text(
            Format.duration(drop.duration),
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

class _NetworkRow extends StatelessWidget {
  const _NetworkRow({required this.network});

  final NetworkBreakdown network;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final avg = network.averageBars;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(network.kind.label, style: theme.textTheme.bodyMedium),
                Text(
                  '${Format.duration(network.measured)} measured · '
                  '${Format.percent(network.poorFraction)} at 0–1 bars · '
                  '${network.dropouts} drop-out${network.dropouts == 1 ? '' : 's'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${avg.toStringAsFixed(1)} / 5',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.of(context).forBars(avg.round()),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
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
