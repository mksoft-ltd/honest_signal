import 'history_stats.dart';
import 'network_kind.dart';
import 'signal_sample.dart';

/// One continuous stretch at 0–1 bars.
class Dropout {
  const Dropout({
    required this.start,
    required this.end,
    required this.worstBars,
    required this.kind,
    required this.ongoing,
  });

  final DateTime start;
  final DateTime end;

  /// The lowest score seen during the episode: 0 is "nothing got through",
  /// 1 is "barely usable".
  final int worstBars;

  /// The network the episode started on.
  final NetworkKind kind;

  /// Still poor at the end of the window, i.e. happening now.
  final bool ongoing;

  Duration get duration => end.difference(start);
}

/// How one kind of network behaved over a window.
class NetworkBreakdown {
  const NetworkBreakdown({
    required this.kind,
    required this.measured,
    required this.averageBars,
    required this.poorFraction,
    required this.medianLatency,
    required this.dropouts,
  });

  final NetworkKind kind;

  /// Time covered by readings on this network.
  final Duration measured;

  /// Time-weighted mean score, 0..5.
  final double averageBars;

  /// Share of [measured] spent at 0–1 bars.
  final double poorFraction;

  final double? medianLatency;
  final int dropouts;
}

/// Derived views over the stored step series. Everything here is built from
/// [HistoryInterval.fromSamples], the same freshness-bounded intervals the
/// chart draws and [HistoryStats] totals, so the list of drop-outs can never
/// disagree with the picture above it.
class HistoryInsights {
  const HistoryInsights._();

  /// Readings at or below this count as a drop-out.
  static const int poorBars = 1;

  /// Contiguous poor intervals, oldest first. A gap with no fresh reading ends
  /// an episode: the app does not know what happened in between, so it does
  /// not claim the outage lasted through it.
  static List<Dropout> dropouts(
    List<SignalSample> samples, {
    required DateTime end,
    required Duration maxHold,
  }) {
    final intervals = HistoryInterval.fromSamples(
      samples,
      end: end,
      maxHold: maxHold,
    );
    final out = <Dropout>[];
    DateTime? start;
    DateTime? last;
    var worst = 5;
    NetworkKind? kind;

    void close({required bool ongoing}) {
      if (start == null) return;
      out.add(
        Dropout(
          start: start!,
          end: last!,
          worstBars: worst,
          kind: kind!,
          ongoing: ongoing,
        ),
      );
      start = null;
      worst = 5;
      kind = null;
    }

    for (final interval in intervals) {
      final poor = interval.sample.bars <= poorBars;
      final contiguous = last != null && !interval.start.isAfter(last);
      if (start != null && (!poor || !contiguous)) close(ongoing: false);
      if (poor) {
        start ??= interval.start;
        kind ??= interval.sample.kind;
        if (interval.sample.bars < worst) worst = interval.sample.bars;
      }
      last = interval.end;
    }
    close(ongoing: last != null && !last.isBefore(end));
    return out;
  }

  /// Per network kind, busiest first. Kinds with no measured time are left
  /// out rather than shown as zeros.
  static List<NetworkBreakdown> byNetwork(
    List<SignalSample> samples, {
    required DateTime end,
    required Duration maxHold,
  }) {
    final intervals = HistoryInterval.fromSamples(
      samples,
      end: end,
      maxHold: maxHold,
    );
    final drops = dropouts(samples, end: end, maxHold: maxHold);
    final out = <NetworkBreakdown>[];
    for (final kind in NetworkKind.values) {
      final mine = intervals.where((i) => i.sample.kind == kind).toList();
      var totalMs = 0;
      var poorMs = 0;
      var weightedBars = 0.0;
      for (final interval in mine) {
        final ms = interval.duration.inMilliseconds;
        totalMs += ms;
        weightedBars += interval.sample.bars * ms;
        if (interval.sample.bars <= poorBars) poorMs += ms;
      }
      if (totalMs == 0) continue;
      final latencies =
          mine.map((i) => i.sample.latencyMs).whereType<double>().toList()
            ..sort();
      out.add(
        NetworkBreakdown(
          kind: kind,
          measured: Duration(milliseconds: totalMs),
          averageBars: weightedBars / totalMs,
          poorFraction: poorMs / totalMs,
          medianLatency: latencies.isEmpty
              ? null
              : latencies[latencies.length ~/ 2],
          dropouts: drops.where((d) => d.kind == kind).length,
        ),
      );
    }
    out.sort((a, b) => b.measured.compareTo(a.measured));
    return out;
  }
}
