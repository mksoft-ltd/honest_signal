import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/measurement/domain/history_stats.dart';
import 'package:honestsignal/features/measurement/domain/network_kind.dart';
import 'package:honestsignal/features/measurement/domain/signal_sample.dart';

void main() {
  SignalSample sample(DateTime at, int bars) => SignalSample(
    timestamp: at,
    kind: NetworkKind.wifi,
    bars: bars,
    composite: bars / 5,
    latencyMs: 40,
    lossRatio: 0,
    probesSent: 4,
    bytesUsed: 0,
  );

  test('time fractions weight elapsed duration, not stored row count', () {
    final start = DateTime(2026, 9, 25, 12);
    final stats = HistoryStats.from(
      [
        sample(start, 5),
        sample(start.add(const Duration(minutes: 1)), 0),
        sample(start.add(const Duration(minutes: 2)), 0),
      ],
      end: start.add(const Duration(minutes: 10)),
      maxHold: const Duration(minutes: 20),
    );

    expect(stats.goodFraction, closeTo(0.1, 0.0001));
    expect(stats.badFraction, closeTo(0.9, 0.0001));
  });

  test('a stale final reading is held only to the freshness boundary', () {
    final start = DateTime(2026, 9, 25, 12);
    final intervals = HistoryInterval.fromSamples(
      [sample(start, 5)],
      end: start.add(const Duration(hours: 1)),
      maxHold: const Duration(minutes: 10),
    );

    expect(intervals.single.start, start);
    expect(intervals.single.end, start.add(const Duration(minutes: 10)));
    final stats = HistoryStats.from(
      [sample(start, 5)],
      end: start.add(const Duration(hours: 1)),
      maxHold: const Duration(minutes: 10),
    );
    expect(stats.goodFraction, 1);
  });

  test('a next reading at the hold boundary starts a contiguous interval', () {
    final start = DateTime(2026, 9, 25, 12);
    final intervals = HistoryInterval.fromSamples(
      [sample(start, 5), sample(start.add(const Duration(minutes: 10)), 0)],
      end: start.add(const Duration(minutes: 20)),
      maxHold: const Duration(minutes: 10),
    );

    expect(intervals, hasLength(2));
    expect(intervals.first.end, intervals.last.start);
  });

  test('late next reading leaves a blank stale gap', () {
    final start = DateTime(2026, 9, 25, 12);
    final intervals = HistoryInterval.fromSamples(
      [sample(start, 5), sample(start.add(const Duration(minutes: 20)), 0)],
      end: start.add(const Duration(minutes: 30)),
      maxHold: const Duration(minutes: 10),
    );

    expect(intervals, hasLength(2));
    expect(
      intervals.last.start.difference(intervals.first.end),
      const Duration(minutes: 10),
    );
    final stats = HistoryStats.from(
      [sample(start, 5), sample(start.add(const Duration(minutes: 20)), 0)],
      end: start.add(const Duration(minutes: 30)),
      maxHold: const Duration(minutes: 10),
    );
    expect(stats.goodFraction, 0.5);
    expect(stats.badFraction, 0.5);
  });

  test('maximum hold respects storage cadence and background interval', () {
    expect(
      HistoryInterval.maximumHold(const Duration(seconds: 5)),
      const Duration(seconds: 60),
    );
    expect(
      HistoryInterval.maximumHold(const Duration(minutes: 5)),
      const Duration(minutes: 10),
    );
    expect(
      HistoryInterval.maximumHold(const Duration(hours: 1)),
      HistoryInterval.maximumFreshness,
    );
  });

  test('expected cadence follows only an active persistent indicator', () {
    expect(
      HistoryInterval.expectedInterval(
        foreground: const Duration(seconds: 5),
        background: const Duration(minutes: 5),
        persistentIndicatorActive: false,
      ),
      const Duration(seconds: 5),
    );
    expect(
      HistoryInterval.expectedInterval(
        foreground: const Duration(seconds: 5),
        background: const Duration(minutes: 5),
        persistentIndicatorActive: true,
      ),
      const Duration(minutes: 5),
    );
  });

  test('future and zero-duration samples contribute no measured time', () {
    final end = DateTime(2026, 9, 25, 12);
    final stats = HistoryStats.from(
      [sample(end, 5), sample(end.add(const Duration(minutes: 1)), 0)],
      end: end,
      maxHold: const Duration(minutes: 10),
    );

    expect(stats.goodFraction, 0);
    expect(stats.badFraction, 0);
    expect(stats.medianLatency, isNull);
    expect(stats.bestThroughput, isNull);
  });

  test('out-of-order input is normalised before durations are calculated', () {
    final start = DateTime(2026, 9, 25, 12);
    final stats = HistoryStats.from(
      [sample(start.add(const Duration(minutes: 5)), 0), sample(start, 5)],
      end: start.add(const Duration(minutes: 10)),
      maxHold: const Duration(minutes: 10),
    );

    expect(stats.goodFraction, 0.5);
    expect(stats.badFraction, 0.5);
  });
}
