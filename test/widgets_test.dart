import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/theme/app_theme.dart';
import 'package:honestsignal/features/measurement/domain/data_budget.dart';
import 'package:honestsignal/features/measurement/domain/measurement_state.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/scoring.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';
import 'package:honestsignal/features/measurement/presentation/screens/how_it_works_screen.dart';
import 'package:honestsignal/features/measurement/presentation/widgets/budget_meter.dart';
import 'package:honestsignal/features/measurement/presentation/widgets/history_chart.dart';
import 'package:honestsignal/features/measurement/presentation/widgets/pause_banner.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';
import 'package:honestsignal/shared/widgets/pro_lock.dart';
import 'package:honestsignal/shared/widgets/signal_bars.dart';

Widget _host(Widget child, {Brightness brightness = Brightness.light}) =>
    MaterialApp(
      theme: brightness == Brightness.light ? AppTheme.light() : AppTheme.dark(),
      home: Scaffold(body: child),
    );

SignalSample _sample(DateTime at, int bars) => SignalSample(
      timestamp: at,
      kind: NetworkKind.wifi,
      bars: bars,
      composite: bars / 5,
      latencyMs: 40,
      jitterMs: 5,
      throughputKbps: 12000,
      lossRatio: 0,
      probesSent: 4,
      bytesUsed: 2800,
    );

void main() {
  group('SignalBars', () {
    for (final theme in BarTheme.values) {
      testWidgets('renders every level in the ${theme.label} theme',
          (tester) async {
        for (var bars = 0; bars <= 5; bars++) {
          await tester.pumpWidget(
            _host(SignalBars(bars: bars, theme: theme, animate: false)),
          );
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
      });
    }

    testWidgets('clamps a score outside 0..5 instead of painting off-canvas',
        (tester) async {
      await tester.pumpWidget(_host(const SignalBars(bars: 99, animate: false)));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(_host(const SignalBars(bars: -3, animate: false)));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders in dark mode', (tester) async {
      await tester.pumpWidget(
        _host(const SignalBars(bars: 3, animate: false), brightness: Brightness.dark),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('BudgetMeter', () {
    testWidgets('shows usage against the limit', (tester) async {
      await tester.pumpWidget(_host(BudgetMeter(
        budget: DataBudget(
          dayKey: '2026-08-07',
          bytesUsed: 5 * 1024 * 1024,
          limitBytes: 25 * 1024 * 1024,
        ),
      )));

      expect(find.text('5.0 MB / 25 MB'), findsOneWidget);
      expect(find.textContaining('estimate'), findsOneWidget);
    });

    testWidgets('says what actually stops when the budget is spent',
        (tester) async {
      await tester.pumpWidget(_host(BudgetMeter(
        budget: DataBudget(
          dayKey: '2026-08-07',
          bytesUsed: 25 * 1024 * 1024,
          limitBytes: 25 * 1024 * 1024,
        ),
      )));

      // Not just "budget reached" — the user needs to know latency keeps going.
      expect(find.textContaining('Latency probes continue'), findsOneWidget);
    });
  });

  group('PauseBanner', () {
    testWidgets('is invisible when nothing is paused', (tester) async {
      await tester.pumpWidget(_host(
        PauseBanner(pause: MeasurementPause.none, onOpenSettings: () {}),
      ));
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('offers a way out of the cellular opt-out', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_host(PauseBanner(
        pause: MeasurementPause.cellularOptOut,
        onOpenSettings: () => tapped = true,
      )));

      expect(find.textContaining('mobile data'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      expect(tapped, isTrue);
    });

    testWidgets('backgrounding is not surfaced as a fault', (tester) async {
      // On Android the service keeps measuring; on iOS the freshness line
      // already explains it. A banner here would be noise.
      await tester.pumpWidget(_host(
        PauseBanner(pause: MeasurementPause.appBackgrounded, onOpenSettings: () {}),
      ));
      expect(find.byType(TextButton), findsNothing);
    });
  });

  group('HistoryChart', () {
    testWidgets('says so when the window is empty', (tester) async {
      await tester.pumpWidget(_host(HistoryChart(
        samples: const [],
        window: const Duration(hours: 1),
        now: DateTime(2026, 8, 7, 12),
      )));
      expect(find.textContaining('No samples'), findsOneWidget);
    });

    testWidgets('draws a populated window without overflowing', (tester) async {
      final now = DateTime(2026, 8, 7, 12);
      await tester.pumpWidget(_host(HistoryChart(
        samples: [
          for (var i = 60; i >= 0; i -= 5)
            _sample(now.subtract(Duration(minutes: i)), i % 6),
        ],
        window: const Duration(hours: 1),
        now: now,
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('ProLock explains the feature before asking for money',
      (tester) async {
    var unlocked = false;
    await tester.pumpWidget(_host(ProLock(
      title: 'History is a Pro feature',
      body: 'See how your connection held up.',
      onUnlock: () => unlocked = true,
    )));

    expect(find.text('History is a Pro feature'), findsOneWidget);
    expect(find.text('See how your connection held up.'), findsOneWidget);
    await tester.tap(find.text('See Pro'));
    expect(unlocked, isTrue);
  });

  testWidgets('the scoring method is documented in the app', (tester) async {
    // A tall surface so the lazily-built list renders in one pass; the point of
    // the test is the content, not the scrolling.
    // Tall enough that the lazily-built list renders in one pass, including the
    // retention sentence at the very bottom. The screen grew when the
    // unusable-latency cap was documented, so this has headroom on purpose.
    tester.view.physicalSize = const Size(1080, 12000);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const HowItWorksScreen(),
    ));
    await tester.pump();

    // The product claim is "this number is honest", so the method, the weights
    // and the meaning of each level must all be readable without leaving the
    // app or trusting the store listing.
    expect(find.text('Round-trip probes'), findsOneWidget);
    expect(find.text('A real transfer'), findsOneWidget);
    expect(find.text('Putting it together'), findsOneWidget);
    expect(find.text('30%'), findsNWidgets(2));
    // The glossary rows are RichText, so the finder has to look inside spans.
    expect(
      find.textContaining('No usable connection', findRichText: true),
      findsOneWidget,
    );
    expect(find.textContaining('deleted within 25 hours'), findsOneWidget);
    // The latency caps' release figures are named on screen, not described, so
    // a reader can reproduce every number the method uses. Interpolated from
    // the model, so this fails if the copy and the constants drift apart.
    expect(
      find.textContaining(
        '${SignalScoring.poorLatencyReleaseMs.round()} ms and '
        '${SignalScoring.unusableLatencyReleaseMs.round()} ms',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
