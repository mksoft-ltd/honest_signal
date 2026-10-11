import Foundation

// =============================================================================
// KEEP IN SYNC WITH DART.
//
// This is a port of the latency, jitter and loss part of the app's scoring
// model. The source of truth is lib/features/measurement/domain/scoring.dart
// (`SignalScoring`); every constant below names the Dart member it copies.
// When a constant or curve changes there, change it here too, then run
//   scripts/check_widget_scoring.sh
// which regenerates Fixtures/scoring_fixture.json from the Dart formulas and
// checks this file against it.
//
// Deliberately NOT ported:
//  - throughput (`throughputScore`, `throughputWeight`): the widget never runs
//    a transfer sample, so its weight is redistributed exactly as the app does
//    on a cycle without one (`SignalScoring.composite` with a null throughput).
//  - `transferFailureBarCap`: needs a transfer sample.
//  - hysteresis (`hysteresis`, `previousBars`, the latency-cap release bands):
//    widget readings are minutes apart, so there is no flicker to damp.
// So the widget's reading is what the app would show for a probe-only cycle,
// and can differ from the app's full score. The UI labels it "Quick check".
// =============================================================================

enum WidgetScoring {
    // SignalScoring.lossWeight / latencyWeight / jitterWeight
    static let lossWeight = 0.30
    static let latencyWeight = 0.30
    static let jitterWeight = 0.15

    // SignalScoring.latencyBestMs / latencyWorstMs
    static let latencyBestMs = 40.0
    static let latencyWorstMs = 600.0

    // SignalScoring.unusableLatencyCapMs / unusableLatencyBarCap / poorLatencyBarCap
    static let unusableLatencyCapMs = 1000.0
    static let unusableLatencyBarCap = 1
    static let poorLatencyBarCap = 2

    // SignalScoring.jitterBestMs / jitterWorstMs
    static let jitterBestMs = 15.0
    static let jitterWorstMs = 200.0

    // SignalScoring.lossWorstRatio / severeLossRatio
    static let lossWorstRatio = 0.5
    static let severeLossRatio = 1.0 / 3.0

    // SignalScoring.barThresholds
    static let barThresholds: [Double] = [0.0, 0.15, 0.32, 0.50, 0.68, 0.85]

    // SignalScoring.latencyScore
    static func latencyScore(_ medianMs: Double?) -> Double {
        guard let medianMs else { return 0 }
        return logNormalise(medianMs, best: latencyBestMs, worst: latencyWorstMs)
    }

    // SignalScoring.jitterScore
    static func jitterScore(_ jitterMs: Double?) -> Double {
        guard let jitterMs else { return 0 }
        return logNormalise(max(jitterMs, 1), best: jitterBestMs, worst: jitterWorstMs)
    }

    // SignalScoring.lossScore
    static func lossScore(_ lossRatio: Double) -> Double {
        let clamped = min(max(lossRatio, 0), 1)
        if clamped >= lossWorstRatio { return 0 }
        return 1 - (clamped / lossWorstRatio)
    }

    // SignalScoring.composite with throughputKbps == null
    static func composite(lossRatio: Double, latencyMs: Double?, jitterMs: Double?) -> Double {
        if lossRatio >= 1.0 { return 0 }
        var weighted = lossWeight * lossScore(lossRatio)
        var totalWeight = lossWeight
        if let latencyMs {
            weighted += latencyWeight * latencyScore(latencyMs)
            totalWeight += latencyWeight
        }
        if let jitterMs {
            weighted += jitterWeight * jitterScore(jitterMs)
            totalWeight += jitterWeight
        }
        return min(max(weighted / totalWeight, 0), 1)
    }

    // SignalScoring.bars with previousBars == null and cap == null
    static func bars(composite: Double, lossRatio: Double, latencyMs: Double?) -> Int {
        var result = 0
        for i in stride(from: barThresholds.count - 1, through: 0, by: -1)
        where composite >= barThresholds[i] {
            result = i
            break
        }
        if let cap = latencyBarCap(latencyMs) { result = min(result, cap) }
        if lossRatio >= severeLossRatio && result > 1 { result = 1 }
        if lossRatio >= 1.0 { result = 0 }
        return result
    }

    // SignalScoring.latencyBarCap with previousBars == null
    static func latencyBarCap(_ latencyMs: Double?) -> Int? {
        guard let latencyMs else { return nil }
        if latencyMs >= unusableLatencyCapMs { return unusableLatencyBarCap }
        if latencyMs >= latencyWorstMs { return poorLatencyBarCap }
        return nil
    }

    // SignalScoring.verdict
    static func verdict(_ bars: Int) -> String {
        switch bars {
        case ...0: return "No usable connection"
        case 1: return "Barely usable"
        case 2: return "Slow"
        case 3: return "Workable"
        case 4: return "Good"
        default: return "Excellent"
        }
    }

    // SignalScoring._logNormalise, lowerIsBetter == true (the only case used here)
    private static func logNormalise(_ value: Double, best: Double, worst: Double) -> Double {
        let v = max(value, 0.001)
        if v <= best { return 1 }
        if v >= worst { return 0 }
        return 1 - (log(v / best) / log(worst / best))
    }

    // MeasurementEngine._median
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    // MeasurementEngine._meanAbsoluteDeviation
    static func meanAbsoluteDeviation(_ values: [Double], median: Double?) -> Double? {
        guard values.count >= 2, let median else { return nil }
        return values.reduce(0) { $0 + abs($1 - median) } / Double(values.count)
    }
}
