import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/local_store.dart';
import '../features/indicator/data/indicator_channel.dart';
import '../features/indicator/data/indicator_controller.dart';
import '../features/measurement/data/budget_store.dart';
import '../features/measurement/data/connectivity_source.dart';
import '../features/measurement/data/history_repository.dart';
import '../features/measurement/data/measurement_controller.dart';
import '../features/measurement/data/measurement_engine.dart';
import '../features/measurement/data/probe_client.dart';
import '../features/purchases/data/iap_gateway.dart';
import '../features/purchases/data/purchase_controller.dart';
import '../features/settings/data/settings_repository.dart';
import '../features/settings/domain/app_settings.dart';
import '../features/settings/presentation/settings_controller.dart';

/// Overridden in `main()` once the boxes are open. Nothing may read it before
/// then, which is why bootstrap awaits the store before running the app.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw StateError('localStoreProvider must be overridden in main()'),
);

/// Overridden by the screenshot harness and by tests to swap in fakes.
final probeClientProvider = Provider<ProbeClient>((ref) {
  final client = HttpProbeClient();
  ref.onDispose(client.close);
  return client;
});

final connectivitySourceProvider = Provider<ConnectivitySource>((ref) {
  final source = PluginConnectivitySource();
  ref.onDispose(source.dispose);
  return source;
});

final iapGatewayProvider = Provider<IapGateway>((ref) => PluginIapGateway());

final budgetStoreProvider = Provider<BudgetStore>(
  (ref) => PlatformBudgetStore(),
);

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => SettingsRepository(ref.watch(localStoreProvider).settings),
);

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(localStoreProvider).history),
);

final settingsProvider = StateNotifierProvider<SettingsController, AppSettings>(
  (ref) {
    return SettingsController(ref.watch(settingsRepositoryProvider));
  },
);

final purchaseControllerProvider = ChangeNotifierProvider<PurchaseController>((
  ref,
) {
  final controller = PurchaseController(
    gateway: ref.watch(iapGatewayProvider),
    settings: ref.watch(settingsRepositoryProvider),
  );
  return controller;
});

final isProProvider = Provider<bool>(
  (ref) => ref.watch(purchaseControllerProvider).state.isPro,
);

/// Settings as they actually apply, with Pro-only values clamped for free
/// installs. Everything downstream reads this, never the raw settings.
final effectiveSettingsProvider = Provider<AppSettings>((ref) {
  final settings = ref.watch(settingsProvider);
  return settings.clampedForTier(isPro: ref.watch(isProProvider));
});

final indicatorChannelProvider = Provider<IndicatorChannel>(
  (ref) => IndicatorChannel(),
);

final indicatorControllerProvider = ChangeNotifierProvider<IndicatorController>(
  (ref) {
    final controller = IndicatorController(
      channel: ref.watch(indicatorChannelProvider),
    );

    ref.listen<AppSettings>(
      effectiveSettingsProvider,
      (_, next) => controller.sync(next),
    );

    return controller;
  },
);

final measurementEngineProvider = Provider<MeasurementEngine>(
  (ref) => MeasurementEngine(client: ref.watch(probeClientProvider)),
);

final measurementControllerProvider =
    ChangeNotifierProvider<MeasurementController>((ref) {
      final controller = MeasurementController(
        engine: ref.watch(measurementEngineProvider),
        connectivity: ref.watch(connectivitySourceProvider),
        history: ref.watch(historyRepositoryProvider),
        budgetStore: ref.watch(budgetStoreProvider),
        indicator: ref.watch(indicatorChannelProvider),
        // This controller owns a timer, a connectivity subscription and the
        // foreground-service handoff. It must outlive settings changes; those are
        // delivered through applySettings below rather than rebuilding it.
        settings: ref.read(effectiveSettingsProvider),
      );

      ref.listen<AppSettings>(
        effectiveSettingsProvider,
        (_, next) => controller.applySettings(next),
      );

      return controller;
    });
