import AppIntents
import StarterCore
import StarterUI
import SwiftUI
import WidgetKit

/// The widget extension's entry point. Add more widgets to the bundle as more kinds.
@main
struct StarterWidgetBundle: WidgetBundle {
    var body: some Widget {
        StarterWidget()
    }
}

/// What the person picks in Edit Widget (the system adds that menu item for an `AppIntentConfiguration`).
struct CountdownIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Countdown" }
    static var description: IntentDescription { "Days to a date you choose." }

    @Parameter(title: "Title", default: "Launch")
    var label: String

    @Parameter(title: "Date")
    var date: Date?
}

struct CountdownEntry: TimelineEntry {
    let date: Date
    let countdown: Countdown?
}

/// Entries at now, the target and each midnight (`Countdown.timelineDates`); `.atEnd` asks for the next batch.
struct CountdownProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, countdown: .sample())
    }

    func snapshot(for configuration: CountdownIntent, in context: Context) async -> CountdownEntry {
        // The widget gallery shows a sample until a date is chosen.
        CountdownEntry(date: .now, countdown: countdown(configuration) ?? .sample())
    }

    func timeline(for configuration: CountdownIntent, in context: Context) async -> Timeline<CountdownEntry> {
        let now = Date.now
        guard let countdown = countdown(configuration) else {
            return Timeline(entries: [CountdownEntry(date: now, countdown: nil)], policy: .never)
        }
        let entries = countdown.timelineDates(from: now).map { CountdownEntry(date: $0, countdown: countdown) }
        return Timeline(entries: entries, policy: .atEnd)
    }

    private func countdown(_ configuration: CountdownIntent) -> Countdown? {
        configuration.date.map { Countdown(title: configuration.label, target: $0) }
    }
}

struct StarterWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: StarterWidgetKind.countdown, intent: CountdownIntent.self, provider: CountdownProvider()) { entry in
            StarterWidgetView(entry: entry)
        }
        .configurationDisplayName("Countdown")
        .description("Days to a date you choose.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StarterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CountdownEntry

    var body: some View {
        CountdownView(countdown: entry.countdown, now: entry.date, family: family)
            // The system draws the widget's background: full color, or tinted by the wallpaper when vibrant.
            .containerBackground(.fill.tertiary, for: .widget)
    }
}

#Preview("Small", as: .systemSmall) {
    StarterWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
    CountdownEntry(date: .now, countdown: nil)
}

#Preview("Medium", as: .systemMedium) {
    StarterWidget()
} timeline: {
    CountdownEntry(date: .now, countdown: .sample())
}
