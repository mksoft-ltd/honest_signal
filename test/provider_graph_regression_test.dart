import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/app/providers.dart';
import 'package:honestsignal/core/storage/local_store.dart';
import 'package:honestsignal/features/measurement/data/budget_store.dart';
import 'package:honestsignal/features/measurement/data/history_repository.dart';
import 'package:honestsignal/features/measurement/data/measurement_controller.dart';
import 'package:honestsignal/features/measurement/data/measurement_engine.dart';
import 'package:honestsignal/features/measurement/domain/measurement_config.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/settings/domain/app_settings.dart';

import 'fakes/fake_iap_gateway.dart';
import 'fakes/fake_indicator_channel.dart';
import 'fakes/fake_probe_client.dart';

/// Regression coverage for C1: settings changes must update the existing
/// long-lived controller rather than silently replacing its timer and service
/// handoff with an unstarted instance.
void main() {
  // effectiveSettingsProvider reaches isProProvider, so a settings change walks
  // into the purchase controller. Without a binding and a faked gateway that
  // constructs the real Play Billing plugin and throws on the platform channel.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a real settings-provider update keeps measurement running', () async {
    final store = await LocalStore.openInMemory();
    final probes = FakeProbeClient(rtts: const [30, 31, 30, 30]);
    final connectivity = FakeConnectivitySource();
    final indicator = FakeIndicatorChannel();
    final gateway = FakeIapGateway();
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        probeClientProvider.overrideWithValue(probes),
        connectivitySourceProvider.overrideWithValue(connectivity),
        budgetStoreProvider.overrideWithValue(InMemoryBudgetStore()),
        indicatorChannelProvider.overrideWithValue(indicator),
        iapGatewayProvider.overrideWithValue(gateway),
        // The real engine pauses 60 ms between probes so they measure
        // independent round trips. Draining microtasks does not advance real
        // time, so with the default gap no cycle ever finishes and the second
        // measureNow would bounce off the in-flight guard rather than probing.
        // The engine's timing is not what this test is about — the controller
        // provider's lifetime is.
        measurementEngineProvider.overrideWith(
          (ref) => MeasurementEngine(
            client: ref.watch(probeClientProvider),
            config: const MeasurementConfig(interProbeGap: Duration.zero),
          ),
        ),
      ],
    );
    addTearDown(() async {
      container.dispose();
      connectivity.dispose();
      gateway.dispose();
      await store.close();
    });

    final controller = container.read(measurementControllerProvider);
    await controller.start();
    await drain();
    final probesBeforeSettingsChange = probes.probeCalls;

    await container
        .read(settingsProvider.notifier)
        .update((settings) => settings.copyWith(themeMode: ThemeMode.dark));
    await drain();

    // This is the key assertion. If effectiveSettingsProvider were watched by
    // the controller provider, this would be a replacement that HomeScreen
    // never starts again.
    expect(
      identical(container.read(measurementControllerProvider), controller),
      isTrue,
    );

    expect(probesBeforeSettingsChange, greaterThan(0));

    // Nothing below drives the controller by hand until the last step.
    // `measureNow` deliberately does not check `_started`, so calling it here
    // would pass against the stranded controller C1 actually produced. Only the
    // periodic timer and the connectivity subscription that `start()` owns can
    // move these counts, and a replacement controller has neither.
    final beforeTimerTick = probes.probeCalls;
    await Future<void>.delayed(
      const AppSettings().foregroundInterval + const Duration(milliseconds: 500),
    );
    expect(probes.probeCalls, greaterThan(beforeTimerTick));

    await drain();
    final beforeTransportChange = probes.probeCalls;
    connectivity.emit(NetworkKind.cellular);
    await drain();
    expect(probes.probeCalls, greaterThan(beforeTransportChange));

    // The other half of the stoppage: a controller stuck at `_started == false`
    // returns early here, so `setUiActive(false)` never reaches the Android
    // service and its background loop stays suppressed forever.
    await controller.setForeground(false);
    expect(indicator.uiActive.last, isFalse);
  });

  test(
    'a stale saved reading does not apply hysteresis to a new session',
    () async {
      final store = await LocalStore.openInMemory();
      addTearDown(store.close);
      var now = DateTime(2026, 8, 8, 12);
      final initialClient = FakeProbeClient(
        rtts: const [null, null, null, null],
      );
      final initial = _controller(
        store: store,
        client: initialClient,
        clock: () => now,
      );
      await initial.measureNow(forceTransfer: true);
      initial.dispose();

      now = now.add(
        MeasurementController.hysteresisFreshness + const Duration(seconds: 1),
      );
      final recovered = _controller(
        store: store,
        client: FakeProbeClient(rtts: const [30, 31, 30, 30]),
        clock: () => now,
      );
      addTearDown(recovered.dispose);

      await recovered.measureNow(forceTransfer: true);
      expect(recovered.state.sample.bars, 5);
    },
  );
}

MeasurementController _controller({
  required LocalStore store,
  required FakeProbeClient client,
  required DateTime Function() clock,
}) => MeasurementController(
  engine: MeasurementEngine(
    client: client,
    config: const MeasurementConfig(interProbeGap: Duration.zero),
    clock: clock,
  ),
  connectivity: FakeConnectivitySource(),
  history: HistoryRepository(store.history),
  budgetStore: InMemoryBudgetStore(),
  indicator: FakeIndicatorChannel(),
  settings: const AppSettings(),
  clock: clock,
);
