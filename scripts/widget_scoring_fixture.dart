// Writes ios/HonestSignalWidget/Fixtures/scoring_fixture.json: expected widget
// scores computed by the app's own Dart scoring (SignalScoring), for checking
// the Swift port in ios/HonestSignalWidget/WidgetScoring.swift.
//
// Each case is scored the way a widget reading is: no throughput sample, no
// previous reading (so no hysteresis), no transfer-failure cap.
//
// Usage: dart run scripts/widget_scoring_fixture.dart  (or scripts/check_widget_scoring.sh)
import 'dart:convert';
import 'dart:io';

import 'package:honestsignal/features/measurement/domain/scoring.dart';

void main() {
  const latencies = <double?>[null, 5, 40, 41, 60, 80, 120, 180, 250, 400, 549, 599.9, 600, 750, 999, 1000, 2000];
  const jitters = <double?>[null, 0.5, 15, 40, 120, 250];
  const losses = <double>[0, 0.25, 1 / 3, 0.5, 0.75, 1];

  final cases = <Map<String, Object?>>[];
  for (final latency in latencies) {
    for (final jitter in jitters) {
      // Jitter only exists with at least two answered probes.
      if (latency == null && jitter != null) continue;
      for (final loss in losses) {
        final composite = SignalScoring.composite(
          lossRatio: loss,
          latencyMs: latency,
          jitterMs: jitter,
          throughputKbps: null,
        );
        cases.add({
          'latencyMs': latency,
          'jitterMs': jitter,
          'lossRatio': loss,
          'composite': composite,
          'bars': SignalScoring.bars(composite, lossRatio: loss, latencyMs: latency),
          'verdict': SignalScoring.verdict(
            SignalScoring.bars(composite, lossRatio: loss, latencyMs: latency),
          ),
        });
      }
    }
  }

  final out = File('ios/HonestSignalWidget/Fixtures/scoring_fixture.json');
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'source': 'lib/features/measurement/domain/scoring.dart (SignalScoring.composite with throughputKbps: null, SignalScoring.bars with no previousBars or cap)',
      'generator': 'scripts/widget_scoring_fixture.dart',
      'cases': cases,
    })}\n',
  );
  stdout.writeln('Wrote ${cases.length} cases to ${out.path}');
}
