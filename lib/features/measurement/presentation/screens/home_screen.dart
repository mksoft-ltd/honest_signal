import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../app/providers.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../shared/widgets/metric_tile.dart';
import '../../../../shared/widgets/signal_bars.dart';
import '../../../settings/domain/app_settings.dart';
import '../../domain/measurement_state.dart';
import '../../domain/scoring.dart';
import '../../domain/signal_sample.dart';
import '../widgets/budget_meter.dart';
import '../widgets/freshness_line.dart';
import '../widgets/pause_banner.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(measurementControllerProvider).start();
      ref.read(indicatorControllerProvider).refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(measurementControllerProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        controller.setForeground(true);
        ref.read(indicatorControllerProvider).refresh();
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        controller.setForeground(false);
      case AppLifecycleState.inactive:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(measurementControllerProvider);
    final state = controller.state;
    final settings = ref.watch(effectiveSettingsProvider);
    final isPro = ref.watch(isProProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Honest Signal'),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: const Icon(Icons.show_chart),
            onPressed: () => context.push('/history'),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => controller.measureNow(forceTransfer: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: AppSpacing.page,
            children: [
              _Verdict(state: state, theme: settings.barTheme),
              const SizedBox(height: 12),
              FreshnessLine(state: state),
              const SizedBox(height: 20),
              PauseBanner(
                pause: state.pause,
                onOpenSettings: () => context.push('/settings'),
              ),
              _MetricGrid(sample: state.sample, hasReading: state.hasReading),
              const SizedBox(height: 20),
              BudgetMeter(budget: state.budget),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: state.measuring
                    ? null
                    : () => controller.measureNow(forceTransfer: true),
                icon: state.measuring
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(state.measuring ? 'Measuring…' : 'Measure now'),
              ),
              if (!isPro) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => context.push('/pro'),
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Honest Signal Pro'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Verdict extends StatelessWidget {
  const _Verdict({required this.state, required this.theme});

  final MeasurementState state;
  final BarTheme theme;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final sample = state.sample;
    final colour = AppColors.of(context).forBars(sample.bars);
    final showReading = state.hasReading;

    return Column(
      children: [
        const SizedBox(height: 12),
        SignalBars(bars: showReading ? sample.bars : 0, theme: theme, size: 132),
        const SizedBox(height: 20),
        Text(
          showReading ? sample.verdict : 'Measuring…',
          textAlign: TextAlign.center,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: showReading ? colour : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          showReading
              ? sample.verdictDetail
              : 'Sending probes to see what this connection can actually do.',
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.sample, required this.hasReading});

  final SignalSample sample;
  final bool hasReading;

  @override
  Widget build(BuildContext context) {
    final scores = AppColors.of(context);
    final tiles = <Widget>[
      MetricTile(
        label: 'Network',
        value: sample.kind.label,
        caption: sample.networkDetail ?? _platformCaption(),
        icon: Icons.router_outlined,
      ),
      MetricTile(
        label: 'Latency',
        value: hasReading ? Format.latency(sample.latencyMs) : '—',
        caption: 'Round trip, median',
        icon: Icons.timer_outlined,
      ),
      MetricTile(
        label: 'Speed',
        value: hasReading ? Format.throughput(sample.throughputKbps) : '—',
        caption: sample.throughputIsStale
            ? 'From the last transfer sample'
            : 'Measured download sample',
        icon: Icons.download_outlined,
        emphasis: hasReading &&
                sample.throughputKbps != null &&
                sample.throughputKbps! <= 0
            ? scores.dead
            : null,
      ),
      MetricTile(
        label: 'Jitter',
        value: hasReading ? Format.jitter(sample.jitterMs) : '—',
        caption: 'Variation between probes',
        icon: Icons.ssid_chart,
      ),
      MetricTile(
        label: 'Lost probes',
        value: hasReading ? Format.lossPercent(sample.lossRatio) : '—',
        caption: '${sample.probesSent} sent this cycle',
        icon: Icons.link_off,
        emphasis: hasReading && sample.lossRatio >= SignalScoring.severeLossRatio
            ? scores.dead
            : null,
      ),
      MetricTile(
        label: 'Score',
        value: hasReading ? '${sample.bars}/5' : '—',
        caption: hasReading
            ? '${(sample.composite * 100).round()} / 100 composite'
            : null,
        icon: Icons.speed,
      ),
    ];

    // Rows size to their tallest tile rather than to a fixed aspect ratio.
    //
    // A ratio is a guess about height expressed in units of width, so it only
    // holds at the width it was chosen for: 1.85 gave the tiles 71.6 dp of
    // content box at 411 dp wide against the 80 dp they need, and dropping it
    // far enough to clear a 411 dp phone still overflowed a 360 dp one. It also
    // fails at any accessibility text scale, where the height needed grows and
    // the height available does not. Letting the content set the height cannot
    // fail either way.
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 10),
          IntrinsicHeight(
            // `stretch` gives both tiles in a row the taller one's height, so
            // the grid still reads as a grid.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: tiles[i]),
                const SizedBox(width: 10),
                if (i + 1 < tiles.length)
                  Expanded(child: tiles[i + 1])
                else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ],
    );
  }

  static String? _platformCaption() =>
      Platform.isIOS ? 'As reported by iOS' : 'As reported by Android';
}
