import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../indicator/data/indicator_channel.dart';
import '../../settings/domain/app_settings.dart';
import '../domain/data_budget.dart';
import '../domain/indicator_text.dart';
import '../domain/measurement_state.dart';
import '../domain/network_kind.dart';
import '../domain/signal_sample.dart';
import 'budget_store.dart';
import 'connectivity_source.dart';
import 'history_repository.dart';
import 'measurement_engine.dart';

/// Drives the engine while the app is on screen: cadence, data budget,
/// connectivity reactions, history, and the push to the Android status-bar
/// indicator.
///
/// Deliberately holds no Flutter widget dependencies so it can be exercised in
/// plain unit tests with fake time.
class MeasurementController extends ChangeNotifier {
  MeasurementController({
    required this._engine,
    required this._connectivity,
    required this._history,
    required this._budgetStore,
    required this._indicator,
    required AppSettings settings,
    DateTime Function()? clock,
  }) : _settings = settings,
       _now = clock ?? DateTime.now {
    _state = MeasurementState(
      sample: _history.latest() ?? SignalSample.unknown(),
      budget: DataBudget.empty(_now(), settings.dailyBudgetBytes),
    );
  }

  /// A throughput sample costs ~120 KB, so it runs on its own slower clock than
  /// the latency probes. While the user is watching the screen it refreshes
  /// often enough to catch a connection going bad; in the background the
  /// Android service uses the sparser figure.
  static const Duration foregroundTransferInterval = Duration(seconds: 90);
  static const Duration backgroundTransferInterval = Duration(minutes: 10);

  /// Hysteresis is only meaningful between adjacent, recent readings. A score
  /// from a previous session must not hold a fresh recovery reading down.
  static const Duration hysteresisFreshness = Duration(minutes: 2);

  final MeasurementEngine _engine;
  final ConnectivitySource _connectivity;
  final HistoryRepository _history;
  final BudgetStore _budgetStore;
  final IndicatorChannel _indicator;
  final DateTime Function() _now;

  AppSettings _settings;
  late MeasurementState _state;
  MeasurementState get state => _state;

  Timer? _timer;
  StreamSubscription<NetworkKind>? _connectivitySubscription;
  NetworkKind _kind = NetworkKind.other;
  DateTime? _lastTransferAt;
  int _cycle = 0;
  bool _inFlight = false;
  bool _started = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _kind = await _connectivity.current();
    _connectivitySubscription = _connectivity.changes.listen(
      _onConnectivityChanged,
    );
    await _refreshBudget();
    await _indicator.setUiActive(active: true);

    // The first reading after opening the app always includes a transfer
    // sample: the user came here to find out whether the connection works, and
    // latency alone cannot answer that.
    unawaited(measureNow(forceTransfer: true));
    _scheduleTimer();
  }

  /// Called from the app lifecycle observer. On Android the foreground service
  /// takes over when the UI goes away; on iOS measurement genuinely stops, and
  /// the home screen says so.
  Future<void> setForeground(bool foreground) async {
    if (!_started) {
      // A resumed lifecycle callback can beat HomeScreen's post-frame start.
      // Starting here is safe and idempotent; a background callback before
      // start remains a no-op, as there is no UI measurement to hand off.
      if (foreground) await start();
      return;
    }
    await _indicator.setUiActive(active: foreground);
    if (foreground) {
      _setState(_state.copyWith(pause: MeasurementPause.none));
      await _refreshBudget();
      unawaited(measureNow(forceTransfer: true));
      _scheduleTimer();
    } else {
      _timer?.cancel();
      _timer = null;
      _setState(_state.copyWith(pause: MeasurementPause.appBackgrounded));
    }
  }

  Future<void> applySettings(AppSettings settings) async {
    // Provider disposal and an asynchronous settings write can race. A
    // disposed controller must never refresh storage or notify listeners.
    if (_disposed) return;
    final intervalChanged =
        settings.foregroundIntervalSeconds !=
        _settings.foregroundIntervalSeconds;
    _settings = settings;
    await _refreshBudget();
    if (intervalChanged && _timer != null) _scheduleTimer();
    notifyListeners();
  }

  /// Runs a cycle immediately. [forceTransfer] overrides the transfer cadence
  /// (used on open, on manual refresh, and when the network changes).
  Future<void> measureNow({bool forceTransfer = false}) async {
    // Claimed synchronously, before the first await: the periodic timer fires
    // on its own schedule, and a tick landing mid-cycle would otherwise start a
    // second set of probes that double the data cost for the same answer.
    if (_inFlight || _disposed) return;
    _inFlight = true;

    try {
      if (_kind == NetworkKind.cellular && !_settings.measureOnCellular) {
        _setState(_state.copyWith(pause: MeasurementPause.cellularOptOut));
        return;
      }

      final budget = await _refreshBudget();

      // A spent budget does not blank the screen. Latency probes cost ~3 KB, so
      // they keep running and the user still gets a reading; only the 120 KB
      // transfer sample stops until tomorrow or until they raise the limit.
      final overBudget = budget.isExhausted;
      final includeTransfer =
          !overBudget &&
          (forceTransfer || _transferDue()) &&
          _kind != NetworkKind.none;

      _setState(
        _state.copyWith(
          measuring: true,
          pause: overBudget
              ? MeasurementPause.budgetExhausted
              : MeasurementPause.none,
        ),
      );

      final sample = await _engine.measure(
        kind: _kind,
        includeTransfer: includeTransfer,
        previousBars: _previousBarsForNextCycle(),
        cycle: _cycle++,
      );

      if (includeTransfer) _lastTransferAt = _now();

      final spent = sample.bytesUsed > 0
          ? await _budgetStore.spend(
              now: _now(),
              bytes: sample.bytesUsed,
              limitBytes: _settings.dailyBudgetBytes,
            )
          : budget;

      await _history.record(sample);
      _setState(
        _state.copyWith(sample: sample, budget: spent, measuring: false),
      );
      await _publishToIndicator(sample);
    } finally {
      _inFlight = false;
      if (!_disposed) _setState(_state.copyWith(measuring: false));
    }
  }

  Future<void> clearHistory() async {
    await _history.clear();
    notifyListeners();
  }

  List<SignalSample> historySince(Duration window) =>
      _history.since(_now(), window);

  bool _transferDue() {
    final last = _lastTransferAt;
    if (last == null) return true;
    return _now().difference(last) >= foregroundTransferInterval;
  }

  int? _previousBarsForNextCycle() {
    if (!_state.hasReading) return null;
    final age = _now().difference(_state.sample.timestamp);
    if (age > hysteresisFreshness) return null;
    return _state.sample.bars;
  }

  Future<DataBudget> _refreshBudget() async {
    final budget = await _budgetStore.read(
      now: _now(),
      limitBytes: _settings.dailyBudgetBytes,
    );
    _setState(_state.copyWith(budget: budget));
    return budget;
  }

  void _onConnectivityChanged(NetworkKind kind) {
    _kind = kind;
    // The moment the network changes is exactly when the old reading became
    // meaningless, so re-measure in full rather than waiting for the timer.
    unawaited(measureNow(forceTransfer: true));
  }

  Future<void> _publishToIndicator(SignalSample sample) async {
    if (!_settings.notificationIndicatorEnabled) return;
    await _indicator.publishSample(
      bars: sample.bars,
      verdict: sample.verdict,
      detail: IndicatorText.detail(sample),
      theme: _settings.barTheme.name,
      highContrast: _settings.highContrastIndicator,
      uiIntervalSeconds: _settings.foregroundIntervalSeconds,
    );
  }

  void _scheduleTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(
      _settings.foregroundInterval,
      (_) => unawaited(measureNow()),
    );
  }

  void _setState(MeasurementState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _connectivitySubscription?.cancel();
    // The engine and the connectivity source are owned by their own providers,
    // which close them; disposing them from here would close a client that
    // another consumer may still hold.
    super.dispose();
  }
}
