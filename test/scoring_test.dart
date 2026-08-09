import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/measurement/domain/scoring.dart';

void main() {
  group('sub-scores', () {
    test('latency is perfect at or below the best threshold and zero at worst', () {
      expect(SignalScoring.latencyScore(10), 1.0);
      expect(SignalScoring.latencyScore(SignalScoring.latencyBestMs), 1.0);
      expect(SignalScoring.latencyScore(SignalScoring.latencyWorstMs), 0.0);
      expect(SignalScoring.latencyScore(5000), 0.0);
    });

    test('latency falls on a log curve, so the mid-point is not 320 ms', () {
      // Linear interpolation between 40 and 600 would put 0.5 at 320 ms. The
      // geometric mean (~155 ms) is the log-scale midpoint, and that is the
      // behaviour the model intends: 40->80 matters more than 500->540.
      final geometricMid = SignalScoring.latencyScore(155);
      expect(geometricMid, closeTo(0.5, 0.02));
      expect(SignalScoring.latencyScore(320), lessThan(0.35));
    });

    test('loss is linear and hits zero at the worst ratio', () {
      expect(SignalScoring.lossScore(0), 1.0);
      expect(SignalScoring.lossScore(0.25), closeTo(0.5, 0.001));
      expect(SignalScoring.lossScore(SignalScoring.lossWorstRatio), 0.0);
      expect(SignalScoring.lossScore(1.0), 0.0);
    });

    test('throughput is perfect at the best threshold and zero at the worst', () {
      expect(SignalScoring.throughputScore(SignalScoring.throughputBestKbps), 1.0);
      expect(SignalScoring.throughputScore(50000), 1.0);
      expect(SignalScoring.throughputScore(SignalScoring.throughputWorstKbps), 0.0);
      expect(SignalScoring.throughputScore(0), 0.0);
    });

    test('a null measurement scores zero rather than throwing', () {
      expect(SignalScoring.latencyScore(null), 0.0);
      expect(SignalScoring.jitterScore(null), 0.0);
      expect(SignalScoring.throughputScore(null), 0.0);
    });
  });

  group('composite', () {
    test('a fast, steady, lossless connection scores near 1', () {
      final score = SignalScoring.composite(
        lossRatio: 0,
        latencyMs: 20,
        jitterMs: 3,
        throughputKbps: 40000,
      );
      expect(score, closeTo(1.0, 0.001));
    });

    test('total loss scores zero even with a good throughput reading', () {
      final score = SignalScoring.composite(
        lossRatio: 1.0,
        latencyMs: 20,
        jitterMs: 2,
        throughputKbps: 40000,
      );
      expect(score, 0.0);
    });

    test('a missing throughput sample redistributes its weight', () {
      // With every other component perfect, dropping throughput must not drag
      // the score down — otherwise a cheap latency-only cycle would report a
      // worse connection than an identical one that spent the data.
      final withoutThroughput = SignalScoring.composite(
        lossRatio: 0,
        latencyMs: 20,
        jitterMs: 3,
        throughputKbps: null,
      );
      expect(withoutThroughput, closeTo(1.0, 0.001));
    });
  });

  group('bars', () {
    test('maps composites to the documented thresholds', () {
      expect(SignalScoring.bars(0.0), 0);
      expect(SignalScoring.bars(0.20), 1);
      expect(SignalScoring.bars(0.40), 2);
      expect(SignalScoring.bars(0.55), 3);
      expect(SignalScoring.bars(0.75), 4);
      expect(SignalScoring.bars(0.95), 5);
    });

    test('hysteresis holds the previous level inside the margin', () {
      // 0.51 is just over the 3-bar threshold of 0.50. Coming up from 2 bars it
      // must not flip until it clears 0.50 + 0.03.
      expect(SignalScoring.bars(0.51, previousBars: 2), 2);
      expect(SignalScoring.bars(0.54, previousBars: 2), 3);
    });

    test('hysteresis also resists dropping a level on boundary noise', () {
      expect(SignalScoring.bars(0.49, previousBars: 3), 3);
      expect(SignalScoring.bars(0.46, previousBars: 3), 2);
    });

    test('severe loss caps the display at one bar', () {
      // Latency and jitter can look perfect while a third of requests vanish.
      expect(
        SignalScoring.bars(0.9, lossRatio: SignalScoring.severeLossRatio),
        1,
      );
    });

    test('total loss forces zero regardless of hysteresis', () {
      expect(SignalScoring.bars(0.9, previousBars: 5, lossRatio: 1.0), 0);
    });

    test('an explicit cap overrides a higher previous reading immediately', () {
      // The transfer-failure cap must not be softened by hysteresis: the whole
      // point is to drop fast when data stops moving.
      expect(
        SignalScoring.bars(
          0.9,
          previousBars: 5,
          cap: SignalScoring.transferFailureBarCap,
        ),
        SignalScoring.transferFailureBarCap,
      );
    });
  });

  test('every bar level has a verdict and a detail line', () {
    for (var bars = 0; bars <= 5; bars++) {
      expect(SignalScoring.verdict(bars), isNotEmpty);
      expect(SignalScoring.verdictDetail(bars), isNotEmpty);
    }
  });

  test('weights sum to 1 so the documented percentages are honest', () {
    final total = SignalScoring.lossWeight +
        SignalScoring.latencyWeight +
        SignalScoring.throughputWeight +
        SignalScoring.jitterWeight;
    expect(total, closeTo(1.0, 1e-9));
  });
}
