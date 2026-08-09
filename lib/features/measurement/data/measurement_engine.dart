import 'dart:async';
import 'dart:math' as math;

import '../domain/measurement_config.dart';
import '../domain/network_kind.dart';
import '../domain/probe_targets.dart';
import '../domain/scoring.dart';
import '../domain/signal_sample.dart';
import 'probe_client.dart';

/// The measurement engine.
///
/// Pure Dart with a single injected seam ([ProbeClient]) and an injected clock,
/// so the whole scoring path is exercised in unit tests with no network and no
/// real time. It holds no state beyond the last throughput reading; cadence,
/// budget and persistence all belong to the caller.
class MeasurementEngine {
  MeasurementEngine({
    required this._client,
    this._config = const MeasurementConfig(),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final ProbeClient _client;
  final MeasurementConfig _config;
  final DateTime Function() _now;

  MeasurementConfig get config => _config;

  double? _lastThroughputKbps;
  DateTime? _lastThroughputAt;

  /// Runs one full cycle and returns the resulting sample.
  ///
  /// [includeTransfer] is decided by the caller from the sampling cadence and
  /// the remaining daily data budget. [previousBars] feeds the hysteresis so
  /// the indicator does not flicker on a boundary.
  Future<SignalSample> measure({
    required NetworkKind kind,
    required bool includeTransfer,
    String? networkDetail,
    int? previousBars,
    int cycle = 0,
  }) async {
    if (kind == NetworkKind.none) {
      return SignalSample(
        timestamp: _now(),
        kind: NetworkKind.none,
        bars: 0,
        composite: 0,
        lossRatio: 1,
        probesSent: 0,
        bytesUsed: 0,
        networkDetail: networkDetail,
      );
    }

    final targets = ProbeTargets.latencyRotation(cycle, _config.probeCount);
    final rtts = <double>[];
    var attempted = 0;
    var failures = 0;
    var bytes = 0;
    var abortedDead = false;

    for (var i = 0; i < targets.length; i++) {
      attempted++;
      final result = await _client.probe(
        targets[i],
        timeout: _config.probeTimeout,
      );
      bytes += result.bytes;
      if (result.ok && result.rttMs != null) {
        rtts.add(result.rttMs!);
      } else {
        failures++;
        // Two consecutive dead probes on a network the OS calls "connected" is
        // already the answer; spending two more timeouts changes nothing except
        // the eight seconds the user waits for a verdict.
        if (failures >= 2 && rtts.isEmpty) {
          abortedDead = true;
          break;
        }
      }
      if (i < targets.length - 1) {
        await Future<void>.delayed(_config.interProbeGap);
      }
    }

    // `probesSent` counts probes actually attempted, because the home screen
    // prints it next to a data counter that only moved by what was really sent.
    // Total loss is asserted separately rather than by inflating the count: the
    // early abort means everything measurable was lost, not that four probes ran.
    final probesSent = math.max(attempted, 1);
    final lossRatio = abortedDead ? 1.0 : failures / probesSent;
    final median = _median(rtts);
    final jitter = _meanAbsoluteDeviation(rtts, median);

    double? throughput;
    var throughputStale = false;
    int? barCap;

    if (rtts.isNotEmpty && includeTransfer) {
      final outcome = await _sampleThroughput(median!);
      bytes += outcome.bytes;
      if (outcome.kbps != null) {
        throughput = outcome.kbps;
        _lastThroughputKbps = outcome.kbps;
        _lastThroughputAt = _now();
      } else {
        // Probes answered but bulk data would not move. This is the failure the
        // OS signal icon hides, so it is scored explicitly rather than left
        // unknown.
        throughput = 0;
        barCap = SignalScoring.transferFailureBarCap;
        _lastThroughputKbps = null;
        _lastThroughputAt = null;
      }
    } else if (rtts.isNotEmpty) {
      final carried = _freshThroughput();
      if (carried != null) {
        throughput = carried;
        throughputStale = true;
      }
    }

    final composite = SignalScoring.composite(
      lossRatio: lossRatio,
      latencyMs: median,
      jitterMs: jitter,
      throughputKbps: throughput,
    );

    final bars = SignalScoring.bars(
      composite,
      previousBars: previousBars,
      lossRatio: lossRatio,
      latencyMs: median,
      cap: barCap,
    );

    return SignalSample(
      timestamp: _now(),
      kind: kind,
      bars: bars,
      composite: composite,
      latencyMs: median,
      jitterMs: jitter,
      throughputKbps: throughput,
      throughputIsStale: throughputStale,
      lossRatio: lossRatio,
      probesSent: probesSent,
      bytesUsed: bytes,
      networkDetail: networkDetail,
    );
  }

  /// Downloads a sized sample and converts it to throughput, discounting the
  /// connection setup cost so a short transfer is not dominated by handshakes.
  Future<({double? kbps, int bytes})> _sampleThroughput(
    double medianRttMs,
  ) async {
    var spent = 0;
    for (final size in [_config.transferBytes, _config.transferBytes ~/ 3]) {
      final result = await _client.transfer(
        ProbeTargets.transfer(size),
        timeout: _config.transferTimeout,
      );
      spent += result.bytes;
      if (result.ok && result.bytes > 0 && result.elapsedMs > 0) {
        return (kbps: _toKbps(result, medianRttMs), bytes: spent);
      }
      // One retry at a third of the size: a genuinely weak link may manage the
      // smaller sample, and distinguishing "slow" from "broken" matters.
    }
    return (kbps: null, bytes: spent);
  }

  /// DNS, TCP and TLS cost roughly two round trips before the first byte. On a
  /// 120 KB sample over a high-latency link that setup can be most of the
  /// elapsed time, so charging it to throughput would report a fast connection
  /// as slow. The 25% floor stops the correction from inventing infinite speed
  /// when the transfer finishes in about one round trip.
  double _toKbps(TransferResult result, double medianRttMs) {
    final overhead = medianRttMs * 2;
    final effectiveMs = math.max(
      result.elapsedMs - overhead,
      result.elapsedMs * 0.25,
    );
    return (result.bytes * 8 / 1000) / (effectiveMs / 1000);
  }

  double? _freshThroughput() {
    final at = _lastThroughputAt;
    final value = _lastThroughputKbps;
    if (at == null || value == null) return null;
    if (_now().difference(at) > _config.throughputFreshness) return null;
    return value;
  }

  static double? _median(List<double> values) {
    if (values.isEmpty) return null;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  /// Mean absolute deviation rather than standard deviation: one outlier probe
  /// on an otherwise steady connection should not triple the reported jitter.
  static double? _meanAbsoluteDeviation(List<double> values, double? median) {
    if (values.length < 2 || median == null) return null;
    final total = values.fold<double>(0, (sum, v) => sum + (v - median).abs());
    return total / values.length;
  }

  void dispose() => _client.close();
}
