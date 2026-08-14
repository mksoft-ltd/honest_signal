import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:honestsignal/app/app.dart';
import 'package:honestsignal/app/providers.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/data/budget_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';
import 'package:honestsignal/features/measurement/presentation/screens/history_screen.dart';
import 'package:honestsignal/features/measurement/presentation/widgets/freshness_line.dart';
import 'package:honestsignal/features/measurement/presentation/widgets/history_chart.dart';
import 'package:honestsignal/features/purchases/data/purchase_controller.dart';
import 'package:honestsignal/features/purchases/presentation/paywall_screen.dart';
import 'package:honestsignal/features/settings/presentation/settings_screen.dart';
import 'package:honestsignal/features/settings/data/settings_repository.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';
import 'package:honestsignal/shared/widgets/pro_lock.dart';

import 'fakes/fake_iap_gateway.dart';
import 'fakes/fake_indicator_channel.dart';
import 'fakes/fake_probe_client.dart';

/// Screen-level behaviour, driven through the real provider graph with the four
/// outside-world seams faked.
///
/// `pumpAndSettle` is never used: the home screen's measurement timer and the
/// freshness ticker are both periodic, so settling never completes and the test
/// would hang instead of failing. Every wait here is an explicit duration.
void main() {
  late LocalStore store;
  late FakeIapGateway gateway;
  late FakeProbeClient probes;
  late FakeConnectivitySource connectivity;

  setUp(() async {
    store = await LocalStore.openInMemory();
    gateway = FakeIapGateway();
    probes = FakeProbeClient(rtts: const [22, 24, 23, 22]);
    connectivity = FakeConnectivitySource();
  });

  tearDown(() async {
    gateway.dispose();
    connectivity.dispose();
    await store.close();
  });

  List<Override> overrides() => [
        localStoreProvider.overrideWithValue(store),
        probeClientProvider.overrideWithValue(probes),
        connectivitySourceProvider.overrideWithValue(connectivity),
        budgetStoreProvider.overrideWithValue(InMemoryBudgetStore()),
        iapGatewayProvider.overrideWithValue(gateway),
        indicatorChannelProvider
            .overrideWithValue(FakeIndicatorChannel(supported: false)),
      ];

  Widget host(Widget child) =>
      ProviderScope(overrides: overrides(), child: MaterialApp(home: child));

  /// Advances a fixed span of time in small steps. Twelve frames covers a full
  /// measurement cycle without reaching the five-second periodic timers.
  Future<void> settle(WidgetTester tester, [int frames = 12]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
  }

  /// Unmounts the tree so the measurement timer and the freshness ticker are
  /// cancelled before the test ends.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  PurchaseController purchasesOf(WidgetTester tester, Type screen) =>
      ProviderScope.containerOf(tester.element(find.byType(screen)))
          .read(purchaseControllerProvider);

  group('paywall', () {
    testWidgets('shows the price the store quoted, never a hardcoded one',
        (tester) async {
      // Both stores reject a price that disagrees with the user's storefront.
      await tester.pumpWidget(host(const PaywallScreen()));
      expect(find.text('Unlock Pro'), findsOneWidget);

      await purchasesOf(tester, PaywallScreen).init();
      await tester.pump();

      expect(find.text('Unlock Pro — £2.99'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('names each Pro feature before asking for money',
        (tester) async {
      await tester.pumpWidget(host(const PaywallScreen()));

      expect(find.text('History and graphs'), findsOneWidget);
      expect(find.text('Your own sampling rate'), findsOneWidget);
      expect(find.text('Indicator themes'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('sells nothing the buyer already has, or cannot get here',
        (tester) async {
      // H-1. These tests run with `Platform.isAndroid == false`, which is the
      // iPhone path — the one the compliance audit failed on.
      await tester.pumpWidget(host(const PaywallScreen()));

      // The daily budget is adjustable on EVERY tier (`clampedForTier` never
      // touches dailyBudgetMb) and both store listings say so. Selling it here
      // made the listing contradict itself.
      expect(find.textContaining('daily data budget'), findsNothing);
      // The background interval is Android-only, so "once an hour" describes
      // nothing an iPhone buyer receives.
      expect(find.textContaining('once an hour'), findsNothing);
      // What is actually true on iOS.
      expect(find.textContaining('every 2 seconds'), findsOneWidget);
      expect(find.textContaining('in the status bar'), findsNothing);
      await unmount(tester);
    });

    testWidgets('explains an unreachable store instead of leaving a dead '
        'button', (tester) async {
      gateway.available = false;
      await tester.pumpWidget(host(const PaywallScreen()));

      await purchasesOf(tester, PaywallScreen).init();
      await tester.pump();

      expect(find.textContaining('store is unreachable'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
      await unmount(tester);
    });

    testWidgets('tapping unlock opens the store sheet', (tester) async {
      await tester.pumpWidget(host(const PaywallScreen()));
      await purchasesOf(tester, PaywallScreen).init();
      await tester.pump();

      await tester.tap(find.text('Unlock Pro — £2.99'));
      await tester.pump();

      expect(gateway.bought, [PurchaseController.proProductId]);
      await unmount(tester);
    });

    testWidgets('a cancelled sheet leaves no spinner behind', (tester) async {
      // The sheet only reports that it opened; the cancel arrives later on the
      // purchase stream, and that is what has to clear the spinner.
      await tester.pumpWidget(host(const PaywallScreen()));
      final controller = purchasesOf(tester, PaywallScreen);
      await controller.init();
      await tester.pump();

      await tester.tap(find.text('Unlock Pro — £2.99'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      gateway.emitNow(PurchaseStatus.canceled);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Unlock Pro — £2.99'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('an owned unlock replaces the button with a receipt',
        (tester) async {
      await SettingsRepository(store.settings).saveProUnlocked(true);
      await tester.pumpWidget(host(const PaywallScreen()));
      await tester.pump();

      expect(find.text('You have Pro'), findsOneWidget);
      expect(find.text('Pro is unlocked on this device.'), findsOneWidget);
      expect(find.textContaining('Unlock Pro'), findsNothing);
      await unmount(tester);
    });

    testWidgets('restore is always reachable, even before the store answers',
        (tester) async {
      // Apple requires a restore path that does not depend on a live purchase.
      await tester.pumpWidget(host(const PaywallScreen()));

      await tester.tap(find.text('Restore purchase'));
      await tester.pump();

      expect(gateway.restoreCalls, greaterThan(0));
      await unmount(tester);
    });
  });

  group('history', () {
    Future<void> seed(int count) async {
      final history = HistoryRepository(store.history);
      final now = DateTime.now();
      for (var i = count; i > 0; i--) {
        await history.record(SignalSample(
          timestamp: now.subtract(Duration(minutes: i)),
          kind: NetworkKind.wifi,
          bars: i % 6,
          composite: (i % 6) / 5,
          latencyMs: 40,
          jitterMs: 5,
          throughputKbps: 20000,
          lossRatio: 0,
          probesSent: 4,
          bytesUsed: 2800,
        ));
      }
    }

    testWidgets('a free install is told what the feature does, not just that '
        'it is locked', (tester) async {
      await tester.pumpWidget(host(const HistoryScreen()));
      await tester.pump();

      expect(find.byType(ProLock), findsOneWidget);
      expect(find.text('History is a Pro feature'), findsOneWidget);
      expect(find.textContaining('drop-outs'), findsOneWidget);
      expect(find.byType(HistoryChart), findsNothing);
      await unmount(tester);
    });

    testWidgets('Pro sees the chart and the summary stats', (tester) async {
      await SettingsRepository(store.settings).saveProUnlocked(true);
      await seed(20);

      await tester.pumpWidget(host(const HistoryScreen()));
      await tester.pump();

      expect(find.byType(ProLock), findsNothing);
      expect(find.byType(HistoryChart), findsOneWidget);
      expect(find.text('Samples stored'), findsOneWidget);
      expect(find.text('Median latency'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('switching to the 24-hour window keeps the chart alive',
        (tester) async {
      await SettingsRepository(store.settings).saveProUnlocked(true);
      await seed(20);
      await tester.pumpWidget(host(const HistoryScreen()));
      await tester.pump();

      await tester.tap(find.text('Last 24 h'));
      await tester.pump();

      expect(find.byType(HistoryChart), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('an empty window says so rather than drawing a blank box',
        (tester) async {
      await SettingsRepository(store.settings).saveProUnlocked(true);

      await tester.pumpWidget(host(const HistoryScreen()));
      await tester.pump();

      expect(find.textContaining('No samples'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('only Pro gets the clear-history control', (tester) async {
      await tester.pumpWidget(host(const HistoryScreen()));
      await tester.pump();

      expect(find.byIcon(Icons.delete_outline), findsNothing);
      await unmount(tester);
    });
  });

  group('first run and the meter', () {
    Widget app() =>
        ProviderScope(overrides: overrides(), child: const HonestSignalApp());

    /// The meter is one lazily-built list, so anything below an 800 px viewport
    /// is never constructed. A tall surface renders the whole screen in one
    /// pass; the point of these tests is the content, not the scrolling.
    void tallSurface(WidgetTester tester) {
      // The default 800 logical width is kept; only the height changes, so the
      // layout under test is the same one the other tests exercise.
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    testWidgets('a fresh install opens on the explanation, not the meter',
        (tester) async {
      await tester.pumpWidget(app());
      await settle(tester, 4);

      expect(find.text('Your signal icon is lying to you'), findsOneWidget);
      expect(find.text('Measure my connection'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('finishing onboarding remembers it and starts measuring',
        (tester) async {
      await tester.pumpWidget(app());
      await settle(tester, 4);

      await tester.tap(find.text('Measure my connection'));
      await settle(tester);

      expect(find.text('Honest Signal'), findsOneWidget);
      expect(
        SettingsRepository(store.settings).load().hasSeenOnboarding,
        isTrue,
      );
      await unmount(tester);
    });

    testWidgets('an onboarded install opens straight onto a real reading',
        (tester) async {
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));

      await tester.pumpWidget(app());
      await settle(tester, 20);

      // The fake network is fast, steady and lossless, so the meter must reach
      // the top of the scale rather than sitting on the placeholder.
      expect(find.text('Excellent'), findsOneWidget);
      expect(find.text('5/5'), findsOneWidget);
      expect(find.text('Latency'), findsOneWidget);
      expect(find.text('Lost probes'), findsOneWidget);
      expect(find.text('0%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });

    testWidgets('the free tier is offered Pro from the meter', (tester) async {
      tallSurface(tester);
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));

      await tester.pumpWidget(app());
      await settle(tester, 20);

      expect(find.text('Honest Signal Pro'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('a Pro install is not nagged on the meter', (tester) async {
      tallSurface(tester);
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));
      await SettingsRepository(store.settings).saveProUnlocked(true);

      await tester.pumpWidget(app());
      await settle(tester, 20);

      expect(find.text('Honest Signal Pro'), findsNothing);
      await unmount(tester);
    });

    testWidgets('the reading is dated, so a stale number can never look live',
        (tester) async {
      // iOS cannot measure while the app is closed, so the age of the reading
      // is a product requirement rather than decoration.
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));

      await tester.pumpWidget(app());
      await settle(tester, 20);

      expect(
        find.descendant(
          of: find.byType(FreshnessLine),
          matching: find.textContaining('Measured'),
        ),
        findsOneWidget,
      );
      await unmount(tester);
    });

    testWidgets('the data budget is on the meter, not buried in settings',
        (tester) async {
      tallSurface(tester);
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));

      await tester.pumpWidget(app());
      await settle(tester, 20);

      expect(find.textContaining('/ 25 MB'), findsOneWidget);
      await unmount(tester);
    });

    // Layout matrix: four handset widths against the text scales that are
    // meaningful under the test font.
    //
    // Both overflow defects this stage found were invisible at the default
    // 800x600 test surface, which is wider than any phone and hands the metric
    // tiles roughly double the height they get on a real handset. Pinning the
    // matrix is what stops either from coming back quietly, because neither
    // shows up as a failed assertion — an overflow is thrown during layout.
    //
    // Capped at 1.3x deliberately. `flutter_test` renders in Ahem, where every
    // glyph is a full em square, so a string measures roughly twice its real
    // width. At 1.6x on a 360 dp screen that inflation alone overflows
    // `FreshnessLine` by 33 px and `BudgetMeter`'s header by 24 px — neither of
    // which is reachable on a device at that scale. Raising this ceiling would
    // pin a font artifact as if it were a layout bug. The underlying
    // robustness gap (unflexed `Text` inside a `Row`) is recorded in
    // docs/TEST_PLAN.md; if it is fixed, this can go to 1.6x.
    const geometries = <String, ({Size size, double dpr})>{
      'small phone (360x800)': (size: Size(1080, 2400), dpr: 3.0),
      'Pixel-class (393x852)': (size: Size(1080, 2340), dpr: 2.75),
      'large phone (411x914)': (size: Size(1080, 2400), dpr: 2.625),
      'max phone (430x932)': (size: Size(1290, 2796), dpr: 3.0),
    };

    for (final entry in geometries.entries) {
      for (final textScale in [1.0, 1.3]) {
        testWidgets(
          'lays out on a ${entry.key} at ${textScale}x text without '
          'overflowing',
          (tester) async {
            tester.view.physicalSize = entry.value.size;
            tester.view.devicePixelRatio = entry.value.dpr;
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(tester.view.reset);
            addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

            await SettingsRepository(store.settings)
                .save(const AppSettings(hasSeenOnboarding: true));

            await tester.pumpWidget(app());
            await settle(tester, 20);

            // An overflow is thrown during layout, not asserted, so this is
            // the whole check.
            expect(tester.takeException(), isNull);
            await unmount(tester);
          },
        );
      }
    }

    testWidgets('a dead connection is reported as dead', (tester) async {
      probes.rtts = const [null, null, null, null];
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));

      await tester.pumpWidget(app());
      await settle(tester, 20);

      expect(find.text('No usable connection'), findsOneWidget);
      expect(find.text('0/5'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('probes answering while the download dies is shown as the '
        'two-bar case the app exists to catch', (tester) async {
      probes.transferSucceeds = false;
      await SettingsRepository(store.settings)
          .save(const AppSettings(hasSeenOnboarding: true));

      await tester.pumpWidget(app());
      await settle(tester, 20);

      expect(find.text('Slow'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      // Latency still looks excellent — which is the whole point.
      expect(find.text('stalled'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('settings', () {
    testWidgets('a Pro buyer can change the indicator style on every platform '
        'the feature is sold on', (tester) async {
      // C-1, the compliance Critical. `_ThemePicker` is the only writer of
      // `barTheme` in the app, and it used to sit inside `if
      // (Platform.isAndroid)`. These tests run with `Platform.isAndroid ==
      // false` — the iPhone path — so before the fix nothing here rendered and
      // an iPhone buyer paid for a feature with no control anywhere.
      await tester.pumpWidget(host(const SettingsScreen()));
      await tester.pump();

      expect(find.text('Indicator style'), findsOneWidget);
      // Platform-true wording: there is no status bar to theme on iOS, so
      // promising one would be the same inaccuracy in miniature.
      expect(
        find.textContaining('Bars, dots or wave — in the app'),
        findsOneWidget,
      );
      expect(find.textContaining('in the status bar'), findsNothing);
      expect(tester.takeException(), isNull);
      await unmount(tester);
    });
  });
}
