import 'package:hive/hive.dart';

import '../domain/signal_sample.dart';

/// The rolling sample log behind the history screen.
///
/// Rows are appended with Hive's auto-increment keys and carry their own
/// timestamp in the value. Keying by `millisecondsSinceEpoch` would be the
/// obvious choice but Hive rejects integer keys above 0xFFFFFFFF, and an epoch
/// in milliseconds passed that in 1970 — every write would throw. Auto keys are
/// also monotonic, so insertion order is chronological order.
class HistoryRepository {
  HistoryRepository(this._box, {this.retention = defaultRetention});

  final Box<dynamic> _box;

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
    if (previous != null &&
        previous.bars == sample.bars &&
        previous.kind == sample.kind &&
        sample.timestamp.difference(previous.timestamp) < minimumSpacing) {
      return;
    }
    await _box.add(sample.toJson());
    await prune(sample.timestamp);
  }

  Future<void> prune(DateTime now) async {
    final cutoff = now.subtract(retention).millisecondsSinceEpoch;
    final stale = <dynamic>[];
    for (final key in _box.keys) {
      final timestamp = _timestampOf(_box.get(key));
      if (timestamp == null || timestamp < cutoff) stale.add(key);
    }
    if (stale.isNotEmpty) await _box.deleteAll(stale);
  }

  SignalSample? latest() {
    for (var i = _box.length - 1; i >= 0; i--) {
      final raw = _box.getAt(i);
      if (raw is Map) return SignalSample.fromJson(raw);
    }
    return null;
  }

  /// Samples inside [window], oldest first.
  ///
  /// Sorted explicitly rather than trusting insertion order: a device clock
  /// that jumps — a timezone change, or an NTP correction — would otherwise
  /// draw the chart backwards.
  List<SignalSample> since(DateTime now, Duration window) {
    final cutoff = now.subtract(window).millisecondsSinceEpoch;
    final samples = <SignalSample>[];
    for (final raw in _box.values) {
      final timestamp = _timestampOf(raw);
      if (timestamp != null && timestamp >= cutoff) {
        samples.add(SignalSample.fromJson(raw as Map<dynamic, dynamic>));
      }
    }
    samples.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return List.unmodifiable(samples);
  }

  Future<void> clear() => _box.clear();

  static int? _timestampOf(Object? raw) =>
      raw is Map ? (raw['ts'] as num?)?.toInt() : null;
}
