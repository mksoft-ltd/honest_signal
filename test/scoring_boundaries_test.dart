import 'package:flutter_test/flutter_test.dart';
import 'package:honestsignal/features/measurement/domain/scoring.dart';

/// The exact edges of the bar mapping.
///
/// `scoring_test.dart` covers the shape of the model; this file pins the
/// arithmetic at the boundaries, where an off-by-a-hair change would show up on
/// device as an indicator that flickers, sticks, or refuses to fall.
void main() {
  group('hysteresis boundaries', () {
    test('a rise moves exactly at the margin, and not a hair before', () {
      // The 3-bar threshold is 0.50 and the margin is 0.03.
      expect(SignalScoring.bars(0.5299, previousBars: 2), 2);
      expect(SignalScoring.bars(0.53, previousBars: 2), 3);
    });

    test('a fall moves exactly at the margin, and not a hair before', () {
      expect(SignalScoring.bars(0.4701, previousBars: 3), 3);
      expect(SignalScoring.bars(0.47, previousBars: 3), 2);
    });

    test('a composite that maps to the level already shown is left alone', () {
      // No boundary is being crossed, so the margin must not enter into it.
      for (final composite in [0.50, 0.55, 0.60, 0.67]) {
        expect(SignalScoring.bars(composite, previousBars: 3), 3);
      }
    });

    test('the margin is far narrower than the narrowest band, so no level is '
        'unreachable', () {
      // If tuning ever made a band narrower than twice the margin, a connection
      // could never settle inside it and the indicator would jump over it.
      var narrowest = double.infinity;
      for (var i = 1; i < SignalScoring.barThresholds.length; i++) {
        final gap =
            SignalScoring.barThresholds[i] - SignalScoring.barThresholds[i - 1];
        if (gap < narrowest) narrowest = gap;
      }
      expect(SignalScoring.hysteresis * 2, lessThan(narrowest));
    });

    test('a large recovery clears the first boundary crossed, then reports '
        'the measured level without an artificial slew rate', () {
      // The specification says hysteresis applies at the boundary being
      // crossed, not at the destination's boundary. From zero, 0.51 has
      // cleared the 1-bar boundary (0.15 + 0.03) and is genuinely 3 bars.
      expect(SignalScoring.bars(0.51, previousBars: 0), 3);
      expect(SignalScoring.bars(0.86, previousBars: 0), 5);
      // The 1-bar boundary still suppresses jitter immediately above it.
      expect(SignalScoring.bars(0.1799, previousBars: 0), 0);
      expect(SignalScoring.bars(0.18, previousBars: 0), 1);
    });

    test('with no previous reading the raw mapping applies', () {
      expect(SignalScoring.bars(0.51), 3);
      expect(SignalScoring.bars(0.86), 5);
    });
  });

  group('cap ordering', () {
    test(
      'a cap pulls down through hysteresis but never lifts a lower reading',
      () {
        expect(SignalScoring.bars(0.9, previousBars: 5, cap: 2), 2);
        // A cap above the measured level changes nothing.
        expect(SignalScoring.bars(0.10, previousBars: 0, cap: 4), 0);
      },
    );

    test('severe loss outranks a generous cap', () {
      // Loss is applied after the cap, so a cap of 5 cannot rescue a connection
      // dropping a third of its requests.
      expect(SignalScoring.bars(0.9, lossRatio: 0.4, cap: 5), 1);
    });

    test('the severe-loss cap starts exactly at a third', () {
      expect(SignalScoring.bars(0.9, lossRatio: 0.32), 5);
      expect(
        SignalScoring.bars(0.9, lossRatio: SignalScoring.severeLossRatio),
        1,
      );
    });

    test(
      'total loss forces zero whatever the cap and the previous reading say',
      () {
        expect(
          SignalScoring.bars(0.9, previousBars: 5, lossRatio: 1.0, cap: 4),
          0,
        );
      },
    );
  });

  group('latency-only safety cap', () {
    test('a lossless link with no transfer sample cannot be called workable '
        'when its round trip is at least one second', () {
      // Independently derived from PRODUCT_SPEC §5: one-second interactive
      // round trips are only barely usable, even if a sparse cycle has no
      // throughput sample to include in the blend.
      final composite = SignalScoring.composite(
        lossRatio: 0,
        latencyMs: 5000,
        jitterMs: 20,
        throughputKbps: null,
      );
      expect(composite, greaterThanOrEqualTo(0.5));
      expect(
        SignalScoring.bars(composite, latencyMs: 5000),
        SignalScoring.unusableLatencyBarCap,
      );
    });

    test('the 600-999 ms band cannot report a workable link either', () {
      // The band the second cap exists for. Derived from PRODUCT_SPEC §5:
      // 600 ms is where the latency sub-score already reaches zero, so a
      // no-transfer cycle whose remaining components are perfect would
      // otherwise still be carried to 3 bars, "browsing and standard video
      // work". 700 ms was the reviewer's worked example.
      final composite = SignalScoring.composite(
        lossRatio: 0,
        latencyMs: 700,
        jitterMs: 20,
        throughputKbps: null,
      );
      expect(composite, greaterThanOrEqualTo(0.5), reason: 'raw maps to 3 bars');
      expect(
        SignalScoring.bars(composite, latencyMs: 700),
        SignalScoring.poorLatencyBarCap,
      );

      // The knee is exactly latencyWorstMs, and a hair below it is untouched.
      expect(SignalScoring.bars(0.9, latencyMs: 600), 2);
      expect(SignalScoring.bars(0.9, latencyMs: 599.9), 5);
      // The two caps do not overlap: the stricter one wins at 1,000 ms.
      expect(SignalScoring.bars(0.9, latencyMs: 999.9), 2);
      expect(SignalScoring.bars(0.9, latencyMs: 1000), 1);
    });

    test('a latency sitting on a knee does not flap the indicator', () {
      // N1. The caps are step functions on a continuous measurement, so without
      // a release band they alternate the reading every cycle while the
      // composite sits perfectly still — the flicker hysteresis exists to
      // prevent, moved onto the latency axis. Both sequences were [3,2,3,2,…]
      // and [2,1,2,1,…] before the band existed.
      List<int> run(List<double> latencies, double composite) {
        int? previous;
        return [
          for (final latency in latencies)
            previous = SignalScoring.bars(
              composite,
              previousBars: previous,
              latencyMs: latency,
            ),
        ];
      }

      final acrossPoorKnee = run(
        [for (var i = 0; i < 10; i++) i.isEven ? 605.0 : 595.0],
        0.60,
      );
      expect(acrossPoorKnee.toSet(), hasLength(1), reason: '$acrossPoorKnee');
      expect(acrossPoorKnee.first, SignalScoring.poorLatencyBarCap);

      final acrossUnusableKnee = run(
        [for (var i = 0; i < 10; i++) i.isEven ? 1010.0 : 990.0],
        0.60,
      );
      expect(
        acrossUnusableKnee.toSet(),
        hasLength(1),
        reason: '$acrossUnusableKnee',
      );
      expect(acrossUnusableKnee.first, SignalScoring.unusableLatencyBarCap);
    });

    test('the release band lets a genuinely recovered link back up', () {
      // The band must be sticky, not a trapdoor. Below the release threshold
      // the cap lifts on the very next cycle.
      expect(
        SignalScoring.latencyBarCap(595, previousBars: 2),
        SignalScoring.poorLatencyBarCap,
      );
      expect(
        SignalScoring.latencyBarCap(
          SignalScoring.poorLatencyReleaseMs - 0.1,
          previousBars: 2,
        ),
        isNull,
      );
      // Holding only applies to a reading the cap itself could have produced —
      // a fast link dipping to 595 ms is not retroactively capped.
      expect(SignalScoring.latencyBarCap(595, previousBars: 5), isNull);
      // With no previous reading there is nothing to hold, so only the engage
      // threshold applies. This is the cold-start path.
      expect(SignalScoring.latencyBarCap(595), isNull);
      expect(
        SignalScoring.latencyBarCap(600),
        SignalScoring.poorLatencyBarCap,
      );
    });
  });

  group('invariants', () {
    test('the documented thresholds are exactly what the code uses', () {
      // These five numbers are printed in the app's own "How the score works"
      // screen and in docs/PRODUCT_SPEC.md. The product claim is that the
      // method is not a secret, so the three must not drift apart.
      expect(SignalScoring.barThresholds, [0.0, 0.15, 0.32, 0.50, 0.68, 0.85]);
    });

    test('the documented weights are exactly what the code uses', () {
      expect(SignalScoring.lossWeight, 0.30);
      expect(SignalScoring.latencyWeight, 0.30);
      expect(SignalScoring.throughputWeight, 0.25);
      expect(SignalScoring.jitterWeight, 0.15);
    });

    test('thresholds ascend and start at zero', () {
      expect(SignalScoring.barThresholds.first, 0.0);
      for (var i = 1; i < SignalScoring.barThresholds.length; i++) {
        expect(
          SignalScoring.barThresholds[i],
          greaterThan(SignalScoring.barThresholds[i - 1]),
        );
      }
    });

    test('every composite in range maps to a bar in range', () {
      for (var step = 0; step <= 100; step++) {
        final bars = SignalScoring.bars(step / 100);
        expect(bars, inInclusiveRange(0, 5));
      }
    });

    test('a composite outside 0..1 is clamped rather than thrown', () {
      expect(SignalScoring.bars(-1), 0);
      expect(SignalScoring.bars(2), 5);
    });

    test('composite never leaves 0..1 for any plausible measurement', () {
      for (final loss in [0.0, 0.25, 0.5, 0.75, 1.0]) {
        for (final latency in [1.0, 40.0, 300.0, 5000.0]) {
          for (final jitter in [null, 0.0, 15.0, 900.0]) {
            for (final throughput in [null, 0.0, 100.0, 90000.0]) {
              final composite = SignalScoring.composite(
                lossRatio: loss,
                latencyMs: latency,
                jitterMs: jitter,
                throughputKbps: throughput,
              );
              expect(composite, inInclusiveRange(0.0, 1.0));
            }
          }
        }
      }
    });

    test('a negative loss ratio cannot score better than perfect', () {
      expect(SignalScoring.lossScore(-1), 1.0);
    });

    test('every bar level has a distinct verdict', () {
      final verdicts = {for (var b = 0; b <= 5; b++) SignalScoring.verdict(b)};
      expect(verdicts, hasLength(6));
    });
  });
}
