import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/data/budget_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/data/measurement_controller.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/measurement_state.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

import 'fakes/fake_indicator_channel.dart';
import 'fakes/fake_probe_client.dart';

/// The cadence, data-budget and indicator behaviour that sits above the engine.
///
/// Everything here runs on an injected clock; the periodic timer is only ever
/// started where a test needs it, and is cancelled in teardown.
void main() {
  late LocalStore store;
  late FakeProbeClient client;
  late FakeConnectivitySource connectivity;
  late FakeIndicatorChannel indicator;
  late MeasurementController controller;
  late DateTime now;

  /// Set by the one test that disposes the controller as part of its scenario,
  /// so teardown does not dispose it a second time.
  var disposedInTest = false;

  const oneCycleBytes = 4 * 700;
  const transferBytes = 120000;

  Future<void> build({
    AppSettings settings = const AppSettings(),
    NetworkKind kind = NetworkKind.wifi,
    BudgetStore? budgetStore,
  }) async {
    disposedInTest = false;
    store = await LocalStore.openInMemory();
    client = FakeProbeClient(rtts: const [30, 31, 30, 30]);
    connectivity = FakeConnectivitySource(kind);
    indicator = FakeIndicatorChannel();
    now = DateTime(2026, 8, 8, 12);
    controller = MeasurementController(
      engine: MeasurementEngine(
        client: client,
        config: const MeasurementConfig(interProbeGap: Duration.zero),
        clock: () => now,
      ),
      connectivity: connectivity,
      history: HistoryRepository(store.history),
      budgetStore: budgetStore ?? InMemoryBudgetStore(),
      indicator: indicator,
      settings: settings,
      clock: () => now,
    );
  }

  tearDown(() async {
    if (!disposedInTest) controller.dispose();
    connectivity.dispose();
    await store.close();
  });

  group('data budget', () {
    test('two cycles racing charge the budget once, not twice', () async {
      // The periodic timer fires on its own schedule. Before the re-entrancy
      // guard, a tick landing mid-cycle started a second set of probes and
      // charged the user twice for one answer.
      await build();

      final first = controller.measureNow(forceTransfer: true);
      final second = controller.measureNow(forceTransfer: true);
      await Future.wait([first, second]);

      expect(client.probeCalls, 4);
      expect(client.transferCalls, 1);
      expect(controller.state.budget.bytesUsed, oneCycleBytes + transferBytes);
    });

    test('spending accumulates across cycles', () async {
      await build();

      await controller.measureNow(forceTransfer: true);
      now = now.add(const Duration(seconds: 5));
      await controller.measureNow();

      expect(
        controller.state.budget.bytesUsed,
        oneCycleBytes * 2 + transferBytes,
      );
    });

    test('a spent budget stops the transfer sample but not the reading',
        () async {
      const limit = AppSettings.minDailyBudgetMb;
      final budgetStore = InMemoryBudgetStore();
      await build(
        settings: const AppSettings(dailyBudgetMb: limit),
        budgetStore: budgetStore,
      );
      await budgetStore.spend(
        now: now,
        bytes: limit * 1024 * 1024,
        limitBytes: limit * 1024 * 1024,
      );

      await controller.measureNow(forceTransfer: true);

      expect(controller.state.pause, MeasurementPause.budgetExhausted);
      expect(client.probeCalls, 4);
      expect(client.transferCalls, 0);
      expect(controller.state.hasReading, isTrue);
    });

    test('the transfer sample resumes when the calendar day rolls over',
        () async {
      const limit = AppSettings.minDailyBudgetMb;
      final budgetStore = InMemoryBudgetStore();
      await build(
        settings: const AppSettings(dailyBudgetMb: limit),
        budgetStore: budgetStore,
      );
      await budgetStore.spend(
        now: now,
        bytes: limit * 1024 * 1024,
        limitBytes: limit * 1024 * 1024,
      );
      await controller.measureNow(forceTransfer: true);
      expect(client.transferCalls, 0);

      now = DateTime(2026, 8, 9, 0, 1);
      await controller.measureNow(forceTransfer: true);

      expect(controller.state.pause, MeasurementPause.none);
      expect(client.transferCalls, 1);
    });

    test('raising the limit lifts the pause without waiting for tomorrow',
        () async {
      const limit = AppSettings.minDailyBudgetMb;
      final budgetStore = InMemoryBudgetStore();
      await build(
        settings: const AppSettings(dailyBudgetMb: limit),
        budgetStore: budgetStore,
      );
      await budgetStore.spend(
        now: now,
        bytes: limit * 1024 * 1024,
        limitBytes: limit * 1024 * 1024,
      );
      await controller.measureNow(forceTransfer: true);
      expect(controller.state.pause, MeasurementPause.budgetExhausted);

      await controller.applySettings(
        const AppSettings(dailyBudgetMb: AppSettings.maxDailyBudgetMb),
      );
      await controller.measureNow(forceTransfer: true);

      expect(controller.state.pause, MeasurementPause.none);
      expect(client.transferCalls, 1);
    });

    test('a broken budget channel fails closed: probes continue, the 120 KB '
        'sample does not', () async {
      // Failing open would let a channel error spend unlimited mobile data in
      // the background, which is the one bug this app must never ship.
      await build(budgetStore: PlatformBudgetStore(channel: const _DeadChannel()));

      await controller.measureNow(forceTransfer: true);

      expect(controller.state.pause, MeasurementPause.budgetExhausted);
      expect(client.transferCalls, 0);
      expect(client.probeCalls, 4);
    });

    test('the transfer sample keeps its own slower clock', () async {
      await build();

      await controller.measureNow(forceTransfer: true);
      expect(client.transferCalls, 1);

      now = now.add(const Duration(seconds: 30));
      await controller.measureNow();
      expect(client.transferCalls, 1);

      now = now.add(MeasurementController.foregroundTransferInterval);
      await controller.measureNow();
      expect(client.transferCalls, 2);
    });
  });

  group('lifecycle', () {
    test('opening the app measures immediately, including a transfer sample',
        () async {
      // The user opened the app to find out whether the connection works, and
      // latency alone cannot answer that.
      await build();

      await controller.start();
      await drain();

      expect(client.probeCalls, 4);
      expect(client.transferCalls, 1);
      expect(controller.state.hasReading, isTrue);
      expect(indicator.uiActive, contains(true));
    });

    test('starting twice does not double up the probing', () async {
      await build();

      await controller.start();
      await drain();
      final afterFirst = client.probeCalls;
      await controller.start();
      await drain();

      expect(client.probeCalls, afterFirst);
    });

    test('backgrounding stops the foreground loop and says so', () async {
      await build();
      await controller.start();
      await drain();

      await controller.setForeground(false);

      expect(controller.state.pause, MeasurementPause.appBackgrounded);
      expect(indicator.uiActive.last, isFalse);
    });

    test('returning to the foreground takes a fresh full reading', () async {
      await build();
      await controller.start();
      await drain();
      await controller.setForeground(false);
      final before = client.transferCalls;

      now = now.add(const Duration(minutes: 3));
      await controller.setForeground(true);
      await drain();

      expect(controller.state.pause, MeasurementPause.none);
      expect(client.transferCalls, greaterThan(before));
      expect(indicator.uiActive.last, isTrue);
    });

    test('a lifecycle change before start() is ignored', () async {
      await build();

      await controller.setForeground(false);

      expect(controller.state.pause, MeasurementPause.none);
      expect(client.probeCalls, 0);
    });

    test('measuring after disposal touches nothing', () async {
      await build();
      controller.dispose();
      disposedInTest = true;

      await controller.measureNow(forceTransfer: true);

      expect(client.probeCalls, 0);
    });
  });

  group('connectivity', () {
    test('a transport change forces a full re-measure at once', () async {
      // The moment the network changes is exactly when the old reading became
      // meaningless.
      await build();
      await controller.start();
      await drain();
      final before = client.transferCalls;

      now = now.add(const Duration(seconds: 2));
      connectivity.emit(NetworkKind.cellular);
      await drain();

      expect(controller.state.sample.kind, NetworkKind.cellular);
      expect(client.transferCalls, greaterThan(before));
    });

    test('losing the network reports zero bars without probing', () async {
      await build();
      await controller.start();
      await drain();
      final before = client.probeCalls;

      connectivity.emit(NetworkKind.none);
      await drain();

      expect(controller.state.sample.bars, 0);
      expect(controller.state.sample.isOffline, isTrue);
      expect(client.probeCalls, before);
    });

    test('opting out of mobile data suppresses probing on cellular', () async {
      await build(
        settings: const AppSettings(measureOnCellular: false),
        kind: NetworkKind.cellular,
      );

      await controller.start();
      await drain();

      expect(controller.state.pause, MeasurementPause.cellularOptOut);
      expect(client.probeCalls, 0);
    });
  });

  group('status-bar indicator', () {
    test('receives every reading with the wording the notification shows',
        () async {
      await build();

      await controller.start();
      await drain();

      expect(indicator.published, hasLength(1));
      final published = indicator.published.single;
      expect(published['bars'], controller.state.sample.bars);
      expect(published['verdict'], controller.state.sample.verdict);
      expect(published['theme'], BarTheme.bars.name);
      expect(published['detail'], contains('Wi-Fi'));
    });

    test('is not fed when the user has turned it off', () async {
      await build(
        settings: const AppSettings(notificationIndicatorEnabled: false),
      );

      await controller.measureNow(forceTransfer: true);

      expect(indicator.published, isEmpty);
    });

    test('follows the chosen bar theme', () async {
      await build(settings: const AppSettings(barTheme: BarTheme.wave));

      await controller.measureNow(forceTransfer: true);

      expect(indicator.published.single['theme'], BarTheme.wave.name);
    });

    test('tells the service how often the next reading is due', () async {
      // N2. Every publish renews the service's UI-active lease, and the service
      // sizes that lease from this number. A flat lease shorter than the
      // publishing cadence expires between publishes, and the service then runs
      // the duplicate probe set the lease exists to prevent. Reachable on Pro,
      // whose foreground interval also tops out at 60 s — so the interval has
      // to travel with the reading rather than being assumed.
      await build(
        settings: const AppSettings(
          foregroundIntervalSeconds: AppSettings.maxForegroundInterval,
        ),
      );

      await controller.measureNow(forceTransfer: true);

      expect(
        indicator.published.single['uiIntervalSeconds'],
        AppSettings.maxForegroundInterval,
      );
    });
  });

  group('history', () {
    test('each distinct reading is written as it arrives', () async {
      await build();

      await controller.measureNow(forceTransfer: true);
      client.rtts = const [1200, 1300, 1250, 1200];
      now = now.add(const Duration(seconds: 5));
      await controller.measureNow();

      final samples = controller.historySince(const Duration(hours: 1));
      expect(samples, hasLength(2));
      expect(samples.first.bars, greaterThan(samples.last.bars));
    });

    test('clearing history empties the window', () async {
      await build();
      await controller.measureNow(forceTransfer: true);
      expect(controller.historySince(const Duration(hours: 1)), isNotEmpty);

      await controller.clearHistory();

      expect(controller.historySince(const Duration(hours: 1)), isEmpty);
    });

    test('the app reopens on the last stored reading rather than a blank meter',
        () async {
      await build();
      await controller.measureNow(forceTransfer: true);
      final stored = controller.state.sample.bars;

      final reopened = MeasurementController(
        engine: MeasurementEngine(
          client: FakeProbeClient(),
          config: const MeasurementConfig(interProbeGap: Duration.zero),
          clock: () => now,
        ),
        connectivity: FakeConnectivitySource(),
        history: HistoryRepository(store.history),
        budgetStore: InMemoryBudgetStore(),
        indicator: FakeIndicatorChannel(),
        settings: const AppSettings(),
        clock: () => now,
      );

      expect(reopened.state.hasReading, isTrue);
      expect(reopened.state.sample.bars, stored);
      reopened.dispose();
    });
  });
}

/// Stands in for a platform channel that is not there — iOS before the Swift
/// handler is registered, or a genuine failure.
class _DeadChannel extends MethodChannel {
  const _DeadChannel() : super('test/dead');

  @override
  Future<Map<K, V>?> invokeMapMethod<K, V>(String method, [dynamic arguments]) async {
    throw MissingPluginException('no handler');
  }
}
