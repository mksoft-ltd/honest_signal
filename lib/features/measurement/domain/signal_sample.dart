import 'network_kind.dart';
import 'scoring.dart';

/// One completed measurement cycle.
///
/// Immutable and JSON-serialisable by hand — the app has three small models and
/// no server contract, so hand-written serialisation is cheaper to read than a
/// build_runner pipeline.
class SignalSample {
  const SignalSample({
    required this.timestamp,
    required this.kind,
    required this.bars,
    required this.composite,
    required this.lossRatio,
    required this.probesSent,
    required this.bytesUsed,
    this.latencyMs,
    this.jitterMs,
    this.throughputKbps,
    this.throughputIsStale = false,
    this.networkDetail,
  });

  final DateTime timestamp;
  final NetworkKind kind;

  /// 0..5, after hysteresis and the severe-loss cap.
  final int bars;

  /// The raw 0..1 composite this sample's bars came from.
  final double composite;

  /// Median round-trip time across the successful latency probes.
  final double? latencyMs;

  /// Mean absolute deviation of the probe round-trip times.
  final double? jitterMs;

  /// Estimated download throughput. Null when this cycle skipped the transfer
  /// sample; non-null but [throughputIsStale] when carried over from an earlier
  /// cycle within the freshness window.
  final double? throughputKbps;
  final bool throughputIsStale;

  /// Timed-out or failed probes as a fraction of probes sent.
  final double lossRatio;

  final int probesSent;

  /// Bytes this cycle spent, counted against the daily budget.
  final int bytesUsed;

  /// Best-effort extra detail, e.g. the Wi-Fi SSID-free descriptor or "Mobile".
  final String? networkDetail;

  bool get isOffline => kind == NetworkKind.none || lossRatio >= 1.0;

  String get verdict => SignalScoring.verdict(bars);
  String get verdictDetail => SignalScoring.verdictDetail(bars);

  SignalSample copyWith({int? bars, double? composite}) => SignalSample(
        timestamp: timestamp,
        kind: kind,
        bars: bars ?? this.bars,
        composite: composite ?? this.composite,
        latencyMs: latencyMs,
        jitterMs: jitterMs,
        throughputKbps: throughputKbps,
        throughputIsStale: throughputIsStale,
        lossRatio: lossRatio,
        probesSent: probesSent,
        bytesUsed: bytesUsed,
        networkDetail: networkDetail,
      );

  Map<String, dynamic> toJson() => {
        'ts': timestamp.millisecondsSinceEpoch,
        'kind': kind.name,
        'bars': bars,
        'composite': composite,
        'latency': latencyMs,
        'jitter': jitterMs,
        'throughput': throughputKbps,
        'stale': throughputIsStale,
        'loss': lossRatio,
        'probes': probesSent,
        'bytes': bytesUsed,
        'detail': networkDetail,
      };

  static SignalSample fromJson(Map<dynamic, dynamic> json) => SignalSample(
        timestamp: DateTime.fromMillisecondsSinceEpoch(
          (json['ts'] as num?)?.toInt() ?? 0,
        ),
        kind: NetworkKind.fromStorage(json['kind'] as String?),
        bars: (json['bars'] as num?)?.toInt() ?? 0,
        composite: (json['composite'] as num?)?.toDouble() ?? 0,
        latencyMs: (json['latency'] as num?)?.toDouble(),
        jitterMs: (json['jitter'] as num?)?.toDouble(),
        throughputKbps: (json['throughput'] as num?)?.toDouble(),
        throughputIsStale: json['stale'] as bool? ?? false,
        lossRatio: (json['loss'] as num?)?.toDouble() ?? 0,
        probesSent: (json['probes'] as num?)?.toInt() ?? 0,
        bytesUsed: (json['bytes'] as num?)?.toInt() ?? 0,
        networkDetail: json['detail'] as String?,
      );

  /// The sample shown before the first cycle completes.
  static SignalSample unknown() => SignalSample(
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
        kind: NetworkKind.other,
        bars: 0,
        composite: 0,
        lossRatio: 0,
        probesSent: 0,
        bytesUsed: 0,
      );

  bool get isPlaceholder => timestamp.millisecondsSinceEpoch == 0;
}
