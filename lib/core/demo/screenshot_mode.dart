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

  static const bool _flag = bool.fromEnvironment(
    'SCREENSHOT_MODE',
    defaultValue: false,
  );

  /// `pro` (default) shows the Pro screens; `free` captures the paywall and the
  /// locked states. Pass `--dart-define=SCREENSHOT_TIER=free` for those shots.
  static const String _tier = String.fromEnvironment(
    'SCREENSHOT_TIER',
    defaultValue: 'pro',
  );

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
      unawaited(
        store.spend(
          now: DateTime.now(),
          bytes: 6 * 1024 * 1024,
          limitBytes: 25 * 1024 * 1024,
        ),
      );
      return store;
    }),
  ];

  /// Fills the history box with a plausible hour: mostly good, with the kind
  /// of trouble the app exists to catch — the Wi-Fi falling over, the phone
  /// falling back to mobile data, and that failing too before things recover.
  ///
  /// Only the raw measurements are invented. Every composite and bar count is
  /// produced by [SignalScoring], so the chart, the drop-out list and the
  /// per-network breakdown are exactly what the real engine would show for
  /// these numbers.
  static Future<void> seedHistory(HistoryRepository history) async {
    final now = DateTime.now();
    final random = math.Random(7);
    int? previousBars;

    for (var minutesAgo = 60; minutesAgo >= 0; minutesAgo--) {
      final t = now.subtract(Duration(minutes: minutesAgo));
      final reading = _demoReading(minutesAgo, random);
      final composite = SignalScoring.composite(
        lossRatio: reading.loss,
        latencyMs: reading.latencyMs,
        jitterMs: reading.jitterMs,
        throughputKbps: reading.throughputKbps,
      );
      final bars = SignalScoring.bars(
        composite,
        previousBars: previousBars,
        lossRatio: reading.loss,
        latencyMs: reading.latencyMs,
      );
      previousBars = bars;

      await history.record(
        SignalSample(
          timestamp: t,
          kind: reading.kind,
          bars: bars,
          composite: composite,
          latencyMs: reading.latencyMs,
          jitterMs: reading.jitterMs,
          throughputKbps: reading.throughputKbps,
          lossRatio: reading.loss,
          probesSent: 4,
          bytesUsed: 0,
          networkDetail: reading.kind == NetworkKind.wifi
              ? 'Home Wi-Fi'
              : 'Mobile data',
        ),
      );
    }
  }

  /// The story, oldest first: solid home Wi-Fi; the router struggling and then
  /// failing (drop-out on Wi-Fi); the phone falling back to mobile data, which
  /// is slow and then drops out too (drop-out on cellular); mobile data
  /// recovering; Wi-Fi back and strong now.
  static ({
    NetworkKind kind,
    double? latencyMs,
    double? jitterMs,
    double? throughputKbps,
    double loss,
  })
  _demoReading(int minutesAgo, math.Random random) => switch (minutesAgo) {
    > 46 => (
      kind: NetworkKind.wifi,
      latencyMs: 24.0 + random.nextInt(8),
      jitterMs: 4,
      throughputKbps: 46000,
      loss: 0,
    ),
    > 40 => (
      kind: NetworkKind.wifi,
      latencyMs: 140,
      jitterMs: 45,
      throughputKbps: 4000,
      loss: 0,
    ),
    > 34 => (
      kind: NetworkKind.wifi,
      latencyMs: 650,
      jitterMs: 120,
      throughputKbps: 600,
      loss: 0.35,
    ),
    > 30 => (
      kind: NetworkKind.cellular,
      latencyMs: 380,
      jitterMs: 90,
      throughputKbps: 900,
      loss: 0,
    ),
    > 26 => (
      kind: NetworkKind.cellular,
      latencyMs: null,
      jitterMs: null,
      throughputKbps: null,
      loss: 1,
    ),
    > 14 => (
      kind: NetworkKind.cellular,
      latencyMs: 110,
      jitterMs: 30,
      throughputKbps: 4000,
      loss: 0,
    ),
    _ => (
      kind: NetworkKind.wifi,
      latencyMs: 24.0 + random.nextInt(8),
      jitterMs: 4,
      throughputKbps: 46000,
      loss: 0,
    ),
  };
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
    description:
        'History, themes, custom intervals and the floating indicator.',
    price: '£4.99',
    rawPrice: 4.99,
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
