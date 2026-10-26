import StarterCore
import SwiftUI
import WidgetKit

/// The widget's face, shared by the widget extension and the app's gallery. Glanceable: one bold number, one short
/// label, system fonts never under 10 pt, semantic colors so the desktop's vibrant (tinted) mode reads well.
/// Sizes come from the system: no fixed frames here (WidgetKit: widget sizes vary across devices).
public struct CountdownView: View {
    let countdown: Countdown?
    let now: Date
    let family: WidgetFamily

    public init(countdown: Countdown?, now: Date, family: WidgetFamily) {
        self.countdown = countdown
        self.now = now
        self.family = family
    }

    public var body: some View {
        if let countdown {
            if family == .systemSmall {
                face(countdown)
            } else {
                HStack(alignment: .top, spacing: 16) {
                    face(countdown)
                    Divider()
                    details(countdown)
                }
            }
        } else {
            empty
        }
    }

    private func face(_ countdown: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(countdown.title)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 0)
            value(countdown)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(caption(countdown))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func value(_ countdown: Countdown) -> some View {
        switch countdown.phase(at: now) {
        case let .upcoming(days):
            Text(days, format: .number).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
        case .today:
            // Counts down by itself, with no timeline reloads.
            Text(countdown.target, style: .timer).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
        case let .passed(days):
            if days == 0 {
                Text("Today").font(.system(size: 34, weight: .bold, design: .rounded))
            } else {
                Text(days, format: .number).font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
            }
        }
    }

    private func caption(_ countdown: Countdown) -> String {
        switch countdown.phase(at: now) {
        case let .upcoming(days): days == 1 ? "day left" : "days left"
        case .today: "left today"
        case let .passed(days): days == 0 ? "it's here" : (days == 1 ? "day since" : "days since")
        }
    }

    private func details(_ countdown: Countdown) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(countdown.target, format: .dateTime.weekday(.wide))
                .font(.subheadline.weight(.semibold))
            Text(countdown.target, format: .dateTime.day().month(.wide).year())
                .font(.subheadline)
            Text(countdown.target, format: .dateTime.hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// No date yet: say what to do (HIG Widgets: a clear placeholder, not an error).
    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "calendar.badge.plus")
                .font(.title)
                .foregroundStyle(.secondary)
                .widgetAccentable()
            Text("Choose a date")
                .font(.headline)
            Text("Right-click › Edit Widget")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .lineLimit(2)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension Countdown {
    /// For previews and the app's gallery.
    public static func sample(from now: Date = .now) -> Countdown {
        Countdown(title: "Launch", target: Calendar.current.date(byAdding: .day, value: 12, to: now) ?? now)
    }
}
