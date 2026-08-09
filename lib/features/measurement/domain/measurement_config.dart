/// Tunables for one measurement cycle.
class MeasurementConfig {
  const MeasurementConfig({
    this.probeCount = 4,
    this.probeTimeout = const Duration(seconds: 2),
    this.transferBytes = 120000,
    this.transferTimeout = const Duration(seconds: 8),
    this.throughputFreshness = const Duration(minutes: 5),
    this.interProbeGap = const Duration(milliseconds: 60),
  });

  /// Latency probes per cycle. Four is the smallest count that gives a usable
  /// median plus a meaningful loss fraction (0, 25, 50, 75, 100%).
  final int probeCount;

  /// A probe that has not answered in this long is counted as lost. Two seconds
  /// is well beyond any working mobile connection's round trip.
  final Duration probeTimeout;

  /// Size of the throughput sample. ~120 KB is large enough to escape TCP slow
  /// start on a decent link and small enough that a full day of sampling stays
  /// inside a sane data budget.
  final int transferBytes;

  final Duration transferTimeout;

  /// How long a throughput reading may be reused on cycles that skip the
  /// transfer sample before the engine reports throughput as unknown.
  final Duration throughputFreshness;

  /// Small pause between probes so they measure independent round trips rather
  /// than queueing behind each other.
  final Duration interProbeGap;

  MeasurementConfig copyWith({int? probeCount, int? transferBytes}) =>
      MeasurementConfig(
        probeCount: probeCount ?? this.probeCount,
        probeTimeout: probeTimeout,
        transferBytes: transferBytes ?? this.transferBytes,
        transferTimeout: transferTimeout,
        throughputFreshness: throughputFreshness,
        interProbeGap: interProbeGap,
      );
}
