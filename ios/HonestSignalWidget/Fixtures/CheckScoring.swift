// Checks WidgetScoring.swift against scoring_fixture.json (generated from the
// Dart scoring). Not part of the widget target; run scripts/check_widget_scoring.sh.
import Foundation

struct Fixture: Decodable {
    struct Case: Decodable {
        let latencyMs: Double?
        let jitterMs: Double?
        let lossRatio: Double
        let composite: Double
        let bars: Int
        let verdict: String
    }
    let cases: [Case]
}

let path = CommandLine.arguments[1]
let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
var failures = 0
for c in fixture.cases {
    let composite = WidgetScoring.composite(lossRatio: c.lossRatio, latencyMs: c.latencyMs, jitterMs: c.jitterMs)
    let bars = WidgetScoring.bars(composite: composite, lossRatio: c.lossRatio, latencyMs: c.latencyMs)
    if abs(composite - c.composite) > 1e-9 || bars != c.bars || WidgetScoring.verdict(bars) != c.verdict {
        failures += 1
        print("MISMATCH \(c): swift composite=\(composite) bars=\(bars)")
    }
}
print("\(fixture.cases.count - failures)/\(fixture.cases.count) fixture cases match")
exit(failures == 0 ? 0 : 1)
