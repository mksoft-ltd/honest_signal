import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:hive/hive.dart';

import '../domain/signal_sample.dart';

/// The rolling sample log behind the history screen.
///
/// Rows are appended with Hive's auto-increment keys and carry their own
/// timestamp in the value. Keying by `millisecondsSinceEpoch` would be the
/// obvious choice but Hive rejects integer keys above 0xFFFFFFFF, and an epoch
/// in milliseconds passed that in 1970 — every write would throw. Auto keys are
/// also monotonic, so insertion order is chronological order.
abstract class BackgroundHistoryBridge {
  Future<void> append(SignalSample sample);
  Future<List<SignalSample>> drain();
  Future<void> acknowledge(List<SignalSample> samples);
}

class PlatformBackgroundHistoryBridge implements BackgroundHistoryBridge {
  PlatformBackgroundHistoryBridge({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'com.froggyeye.honestsignal/budget';
  final MethodChannel _channel;

  @override
  Future<void> append(SignalSample sample) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('historyAppend', sample.toJson());
    } on Object {
      // History must never take down background measurement.
    }
  }

  @override
  Future<List<SignalSample>> drain() async {
    if (!Platform.isAndroid) return const [];
    try {
      final rows = await _channel.invokeListMethod<dynamic>('historyPeek');
      return [
        for (final row in rows ?? const [])
          if (row is Map) SignalSample.fromJson(row),
      ];
    } on Object {
      return const [];
    }
  }

  @override
  Future<void> acknowledge(List<SignalSample> samples) async {
    if (!Platform.isAndroid || samples.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('historyDrop', {
        'timestamps': [
          for (final sample in samples) sample.timestamp.millisecondsSinceEpoch,
        ],
      });
    } on Object {
      // Leaving rows queued is safe: the next import retries them.
    }
  }
}

class HistoryRepository {
  HistoryRepository(
    this._box, {
    this.retention = defaultRetention,
    BackgroundHistoryBridge? backgroundBridge,
  }) : _backgroundBridge =
           backgroundBridge ?? PlatformBackgroundHistoryBridge() {
    _rebuildCache();
  }

  final Box<dynamic> _box;
  final BackgroundHistoryBridge _backgroundBridge;
  final List<SignalSample> _samples = [];
  SignalSample? _latest;
  int _knownBoxLength = 0;

  /// 25 hours rather than 24 so a "last 24 hours" view always has a full window
  /// even mid-write.
  ///
  /// The in-app copy on the history and "How the score works" screens and the
  /// figure in `PRIVACY_POLICY.md` all quote this number, so it lives here once
  /// rather than being retyped into each of them.
  static const Duration defaultRetention = Duration(hours: 25);

  final Duration retention;

  /// Consecutive samples with the same score are not worth a row each; at a
  /// 5-second foreground cadence that would be 17k rows an hour. A sample is
  /// kept when the score changed, the network changed, or this much time has
  /// passed since the last stored one.
  static const Duration minimumSpacing = Duration(seconds: 30);

  Future<void> record(SignalSample sample) async {
    final previous = latest();
    if (!_shouldRecord(sample, previous)) return;
    await _box.add(sample.toJson());
    _samples.add(sample);
    _samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _latest = sample;
    _knownBoxLength = _box.length;
    await prune(sample.timestamp);
  }

  /// Moves samples written by the Android background isolate into Hive.
  /// Native storage is the hand-off queue because Hive boxes cannot safely be
  /// opened by both Flutter engines at once.
  Future<int> importBackgroundSamples() async {
    final pending = await _backgroundBridge.drain();
    if (pending.isEmpty) return 0;
    _refreshCacheIfChanged();

    // A failed batch is left unacknowledged and may already have been partly
    // written by the storage engine. Exact identities make that retry safe.
    final known = _samples.map(_identity).toSet();
    final accepted = <SignalSample>[];
    SignalSample? previous = _latest;
    for (final sample in pending) {
      if (!known.add(_identity(sample))) continue;
      if (!_shouldRecord(sample, previous)) continue;
      accepted.add(sample);
      previous = sample;
    }
    if (accepted.isNotEmpty) {
      await _box.addAll(accepted.map((sample) => sample.toJson()));
      await prune(accepted.last.timestamp);
    }
    await _backgroundBridge.acknowledge(pending);
    return pending.length;
  }

  Future<void> prune(DateTime now) async {
    final cutoff = now.subtract(retention).millisecondsSinceEpoch;
    final stale = <dynamic>[];
    for (final key in _box.keys) {
      final timestamp = _timestampOf(_box.get(key));
      if (timestamp == null || timestamp < cutoff) stale.add(key);
    }
    if (stale.isNotEmpty) await _box.deleteAll(stale);
    _rebuildCache();
  }

  SignalSample? latest() {
    _refreshCacheIfChanged();
    return _latest;
  }

  /// Samples inside [window], oldest first.
  ///
  /// Sorted explicitly rather than trusting insertion order: a device clock
  /// that jumps — a timezone change, or an NTP correction — would otherwise
  /// draw the chart backwards.
  List<SignalSample> since(DateTime now, Duration window) {
    _refreshCacheIfChanged();
    final cutoff = now.subtract(window).millisecondsSinceEpoch;
    return List.unmodifiable(
      _samples.where(
        (sample) => sample.timestamp.millisecondsSinceEpoch >= cutoff,
      ),
    );
  }

  Future<void> clear() async {
    _samples.clear();
    _latest = null;
    await _box.clear();
    _knownBoxLength = 0;
    final pending = await _backgroundBridge.drain();
    await _backgroundBridge.acknowledge(pending);
  }

  void _refreshCacheIfChanged() {
    if (_box.length != _knownBoxLength) _rebuildCache();
  }

  void _rebuildCache() {
    _samples.clear();
    _latest = null;
    for (final raw in _box.values) {
      if (raw is Map && _timestampOf(raw) != null) {
        final sample = SignalSample.fromJson(raw);
        _samples.add(sample);
        _latest = sample;
      }
    }
    _samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    _knownBoxLength = _box.length;
  }

  static int? _timestampOf(Object? raw) =>
      raw is Map ? (raw['ts'] as num?)?.toInt() : null;

  static bool _shouldRecord(SignalSample sample, SignalSample? previous) =>
      previous == null ||
      previous.bars != sample.bars ||
      previous.kind != sample.kind ||
      sample.timestamp.difference(previous.timestamp) >= minimumSpacing;

  static String _identity(SignalSample sample) => jsonEncode(sample.toJson());
}
