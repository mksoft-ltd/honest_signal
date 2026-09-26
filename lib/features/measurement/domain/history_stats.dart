import 'signal_sample.dart';

/// One measured interval in the stored step series.
///
/// A reading is held for at most twice the expected interval: this tolerates
/// one delayed/missed cycle without pretending an hours-old reading remained
/// true. The expected interval is never shorter than the 30-second storage
/// cadence, because unchanged foreground readings are deliberately coalesced.
class HistoryInterval {
  const HistoryInterval({
    required this.sample,
    required this.start,
    required this.end,
  });

  final SignalSample sample;
  final DateTime start;
  final DateTime end;

  Duration get duration => end.difference(start);

  /// Ten minutes is also the background transfer freshness scale. Beyond it,
  /// carrying any score would present an old network state as current even if
  /// a user deliberately selected a very sparse one-hour background cadence.
  static const Duration maximumFreshness = Duration(minutes: 10);

  static Duration maximumHold(Duration expectedInterval) {
    const storageCadence = Duration(seconds: 30);
    final cadence = expectedInterval < storageCadence
        ? storageCadence
        : expectedInterval;
    final twoCycles = cadence * 2;
    return twoCycles < maximumFreshness ? twoCycles : maximumFreshness;
  }

  static Duration expectedInterval({
    required Duration foreground,
    required Duration background,
    required bool persistentIndicatorActive,
  }) => persistentIndicatorActive ? background : foreground;

  static List<HistoryInterval> fromSamples(
    List<SignalSample> samples, {
    required DateTime end,
    required Duration maxHold,
  }) {
    if (maxHold <= Duration.zero) return const [];
    final ordered = [...samples]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final intervals = <HistoryInterval>[];
    for (var i = 0; i < ordered.length; i++) {
      final sample = ordered[i];
      if (!sample.timestamp.isBefore(end)) continue;
      final next = i + 1 < ordered.length ? ordered[i + 1].timestamp : end;
      final freshnessEnd = sample.timestamp.add(maxHold);
      final intervalEnd = next.isBefore(freshnessEnd) ? next : freshnessEnd;
      final clippedEnd = intervalEnd.isBefore(end) ? intervalEnd : end;
      if (clippedEnd.isAfter(sample.timestamp)) {
        intervals.add(
          HistoryInterval(
            sample: sample,
            start: sample.timestamp,
            end: clippedEnd,
          ),
        );
      }
    }
    return intervals;
  }
}

/// Summary of the periods represented by a step-series of signal samples.
/// Each reading remains in force until the next reading (or [end]); this makes
/// the percentages independent of foreground/background sampling cadence.
class HistoryStats {
  const HistoryStats({
    required this.goodFraction,
    required this.badFraction,
    required this.medianLatency,
    required this.bestThroughput,
  });

  final double goodFraction;
  final double badFraction;
  final double? medianLatency;
  final double? bestThroughput;

  factory HistoryStats.from(
    List<SignalSample> samples, {
    required DateTime end,
    required Duration maxHold,
  }) {
    if (samples.isEmpty) {
      return const HistoryStats(
        goodFraction: 0,
        badFraction: 0,
        medianLatency: null,
        bestThroughput: null,
      );
    }

    var totalMs = 0;
    var goodMs = 0;
    var badMs = 0;
    final intervals = HistoryInterval.fromSamples(
      samples,
      end: end,
      maxHold: maxHold,
    );
    for (final interval in intervals) {
      final milliseconds = interval.duration.inMilliseconds.clamp(0, 1 << 53);
      totalMs += milliseconds;
      if (interval.sample.bars >= 4) goodMs += milliseconds;
      if (interval.sample.bars <= 1) badMs += milliseconds;
    }

    final measuredSamples = intervals.map((interval) => interval.sample);
    final latencies =
        measuredSamples.map((s) => s.latencyMs).whereType<double>().toList()
          ..sort();
    final throughputs = measuredSamples
        .map((s) => s.throughputKbps)
        .whereType<double>()
        .toList();
    return HistoryStats(
      goodFraction: totalMs == 0 ? 0 : goodMs / totalMs,
      badFraction: totalMs == 0 ? 0 : badMs / totalMs,
      medianLatency: latencies.isEmpty
          ? null
          : latencies[latencies.length ~/ 2],
      bestThroughput: throughputs.isEmpty
          ? null
          : throughputs.reduce((a, b) => a > b ? a : b),
    );
  }
}
