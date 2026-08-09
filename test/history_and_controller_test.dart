import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/indicator/data/indicator_channel.dart';
import 'package:honestsignal/features/measurement/data/budget_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/data/measurement_controller.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/measurement_state.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

import 'fakes/fake_probe_client.dart';

SignalSample _sample(DateTime at, {int bars = 4, NetworkKind kind = NetworkKind.wifi}) =>
    SignalSample(
      timestamp: at,
      kind: kind,
      bars: bars,
      composite: bars / 5,
      latencyMs: 40,
      jitterMs: 5,
      throughputKbps: 20000,
      lossRatio: 0,
      probesSent: 4,
      bytesUsed: 2800,
    );

void main() {
  group('HistoryRepository', () {
    late LocalStore store;
    late HistoryRepository history;

    setUp(() async {
      store = await LocalStore.openInMemory();
      history = HistoryRepository(store.history);
    });

    tearDown(() => store.close());

    test('an unchanged score inside the spacing window is not stored again',
        () async {
      final t0 = DateTime(2026, 8, 7, 12);
      await history.record(_sample(t0));
      await history.record(_sample(t0.add(const Duration(seconds: 5))));

      // At a 5-second foreground cadence, storing every sample would be 17k
      // rows an hour for an unchanging connection.
      expect(history.since(t0.add(const Duration(minutes: 1)), const Duration(hours: 1)).length, 1);
    });

    test('a changed score is always stored, however soon it arrives', () async {
      final t0 = DateTime(2026, 8, 7, 12);
      await history.record(_sample(t0, bars: 5));
      await history.record(_sample(t0.add(const Duration(seconds: 2)), bars: 1));

      final stored = history.since(t0.add(const Duration(minutes: 1)), const Duration(hours: 1));
      expect(stored.length, 2);
      expect(stored.map((s) => s.bars), [5, 1]);
    });

    test('a network change is stored even at the same score', () async {
      final t0 = DateTime(2026, 8, 7, 12);
      await history.record(_sample(t0, kind: NetworkKind.wifi));
      await history.record(
        _sample(t0.add(const Duration(seconds: 3)), kind: NetworkKind.cellular),
      );

      expect(history.since(t0.add(const Duration(minutes: 1)), const Duration(hours: 1)).length, 2);
    });

    test('an unchanged score is stored again once the spacing window passes',
        () async {
      final t0 = DateTime(2026, 8, 7, 12);
      await history.record(_sample(t0));
      await history.record(
        _sample(t0.add(HistoryRepository.minimumSpacing + const Duration(seconds: 1))),
      );

      expect(history.since(t0.add(const Duration(minutes: 5)), const Duration(hours: 1)).length, 2);
    });

    test('samples older than the retention window are pruned', () async {
      final old = DateTime(2026, 8, 6, 6);
      final now = DateTime(2026, 8, 7, 12);
      await history.record(_sample(old));
      await history.record(_sample(now, bars: 2));

      final all = history.since(now, const Duration(days: 7));
      expect(all.length, 1);
      expect(all.single.bars, 2);
    });

    test('since() returns oldest first, which is the order the chart draws',
        () async {
      final now = DateTime(2026, 8, 7, 12);
      for (var i = 5; i >= 1; i--) {
        await history.record(_sample(now.subtract(Duration(minutes: i * 5)), bars: i));
      }

      final samples = history.since(now, const Duration(hours: 1));
      final timestamps = samples.map((s) => s.timestamp).toList();
      expect(timestamps, orderedEquals(List.of(timestamps)..sort()));
    });

    test('latest() survives a restart, so the app opens on the last reading',
        () async {
      final now = DateTime(2026, 8, 7, 12);
      await history.record(_sample(now, bars: 3));

      expect(HistoryRepository(store.history).latest()?.bars, 3);
    });

    test('clear() empties the log', () async {
      await history.record(_sample(DateTime(2026, 8, 7, 12)));
      await history.clear();
      expect(history.latest(), isNull);
    });
  });

  group('MeasurementController', () {
    late LocalStore store;
    late FakeProbeClient client;
    late InMemoryBudgetStore budget;
    late MeasurementController controller;
    late DateTime now;

    Future<void> build({AppSettings settings = const AppSettings()}) async {
      store = await LocalStore.openInMemory();
      client = FakeProbeClient(rtts: const [30, 31, 30, 30]);
      budget = InMemoryBudgetStore();
      now = DateTime(2026, 8, 7, 12);
      controller = MeasurementController(
        engine: MeasurementEngine(
          client: client,
          config: const MeasurementConfig(interProbeGap: Duration.zero),
          clock: () => now,
        ),
        connectivity: FakeConnectivitySource(),
        history: HistoryRepository(store.history),
        budgetStore: budget,
        indicator: IndicatorChannel(),
        settings: settings,
        clock: () => now,
      );
    }

    tearDown(() async {
      controller.dispose();
      await store.close();
    });

    test('a measurement charges its bytes to the daily budget', () async {
      await build();
      await controller.measureNow(forceTransfer: true);

      expect(controller.state.budget.bytesUsed, controller.state.sample.bytesUsed);
      expect(controller.state.budget.bytesUsed, greaterThan(0));
    });

    test('an exhausted budget stops transfer samples but keeps measuring',
        () async {
      await build(
        settings: const AppSettings(dailyBudgetMb: AppSettings.minDailyBudgetMb),
      );
      await budget.spend(
        now: now,
        bytes: AppSettings.minDailyBudgetMb * 1024 * 1024,
        limitBytes: AppSettings.minDailyBudgetMb * 1024 * 1024,
      );

      await controller.measureNow(forceTransfer: true);

      expect(controller.state.pause, MeasurementPause.budgetExhausted);
      // Latency probes still ran — the user is not left with a blank screen.
      expect(client.probeCalls, 4);
      // But the 120 KB transfer did not.
      expect(client.transferCalls, 0);
      expect(controller.state.hasReading, isTrue);
    });

    test('opting out of mobile data suppresses probing on cellular', () async {
      store = await LocalStore.openInMemory();
      client = FakeProbeClient();
      now = DateTime(2026, 8, 7, 12);
      controller = MeasurementController(
        engine: MeasurementEngine(
          client: client,
          config: const MeasurementConfig(interProbeGap: Duration.zero),
          clock: () => now,
        ),
        connectivity: FakeConnectivitySource(NetworkKind.cellular),
        history: HistoryRepository(store.history),
        budgetStore: InMemoryBudgetStore(),
        indicator: IndicatorChannel(),
        settings: const AppSettings(measureOnCellular: false),
        clock: () => now,
      );

      await controller.start();

      expect(controller.state.pause, MeasurementPause.cellularOptOut);
      expect(client.probeCalls, 0);
    });

    test('the transfer sample runs on its own slower clock', () async {
      await build();

      await controller.measureNow(forceTransfer: true);
      expect(client.transferCalls, 1);

      // A second cycle moments later must not spend another 120 KB.
      now = now.add(const Duration(seconds: 5));
      await controller.measureNow();
      expect(client.transferCalls, 1);

      now = now.add(MeasurementController.foregroundTransferInterval);
      await controller.measureNow();
      expect(client.transferCalls, 2);
    });

    test('overlapping cycles are dropped rather than queued', () async {
      await build();

      final first = controller.measureNow(forceTransfer: true);
      final second = controller.measureNow(forceTransfer: true);
      await Future.wait([first, second]);

      expect(client.probeCalls, 4);
    });

    test('readings are written to history as they arrive', () async {
      await build();
      await controller.measureNow(forceTransfer: true);

      expect(controller.historySince(const Duration(hours: 1)), hasLength(1));
    });
  });
}
