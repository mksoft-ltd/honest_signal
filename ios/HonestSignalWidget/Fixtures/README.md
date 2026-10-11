# Widget scoring fixture

`scoring_fixture.json` holds expected widget scores computed by the app's Dart
scoring model, so the Swift port in `../WidgetScoring.swift` can be checked
against the source of truth.

How it is derived: `scripts/widget_scoring_fixture.dart` imports
`lib/features/measurement/domain/scoring.dart` and, for a grid of median
latency (incl. none and every cap boundary), jitter (incl. none) and loss ratio
(incl. the 1/3 severe-loss boundary and total loss), records
`SignalScoring.composite(..., throughputKbps: null)` and
`SignalScoring.bars(composite, lossRatio:, latencyMs:)` with no previous reading
and no cap — exactly how a widget reading is scored (no transfer sample, no
hysteresis).

Check after any change to `scoring.dart`:

    scripts/check_widget_scoring.sh

It regenerates the JSON, compiles `WidgetScoring.swift` with `CheckScoring.swift`
on the Mac, and fails on any composite (1e-9), bar or verdict mismatch. These
files are not part of the widget target.
