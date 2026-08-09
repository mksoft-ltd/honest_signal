import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/indicator_text.dart';
import '../domain/network_kind.dart';
import '../domain/signal_sample.dart';
import 'budget_store.dart';
import 'connectivity_source.dart';
import 'measurement_engine.dart';
import 'probe_client.dart';

/// Runs the measurement engine inside the background Flutter engine that
/// `HonestSignalService` (Kotlin) hosts while the app is not on screen.
///
/// Timing lives on the Android side — an alarm/handler in the service is far
/// more reliable than a Dart timer in a process the system may freeze — so this
/// class is purely reactive: the service calls `runCycle`, this runs one
/// measurement and hands the sample back for the notification icon.
///
/// The scoring formula therefore exists in exactly one place, in Dart, rather
/// than being reimplemented in Kotlin where the two could drift apart.
class BackgroundMeasurementHost {
  BackgroundMeasurementHost({
    MethodChannel? channel,
    MeasurementEngine? engine,
    ConnectivitySource? connectivity,
    BudgetStore? budgetStore,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _engine = engine ?? MeasurementEngine(client: HttpProbeClient()),
        _connectivity = connectivity ?? PluginConnectivitySource(),
        _budgetStore = budgetStore ?? PlatformBudgetStore();

  static const String channelName = 'com.froggyeye.honestsignal/background';

  final MethodChannel _channel;
  final MeasurementEngine _engine;
  final ConnectivitySource _connectivity;
  final BudgetStore _budgetStore;

  int _cycle = 0;
  int? _previousBars;
  DateTime? _lastTransferAt;

  /// Transfer cadence in the background. Sparser than the foreground rate: the
  /// user is not watching, and a 120 KB sample every few minutes would dominate
  /// the daily budget on its own.
  static const Duration transferInterval = Duration(minutes: 10);

  void attach() {
    _channel.setMethodCallHandler(_handle);
    // Tells the service the isolate finished booting and plugins are
    // registered, so it can start its timer rather than guessing.
    _channel.invokeMethod<void>('backgroundReady');
  }

  Future<Object?> _handle(MethodCall call) async {
    if (call.method != 'runCycle') return null;
    final args = (call.arguments as Map?) ?? const {};
    final sample = await runCycle(
      measureOnCellular: args['measureOnCellular'] as bool? ?? true,
      budgetLimitBytes:
          (args['budgetLimitBytes'] as num?)?.toInt() ?? 25 * 1024 * 1024,
    );
    if (sample == null) return null;
    // The notification's title and body are composed here rather than in Kotlin
    // so the wording lives in one language, next to the model that produced it.
    return {
      ...sample.toJson(),
      'verdict': sample.verdict,
      'detail': IndicatorText.detail(sample),
    };
  }

  /// Returns null when this cycle deliberately did nothing, so the service
  /// leaves the previous icon in place rather than showing a false zero.
  Future<SignalSample?> runCycle({
    required bool measureOnCellular,
    required int budgetLimitBytes,
  }) async {
    final kind = await _connectivity.current();
    if (kind == NetworkKind.cellular && !measureOnCellular) return null;

    final now = DateTime.now();
    final budget = await _budgetStore.read(now: now, limitBytes: budgetLimitBytes);

    final transferDue = _lastTransferAt == null ||
        now.difference(_lastTransferAt!) >= transferInterval;
    final includeTransfer =
        !budget.isExhausted && transferDue && kind != NetworkKind.none;

    final sample = await _engine.measure(
      kind: kind,
      includeTransfer: includeTransfer,
      previousBars: _previousBars,
      cycle: _cycle++,
    );

    if (includeTransfer) _lastTransferAt = now;
    _previousBars = sample.bars;

    if (sample.bytesUsed > 0) {
      await _budgetStore.spend(
        now: now,
        bytes: sample.bytesUsed,
        limitBytes: budgetLimitBytes,
      );
    }

    return sample;
  }
}
