import 'dart:math' as math;

/// The Honest Signal scoring model.
///
/// Everything here is a pure function of measured numbers so the formula can be
/// unit-tested and reasoned about without a network. The formula is documented
/// in `docs/PRODUCT_SPEC.md` — keep the two in sync when tuning constants.
///
/// Four sub-scores are each normalised to 0..1 ("quality"), then blended with
/// fixed weights into a composite, which maps to 0..5 bars.
class SignalScoring {
  const SignalScoring._();

  // ---------------------------------------------------------------------------
  // Sub-score weights. Renormalised over whichever components are available, so
  // a cycle without a throughput sample still produces a sane composite.
  // ---------------------------------------------------------------------------
  static const double lossWeight = 0.30;
  static const double latencyWeight = 0.30;
  static const double throughputWeight = 0.25;
  static const double jitterWeight = 0.15;

  /// Round-trip time (ms) at or below which latency is considered perfect.
  static const double latencyBestMs = 40;

  /// Round-trip time (ms) at or above which latency scores zero.
  static const double latencyWorstMs = 600;

  /// Even with no transfer sample available, a one-second round trip makes a
  /// connection unsuitable for ordinary interactive use. The latency curve
  /// still reaches zero at 600 ms; this separate cap preserves the measured
  /// magnitude so 5 s is not reported as "Workable" between transfers.
  static const double unusableLatencyCapMs = 1000;
  static const int unusableLatencyBarCap = 1;

  /// At [latencyWorstMs] the latency component already scores zero. Letting the
  /// remaining components still carry the reading to three bars — "browsing and
  /// standard video work" — is not defensible at 700 ms, so the same knee caps
  /// the display at "Slow". Without this there is a 600–999 ms band where a
  /// cycle with no transfer sample reports a workable link.
  static const int poorLatencyBarCap = 2;

  /// Release thresholds for the two latency caps.
  ///
  /// The caps are step functions on a *continuous* measurement, so without a
  /// band of their own they reintroduce exactly the flicker the composite
  /// margin exists to prevent: a median oscillating 595/605 ms alternates the
  /// indicator every cycle while the composite sits perfectly still. The
  /// composite margin cannot damp this, because the discontinuity is on the
  /// latency axis and never reaches the composite.
  ///
  /// A cap therefore engages at its threshold and releases only below these
  /// lower figures. Whether one is currently engaged is inferred from
  /// `previousBars` — the reading already on screen — which keeps [bars] a pure
  /// function of its arguments instead of giving the model hidden state.
  static const double poorLatencyReleaseMs = 550;
  static const double unusableLatencyReleaseMs = 900;

  static const double jitterBestMs = 15;
  static const double jitterWorstMs = 200;

  /// Throughput (kbps) at or below which throughput scores zero.
  static const double throughputWorstKbps = 100;

  /// Throughput (kbps) at or above which throughput is considered perfect.
  /// 15 Mbps comfortably carries HD video and large downloads on mobile.
  static const double throughputBestKbps = 15000;

  /// Loss ratio at or above which loss scores zero.
  static const double lossWorstRatio = 0.5;

  /// Composite thresholds. `bars` is the largest index whose threshold the
  /// composite meets or exceeds.
  static const List<double> barThresholds = [0.0, 0.15, 0.32, 0.50, 0.68, 0.85];

  /// A bar change requires the composite to clear the neighbouring threshold by
  /// this margin. Without it the indicator flickers between two bars whenever
  /// the connection sits on a boundary, which reads as broken.
  static const double hysteresis = 0.03;

  /// Loss above this ratio caps the display at one bar no matter how fast the
  /// packets that *did* arrive were. A connection dropping a third of its
  /// requests is not a three-bar connection.
  static const double severeLossRatio = 1 / 3;

  /// Maps latency to 0..1 on a logarithmic curve — the perceptual difference
  /// between 40ms and 80ms is much larger than between 500ms and 540ms.
  static double latencyScore(double? medianMs) {
    if (medianMs == null) return 0;
    return _logNormalise(
      value: medianMs,
      best: latencyBestMs,
      worst: latencyWorstMs,
      lowerIsBetter: true,
    );
  }

  static double jitterScore(double? jitterMs) {
    if (jitterMs == null) return 0;
    return _logNormalise(
      value: math.max(jitterMs, 1),
      best: jitterBestMs,
      worst: jitterWorstMs,
      lowerIsBetter: true,
    );
  }

  static double throughputScore(double? kbps) {
    if (kbps == null) return 0;
    return _logNormalise(
      value: math.max(kbps, 1),
      best: throughputBestKbps,
      worst: throughputWorstKbps,
      lowerIsBetter: false,
    );
  }

  /// Loss is linear: users notice the first dropped request as much as the last.
  static double lossScore(double lossRatio) {
    final clamped = lossRatio.clamp(0.0, 1.0);
    if (clamped >= lossWorstRatio) return 0;
    return 1 - (clamped / lossWorstRatio);
  }

  /// Blends the available sub-scores into a 0..1 composite.
  ///
  /// [throughputKbps] may be null when this cycle skipped the transfer sample
  /// (data budget, or a sparse background cycle); its weight is redistributed.
  static double composite({
    required double lossRatio,
    required double? latencyMs,
    required double? jitterMs,
    required double? throughputKbps,
  }) {
    // Total loss means nothing else was measurable — don't let a stale
    // throughput reading prop up a dead connection.
    if (lossRatio >= 1.0) return 0;

    var weighted = 0.0;
    var totalWeight = 0.0;

    void add(double weight, double score) {
      weighted += weight * score;
      totalWeight += weight;
    }

    add(lossWeight, lossScore(lossRatio));
    if (latencyMs != null) add(latencyWeight, latencyScore(latencyMs));
    if (jitterMs != null) add(jitterWeight, jitterScore(jitterMs));
    if (throughputKbps != null) {
      add(throughputWeight, throughputScore(throughputKbps));
    }

    if (totalWeight == 0) return 0;
    return (weighted / totalWeight).clamp(0.0, 1.0);
  }

  /// A connection that answers latency probes but cannot complete a small
  /// download is the exact failure this app exists to expose — "full bars, no
  /// data". Latency and jitter will both look excellent, so the composite alone
  /// would report a healthy connection. Cap it hard instead.
  static const int transferFailureBarCap = 2;

  /// Maps a composite to 0..5 bars, holding [previousBars] until the composite
  /// clears the boundary by [hysteresis].
  ///
  /// [cap] applies after hysteresis, so a cap can always pull the indicator
  /// down immediately even if the previous reading was higher.
  static int bars(
    double composite, {
    int? previousBars,
    double lossRatio = 0,
    double? latencyMs,
    int? cap,
  }) {
    var result = 0;
    for (var i = barThresholds.length - 1; i >= 0; i--) {
      if (composite >= barThresholds[i]) {
        result = i;
        break;
      }
    }

    if (previousBars != null && result != previousBars) {
      // Moving up: require clearing the threshold we are moving above.
      // Moving down: require falling below the threshold we are leaving by the
      // same margin. Either way, boundary noise cannot drive the indicator.
      final boundary = result > previousBars
          ? barThresholds[previousBars + 1]
          : barThresholds[previousBars];
      final cleared = result > previousBars
          ? composite >= boundary + hysteresis
          : composite <= boundary - hysteresis;
      if (!cleared) result = previousBars;
    }

    if (cap != null && result > cap) result = cap;
    final latencyCap = latencyBarCap(latencyMs, previousBars: previousBars);
    if (latencyCap != null) result = math.min(result, latencyCap);
    if (lossRatio >= severeLossRatio && result > 1) result = 1;
    if (lossRatio >= 1.0) result = 0;
    return result;
  }

  /// The bar ceiling imposed by [latencyMs] alone, or null when latency imposes
  /// none. Exposed so the caps can be reasoned about — and tested — separately
  /// from the composite mapping.
  ///
  /// Each cap engages at its threshold and stays engaged down to its release
  /// threshold while [previousBars] is a reading that cap could have produced.
  /// See [poorLatencyReleaseMs] for why the band is needed.
  static int? latencyBarCap(double? latencyMs, {int? previousBars}) {
    if (latencyMs == null) return null;

    bool stillHolding(int barCap, double releaseMs) =>
        latencyMs >= releaseMs && previousBars != null && previousBars <= barCap;

    if (latencyMs >= unusableLatencyCapMs ||
        stillHolding(unusableLatencyBarCap, unusableLatencyReleaseMs)) {
      return unusableLatencyBarCap;
    }
    if (latencyMs >= latencyWorstMs ||
        stillHolding(poorLatencyBarCap, poorLatencyReleaseMs)) {
      return poorLatencyBarCap;
    }
    return null;
  }

  /// Short human label for a bar count, used on the home screen and in the
  /// notification. Deliberately describes capability, not signal strength.
  static String verdict(int bars) => switch (bars) {
    0 => 'No usable connection',
    1 => 'Barely usable',
    2 => 'Slow',
    3 => 'Workable',
    4 => 'Good',
    _ => 'Excellent',
  };

  static String verdictDetail(int bars) => switch (bars) {
    0 => 'Requests are timing out. Data is not getting through.',
    1 => 'Messages may send eventually. Pages and video will struggle.',
    2 => 'Fine for messaging and email. Video calls will suffer.',
    3 => 'Browsing and standard video work. Large transfers are slow.',
    4 => 'Comfortable for video calls, HD streaming and downloads.',
    _ => 'Fast and stable. Everything should feel instant.',
  };

  /// Normalises [value] onto 0..1 between [best] and [worst] on a log scale.
  static double _logNormalise({
    required double value,
    required double best,
    required double worst,
    required bool lowerIsBetter,
  }) {
    final v = math.max(value, 0.001);
    if (lowerIsBetter) {
      if (v <= best) return 1;
      if (v >= worst) return 0;
      return 1 - (math.log(v / best) / math.log(worst / best));
    }
    if (v >= best) return 1;
    if (v <= worst) return 0;
    return math.log(v / worst) / math.log(best / worst);
  }
}
