import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/indicator_text.dart';
import '../domain/measurement_config.dart';
import '../domain/network_kind.dart';
import '../domain/signal_sample.dart';
import 'budget_store.dart';
import 'connectivity_source.dart';
import 'history_repository.dart';
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
    BackgroundHistoryBridge? historyBridge,
    DateTime Function()? clock,
  }) : _channel = channel ?? const MethodChannel(channelName),
       _engine =
           engine ??
           MeasurementEngine(
             client: HttpProbeClient(),
             // Four sequential foreground probes can take eight seconds on a dead
             // link. A single bounded probe lets the Android service attempt its
             // two-second background cadence without overlapping cycles.
             config: const MeasurementConfig(
               probeCount: 1,
               probeTimeout: Duration(milliseconds: 1500),
             ),
           ),
       _connectivity = connectivity ?? PluginConnectivitySource(),
       _budgetStore = budgetStore ?? PlatformBudgetStore(),
       _historyBridge = historyBridge ?? PlatformBackgroundHistoryBridge(),
       _now = clock ?? DateTime.now;

  static const String channelName = 'com.froggyeye.honestsignal/background';

  final MethodChannel _channel;
  final MeasurementEngine _engine;
  final ConnectivitySource _connectivity;
  final BudgetStore _budgetStore;
  final BackgroundHistoryBridge _historyBridge;
  final DateTime Function() _now;

  int _cycle = 0;
  int? _previousBars;
  int _consecutiveDeadProbes = 0;
  NetworkKind? _lastKind;
  DateTime? _lastTransferAt;
  bool _lastTransferFailed = false;
  SignalSample? _lastStoredSample;

  /// Transfer cadence in the background. Sparser than the foreground rate: the
  /// user is not watching, and a 120 KB sample every few minutes would dominate
  /// the daily budget on its own.
  static const Duration transferInterval = Duration(minutes: 10);
  static const Duration failedTransferRetryInterval = Duration(seconds: 30);

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
      intervalSeconds: (args['intervalSeconds'] as num?)?.toInt() ?? 2,
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
    int intervalSeconds = 2,
  }) async {
    final kind = await _connectivity.current();
    if (kind == NetworkKind.cellular && !measureOnCellular) return null;
    if (_lastKind != kind) {
      _consecutiveDeadProbes = 0;
      _previousBars = null;
      _lastTransferAt = null;
      _lastTransferFailed = false;
      _engine.resetTransfer();
      _lastKind = kind;
    }

    final now = _now();
    final budget = await _budgetStore.read(
      now: now,
      limitBytes: budgetLimitBytes,
    );

    final nextTransferInterval = _lastTransferFailed
        ? failedTransferRetryInterval
        : transferInterval;
    final transferDue =
        _lastTransferAt == null ||
        now.difference(_lastTransferAt!) >= nextTransferInterval;
    final includeTransfer =
        !budget.isExhausted && transferDue && kind != NetworkKind.none;

    var sample = await _engine.measure(
      kind: kind,
      includeTransfer: includeTransfer,
      previousBars: _previousBars,
      cycle: _cycle++,
    );
    var bytesSpent = sample.bytesUsed;
    var deadProbe =
        kind != NetworkKind.none &&
        sample.probesSent == 1 &&
        sample.lossRatio == 1;

    if (deadProbe && intervalSeconds > 2) {
      // A Pro interval can be minutes or an hour. Confirm on the next rotating
      // endpoint now; deferring to the next service tick would leave a dead
      // connection showing healthy bars for that whole interval.
      sample = await _engine.measure(
        kind: kind,
        includeTransfer: includeTransfer,
        previousBars: _previousBars,
        cycle: _cycle++,
      );
      bytesSpent += sample.bytesUsed;
      sample = sample.copyWith(bytesUsed: bytesSpent);
      deadProbe = sample.probesSent == 1 && sample.lossRatio == 1;
      _consecutiveDeadProbes = deadProbe ? 2 : 0;
    } else {
      _consecutiveDeadProbes = deadProbe ? _consecutiveDeadProbes + 1 : 0;
    }

    if (includeTransfer &&
        sample.throughputKbps != null &&
        !sample.throughputIsStale) {
      _lastTransferAt = now;
      _lastTransferFailed = sample.throughputKbps == 0;
    }

    if (bytesSpent > 0) {
      await _budgetStore.spend(
        now: now,
        bytes: bytesSpent,
        limitBytes: budgetLimitBytes,
      );
    }

    // A lone 5xx or timeout from one provider must not turn a working link
    // into zero bars. The next two-second tick rotates to another provider;
    // only a second failed probe confirms the outage. An OS-reported offline
    // network is already conclusive and is published immediately.
    if (deadProbe && _consecutiveDeadProbes == 1) return null;
    _previousBars = sample.bars;

    // The status-bar icon still receives every reading. Persisting an unchanged
    // score every two seconds would write 43,200 rows a day through native
    // SharedPreferences. Keep all meaningful transitions, and one heartbeat
    // per minute for a steady signal. The native queue caps rows if a wildly
    // flapping link generates more transitions than storage can retain.
    final previous = _lastStoredSample;
    final elapsed = previous == null
        ? const Duration(minutes: 1)
        : sample.timestamp.difference(previous.timestamp);
    if (previous == null ||
        previous.bars != sample.bars ||
        previous.kind != sample.kind ||
        elapsed.isNegative ||
        elapsed >= const Duration(minutes: 1)) {
      await _historyBridge.append(sample);
      _lastStoredSample = sample;
    }

    return sample;
  }
}
