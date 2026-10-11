import Foundation
import Network
import os

/// One widget reading. The widget measures for itself because it cannot read
/// the app's results without an App Group.
struct WidgetReading {
    enum Network: String {
        case wifi = "Wi-Fi"
        case cellular = "Cellular"
        case ethernet = "Ethernet"
        case other = "Other"
        case none = "Offline"
    }

    let date: Date
    let network: Network
    let bars: Int
    let latencyMs: Double?
    let lossRatio: Double

    var isOffline: Bool { network == .none || lossRatio >= 1.0 }

    var verdict: String { isOffline ? "No connection" : WidgetScoring.verdict(bars) }

    static func offline(at date: Date, network: Network = .none) -> WidgetReading {
        WidgetReading(date: date, network: network, bars: 0, latencyMs: nil, lossRatio: 1)
    }
}

/// A probe-only measurement cycle, mirroring MeasurementEngine.measure with
/// includeTransfer == false. No transfer sample is ever taken from the widget.
///
/// Requests go to the same public connectivity-check endpoints as the app
/// (ProbeTargets.latency in lib/features/measurement/domain/probe_targets.dart)
/// over an ephemeral session with no cookies, no cache and no identifiers.
enum WidgetProbe {
    // ProbeTargets.latency
    static let targets = [
        URL(string: "https://www.gstatic.com/generate_204")!,
        URL(string: "https://cp.cloudflare.com/generate_204")!,
        URL(string: "https://connectivitycheck.gstatic.com/generate_204")!,
    ]

    // MeasurementConfig.probeCount / probeTimeout / interProbeGap. Four probes,
    // not three: with three, a single lost probe is a 1/3 loss ratio, which
    // trips SignalScoring.severeLossRatio and caps the reading at one bar where
    // the app (losing one of four) would not. Worst case is still ~8 s.
    static let probeCount = 4
    static let probeTimeout: Duration = .seconds(2)
    static let interProbeGap: Duration = .milliseconds(60)

    // HttpProbeClient.maxProbeResponseBytes
    static let maxProbeResponseBytes = 8192

    static func measure(now: Date = Date()) async -> WidgetReading {
        let network = await currentNetwork()
        if network == .none { return .offline(at: now) }

        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }

        // ProbeTargets.latencyRotation: rotate the start host so successive
        // refreshes do not always hit the same provider first.
        let start = Int(now.timeIntervalSince1970 / 900) % targets.count
        var rtts: [Double] = []
        var attempted = 0
        var failures = 0
        var abortedDead = false

        for i in 0..<probeCount {
            attempted += 1
            if let rtt = await probe(targets[(start + i) % targets.count], session: session) {
                rtts.append(rtt)
            } else {
                failures += 1
                // Same early exit as MeasurementEngine: two dead probes with
                // nothing answering is already the answer.
                if failures >= 2 && rtts.isEmpty {
                    abortedDead = true
                    break
                }
            }
            if i < probeCount - 1 { try? await Task.sleep(for: interProbeGap) }
        }

        let lossRatio = abortedDead ? 1.0 : Double(failures) / Double(max(attempted, 1))
        let median = WidgetScoring.median(rtts)
        let jitter = WidgetScoring.meanAbsoluteDeviation(rtts, median: median)
        let composite = WidgetScoring.composite(lossRatio: lossRatio, latencyMs: median, jitterMs: jitter)
        let bars = WidgetScoring.bars(composite: composite, lossRatio: lossRatio, latencyMs: median)
        return WidgetReading(date: now, network: network, bars: bars, latencyMs: median, lossRatio: lossRatio)
    }

    private static var sessionConfiguration: URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 2
        config.timeoutIntervalForResource = 2
        return config
    }

    /// Round-trip time in ms, or nil when the probe counts as lost. Mirrors
    /// HttpProbeClient.probe: any response below 500 proves the path works
    /// (a captive portal's redirect included); timeouts and errors are loss.
    private static func probe(_ url: URL, session: URLSession) async -> Double? {
        var request = URLRequest(url: cacheBusted(url))
        request.setValue("no-cache, no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")

        let clock = ContinuousClock()
        let started = clock.now
        let status: Int? = await withTaskGroup(of: Int?.self) { group in
            group.addTask {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    var received = 0
                    for try await _ in bytes {
                        received += 1
                        if received > maxProbeResponseBytes { return nil }
                    }
                    return (response as? HTTPURLResponse)?.statusCode
                } catch {
                    return nil
                }
            }
            group.addTask {
                try? await Task.sleep(for: probeTimeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let status, status < 500 else { return nil }
        let elapsed = started.duration(to: clock.now).components
        return Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15
    }

    /// HttpProbeClient._cacheBust: a cached 204 would report a 2 ms round trip
    /// on a dead connection.
    private static func cacheBusted(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        let stamp = String(UInt64(Date().timeIntervalSince1970 * 1_000_000), radix: 36)
        components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "_ts", value: stamp)]
        return components.url!
    }

    /// The current path from NWPathMonitor, or `.none` when unsatisfied. Gives
    /// up after a second and lets the probes decide.
    private static func currentNetwork() async -> WidgetReading.Network {
        let monitor = NWPathMonitor()
        defer { monitor.cancel() }
        return await withCheckedContinuation { continuation in
            let queue = DispatchQueue(label: "com.froggyeye.honestsignal.widget.path")
            let resumed = OSAllocatedUnfairLock(initialState: false)
            @Sendable func finish(_ value: WidgetReading.Network) {
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            monitor.pathUpdateHandler = { path in
                guard path.status == .satisfied else { return finish(.none) }
                if path.usesInterfaceType(.wifi) { return finish(.wifi) }
                if path.usesInterfaceType(.cellular) { return finish(.cellular) }
                if path.usesInterfaceType(.wiredEthernet) { return finish(.ethernet) }
                finish(.other)
            }
            monitor.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 1) { finish(.other) }
        }
    }
}
