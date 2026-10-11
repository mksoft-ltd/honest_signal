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
import '../../data/measurement_controller.dart';
import '../../domain/diagnosis.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(measurementControllerProvider).start();
      ref.read(indicatorControllerProvider).refresh();
      ref.read(reviewPrompterProvider).recordUse();
      _openLaunchRoute();
    });
    // A fresh good reading is the moment to ask for a review; the prompter
    // owns every other condition, including never asking twice a session.
    _reviewSubscription = ref.listenManual(measurementControllerProvider, (
      _,
      controller,
    ) {
      final state = controller.state;
      if (state.hasReading && !state.measuring && state.sample.bars >= 4) {
        ref
            .read(reviewPrompterProvider)
            .maybePrompt(currentBars: state.sample.bars);
      }
    });
  }

  ProviderSubscription<MeasurementController>? _reviewSubscription;

  /// Routes a notification may ask for. Anything else is ignored, so a stray
  /// intent extra can never navigate somewhere unexpected.
  static const _launchRoutes = {'/history'};

  /// A drop-out alert opens the app on History, where the drop-out is listed.
  Future<void> _openLaunchRoute() async {
    final route = await ref.read(indicatorChannelProvider).takeLaunchRoute();
    if (route == null || !_launchRoutes.contains(route) || !mounted) return;
    context.push(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reviewSubscription?.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = ref.read(measurementControllerProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        controller.setForeground(true);
        adoptIndicatorTurnOff(ref).then((_) {
          if (mounted) ref.read(indicatorControllerProvider).refresh();
        });
        ref.read(reviewPrompterProvider).recordUse();
        _openLaunchRoute();
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
    final teaser = ref.watch(proTeaserProvider);

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
              if (state.hasReading)
                if (Diagnosis.of(state.sample) case final diagnosis?) ...[
                  _DiagnosisCard(diagnosis: diagnosis),
                  const SizedBox(height: 16),
                ],
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
                  // Names the user's own recorded drop-outs when there are
                  // any: a reason to look, rather than a generic upsell.
                  label: Text(
                    teaser != null && teaser.dropouts > 0
                        ? 'See your ${teaser.dropoutPhrase} from today — Pro'
                        : 'Honest Signal Pro',
                  ),
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
        SignalBars(
          bars: showReading ? sample.bars : 0,
          theme: theme,
          size: 132,
        ),
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

/// Why the score is what it is, in words, and what usually helps.
class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({required this.diagnosis});

  final Diagnosis diagnosis;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lightbulb_outline, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    diagnosis.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    diagnosis.advice,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
            ? 'Transfer sample ${sample.throughputMeasuredAt == null ? 'from earlier' : Format.age(sample.throughputMeasuredAt!)}'
            : 'Measured download sample',
        icon: Icons.download_outlined,
        emphasis:
            hasReading &&
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
        emphasis:
            hasReading && sample.lossRatio >= SignalScoring.severeLossRatio
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
