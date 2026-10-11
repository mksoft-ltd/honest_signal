import SwiftUI
import WidgetKit

// The widget runs its own quick probe each time WidgetKit asks for a timeline
// (see WidgetProbe). iOS decides the real refresh cadence; the 15-minute
// request is only a hint, so the UI always shows how old the reading is.
//
// Tapping opens the app normally: no widgetURL, so no deep link reaches the
// Flutter router.

@main
struct HonestSignalWidgetBundle: WidgetBundle {
    var body: some Widget {
        HonestSignalWidget()
    }
}

struct HonestSignalWidget: Widget {
    let kind = "HonestSignalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            HonestSignalWidgetView(entry: entry)
        }
        .configurationDisplayName("Honest Signal")
        .description("A quick, honest check of your connection, refreshed through the day.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryCircular, .accessoryRectangular, .accessoryInline,
        ])
    }
}

// MARK: - Timeline

struct ReadingEntry: TimelineEntry {
    let reading: WidgetReading
    var date: Date { reading.date }
}

struct Provider: TimelineProvider {
    static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> ReadingEntry {
        ReadingEntry(reading: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReadingEntry) -> Void) {
        if context.isPreview {
            completion(ReadingEntry(reading: .sample))
            return
        }
        Task { completion(ReadingEntry(reading: await WidgetProbe.measure())) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReadingEntry>) -> Void) {
        Task {
            let reading = await WidgetProbe.measure()
            let next = reading.date.addingTimeInterval(Self.refreshInterval)
            completion(Timeline(entries: [ReadingEntry(reading: reading)], policy: .after(next)))
        }
    }
}

extension WidgetReading {
    /// Gallery and placeholder content; never shown as a real measurement.
    static let sample = WidgetReading(date: Date(), network: .wifi, bars: 4, latencyMs: 48, lossRatio: 0)
}

// MARK: - Colours (lib/core/theme/app_theme.dart, AppColors.light / .dark)

enum ScoreColors {
    static func forBars(_ bars: Int, scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch bars {
        case ...0: return Color(hex: dark ? 0xE0483C : 0xC0271B)
        case 1: return Color(hex: dark ? 0xE8863B : 0xA85A0A)
        case 2, 3: return Color(hex: dark ? 0xD8B22E : 0x8A6B00)
        case 4: return Color(hex: dark ? 0x4FA83D : 0x357A27)
        default: return Color(hex: dark ? 0x1FA97A : 0x0E7A57)
        }
    }

    /// Approximations of the app's Material `surface` for each brightness.
    static func background(scheme: ColorScheme) -> Color {
        Color(hex: scheme == .dark ? 0x0F1511 : 0xF5FBF5)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

// MARK: - Bars (lib/shared/widgets/signal_bars.dart, BarTheme.bars)

struct SignalBarsShape: View {
    let bars: Int
    let active: Color
    var inactive: Color = .primary.opacity(0.14)

    var body: some View {
        GeometryReader { geo in
            let count = 5
            let gap = geo.size.width * 0.055
            let barWidth = (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: barWidth * 0.3, style: .continuous)
                        .fill(i < bars ? active : inactive)
                        .frame(width: barWidth,
                               height: geo.size.height * (0.32 + CGFloat(i) / CGFloat(count - 1) * 0.68))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
        }
        .aspectRatio(1 / 0.82, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel("\(min(max(bars, 0), 5)) out of 5 signal bars")
    }
}

// MARK: - Views

struct HonestSignalWidgetView: View {
    let entry: ReadingEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme

    private var reading: WidgetReading { entry.reading }
    private var accent: Color { ScoreColors.forBars(reading.bars, scheme: scheme) }

    var body: some View {
        switch family {
        case .systemMedium: medium.widgetBackground(ScoreColors.background(scheme: scheme))
        case .accessoryCircular: circular.widgetBackground(.clear)
        case .accessoryRectangular: rectangular.widgetBackground(.clear)
        case .accessoryInline: inline.widgetBackground(.clear)
        default: small.widgetBackground(ScoreColors.background(scheme: scheme))
        }
    }

    /// "Quick check · 4 min ago". The widget's score is latency and loss only,
    /// so it is labelled as a quick check rather than the app's full score.
    private var ageLine: Text {
        Text("Quick check · ") + Text(reading.date, style: .relative) + Text(" ago")
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Honest Signal")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            SignalBarsShape(bars: reading.bars, active: accent)
                .frame(maxWidth: 64, alignment: .leading)
            Spacer(minLength: 0)
            Text(reading.verdict)
                .font(.headline)
                .foregroundStyle(accent)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            ageLine
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(spacing: 16) {
            SignalBarsShape(bars: reading.bars, active: accent)
                .frame(width: 92)
            VStack(alignment: .leading, spacing: 4) {
                Text("Honest Signal")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(reading.verdict)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(detailLine)
                    .font(.subheadline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                ageLine
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailLine: String {
        if reading.network == .none { return "Offline" }
        guard !reading.isOffline, let latency = reading.latencyMs else {
            return "\(reading.network.rawValue) · not responding"
        }
        return "\(reading.network.rawValue) · \(Int(latency.rounded())) ms"
    }

    // Lock screen families render in the system's tint, so the bars carry the
    // score through how many are filled rather than through colour.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            SignalBarsShape(bars: reading.bars, active: .primary, inactive: .primary.opacity(0.25))
                .padding(13)
                .widgetAccentable()
        }
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            SignalBarsShape(bars: reading.bars, active: .primary, inactive: .primary.opacity(0.25))
                .frame(width: 30)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(reading.verdict)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                (Text(reading.date, style: .relative) + Text(" ago"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private var inline: some View {
        Text(reading.isOffline ? "No connection" : "Signal \(reading.bars)/5 · \(reading.verdict)")
    }
}

extension View {
    /// iOS 17 requires a container background; iOS 16 has none, so paint it.
    @ViewBuilder
    func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { color }
        } else {
            padding().background(color)
        }
    }
}

// MARK: - Previews

#if DEBUG
struct HonestSignalWidget_Previews: PreviewProvider {
    static let entries = [
        ReadingEntry(reading: .sample),
        ReadingEntry(reading: WidgetReading(date: Date().addingTimeInterval(-600), network: .cellular,
                                            bars: 2, latencyMs: 640, lossRatio: 0)),
        ReadingEntry(reading: .offline(at: Date().addingTimeInterval(-1800))),
    ]
    static let families: [WidgetFamily] = [
        .systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline,
    ]

    static var previews: some View {
        ForEach(families, id: \.self) { family in
            ForEach(entries.indices, id: \.self) { i in
                HonestSignalWidgetView(entry: entries[i])
                    .previewContext(WidgetPreviewContext(family: family))
                    .previewDisplayName("\(family) \(i)")
            }
        }
    }
}
#endif
