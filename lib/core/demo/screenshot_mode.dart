import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../app/providers.dart';
import '../../features/purchases/data/iap_gateway.dart';
import '../../features/purchases/data/purchase_controller.dart';
import '../../features/measurement/data/budget_store.dart';
import '../../features/measurement/data/connectivity_source.dart';
import '../../features/measurement/data/history_repository.dart';
import '../../features/measurement/data/probe_client.dart';
import '../../features/measurement/domain/network_kind.dart';
import '../../features/measurement/domain/scoring.dart';
import '../../features/measurement/domain/signal_sample.dart';

/// Store-screenshot harness support.
///
/// Enabled with `--dart-define=SCREENSHOT_MODE=true`, and only ever in a
/// non-release build: a release binary that could be switched into a fake-data
/// mode is a store-review problem, so the flag is ANDed with `!kReleaseMode`.
class ScreenshotMode {
  const ScreenshotMode._();

  static const bool _flag =
      bool.fromEnvironment('SCREENSHOT_MODE', defaultValue: false);

  /// `pro` (default) shows the Pro screens; `free` captures the paywall and the
  /// locked states. Pass `--dart-define=SCREENSHOT_TIER=free` for those shots.
  static const String _tier =
      String.fromEnvironment('SCREENSHOT_TIER', defaultValue: 'pro');

  static bool get isEnabled => _flag && !kReleaseMode;

  static bool get isPro => _tier != 'free';

  /// Provider overrides that replace every network- and store-facing seam with
  /// a deterministic fake, so screenshots are identical on every run.
  static List<Override> overrides() => [
        probeClientProvider.overrideWithValue(_DemoProbeClient()),
        connectivitySourceProvider.overrideWithValue(_DemoConnectivitySource()),
        iapGatewayProvider.overrideWithValue(_DemoIapGateway()),
        budgetStoreProvider.overrideWith((ref) {
          final store = InMemoryBudgetStore();
          unawaited(store.spend(
            now: DateTime.now(),
            bytes: 6 * 1024 * 1024,
            limitBytes: 25 * 1024 * 1024,
          ));
          return store;
        }),
      ];

  /// Fills the history box with a plausible day: mostly good, with the kind of
  /// dip the app exists to catch.
  static Future<void> seedHistory(HistoryRepository history) async {
    final now = DateTime.now();
    final random = math.Random(7);

    for (var minutesAgo = 60; minutesAgo >= 0; minutesAgo--) {
      final t = now.subtract(Duration(minutes: minutesAgo));
      // A believable story: solid connection, a bad patch 35–22 minutes ago,
      // recovery, and a strong reading now.
      final bars = switch (minutesAgo) {
        > 46 => 5,
        > 35 => 4,
        > 30 => 1,
        > 26 => 0,
        > 22 => 2,
        > 12 => 4,
        _ => 5,
      };
      final latency = switch (bars) {
        0 => 1800.0,
        1 => 780.0,
        2 => 320.0,
        3 => 140.0,
        4 => 62.0,
        _ => 24.0 + random.nextInt(8),
      };
      final throughput = switch (bars) {
        0 => 0.0,
        1 => 240.0,
        2 => 1100.0,
        3 => 4200.0,
        4 => 11000.0,
        _ => 46000.0,
      };

      await history.record(SignalSample(
        timestamp: t,
        kind: bars <= 1 ? NetworkKind.cellular : NetworkKind.wifi,
        bars: bars,
        composite: bars / 5,
        latencyMs: latency,
        jitterMs: bars >= 4 ? 6 : 90,
        throughputKbps: throughput,
        lossRatio: bars == 0 ? 1 : (bars == 1 ? 0.5 : 0),
        probesSent: 4,
        bytesUsed: 0,
        networkDetail: bars <= 1 ? 'Mobile data' : 'Home Wi-Fi',
      ));
    }
  }
}

/// Always reports an excellent connection, so the hero screenshot is stable.
class _DemoProbeClient implements ProbeClient {
  int _n = 0;

  @override
  Future<ProbeResult> probe(Uri url, {required Duration timeout}) async {
    _n++;
    return ProbeResult(ok: true, rttMs: 22 + (_n % 3) * 2, bytes: 700);
  }

  @override
  Future<TransferResult> transfer(Uri url, {required Duration timeout}) async {
    // ~48 Mbps once the engine's setup discount is applied.
    return const TransferResult(ok: true, bytes: 120000, elapsedMs: 64);
  }

  @override
  void close() {}
}

/// A store that always answers, so the paywall screenshot shows a real price
/// and the Pro screenshots do not need a transaction.
class _DemoIapGateway implements IapGateway {
  final _controller = StreamController<List<PurchaseDetails>>.broadcast();

  static final _product = ProductDetails(
    id: PurchaseController.proProductId,
    title: 'Honest Signal Pro',
    description: 'History, themes, custom intervals and the floating indicator.',
    price: '£2.99',
    rawPrice: 2.99,
    currencyCode: 'GBP',
    currencySymbol: '£',
  );

  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _controller.stream;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async =>
      ProductDetailsResponse(productDetails: [_product], notFoundIDs: const []);

  @override
  Future<bool> buyNonConsumable(PurchaseParam param) async {
    _emit(PurchaseStatus.purchased);
    return true;
  }

  @override
  Future<void> restorePurchases() async {
    if (ScreenshotMode.isPro) _emit(PurchaseStatus.restored);
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {}

  void _emit(PurchaseStatus status) {
    _controller.add([
      PurchaseDetails(
        productID: PurchaseController.proProductId,
        verificationData: PurchaseVerificationData(
          localVerificationData: 'demo',
          serverVerificationData: 'demo',
          source: 'demo',
        ),
        transactionDate: null,
        status: status,
      ),
    ]);
  }
}

class _DemoConnectivitySource implements ConnectivitySource {
  @override
  Future<NetworkKind> current() async => NetworkKind.wifi;

  @override
  Stream<NetworkKind> get changes => const Stream<NetworkKind>.empty();

  @override
  void dispose() {}
}

/// Guards against the demo data drifting away from what the real engine would
/// ever produce — a screenshot showing an impossible score would be a store
/// listing that misrepresents the app.
bool demoDataIsPlausible() {
  final composite = SignalScoring.composite(
    lossRatio: 0,
    latencyMs: 24,
    jitterMs: 4,
    throughputKbps: 48000,
  );
  return SignalScoring.bars(composite) == 5;
}
