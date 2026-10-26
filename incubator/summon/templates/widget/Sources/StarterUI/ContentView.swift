import StarterCore
import SwiftUI
import WidgetKit

public enum StarterSettings {
    public static let reloadOnLaunchKey = "reloadWidgetsOnLaunch"
}

/// The app's one window: how to add the widget, and what it looks like. The widget is the product; the app is its
/// home (it has to exist to carry the extension) and closes like any small utility.
public struct ContentView: View {
    @State private var reloaded = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Starter Widget").font(.title2.weight(.semibold))
                Text("Days to the date you choose, on your desktop or in Notification Center.")
                    .foregroundStyle(.secondary)
            }

            // Updated every minute so the previews match the widget.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                HStack(alignment: .top, spacing: 16) {
                    tile(.systemSmall, width: 170, now: context.date)
                    tile(.systemMedium, width: 364, now: context.date)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Add it").font(.headline)
                step(1, "Right-click the desktop and choose Edit Widgets…")
                step(2, "Search for Starter and drag the widget onto the desktop.")
                step(3, "Right-click the widget, choose Edit Widget, and pick a date.")
            }

            HStack {
                Spacer()
                if reloaded {
                    Label("Widgets reloaded", systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Button("Reload Widgets", action: reload)
                    .keyboardShortcut("r")
            }
        }
        .padding(24)
        .frame(width: 600)
        .fixedSize()
    }

    private func tile(_ family: WidgetFamily, width: CGFloat, now: Date) -> some View {
        CountdownView(countdown: .sample(from: now), now: now, family: family)
            .padding(16)
            .frame(width: width, height: 170)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.separator))
            .accessibilityElement(children: .combine)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(number, format: .number)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .frame(width: 18, height: 18)
                .background(.tint.opacity(0.2), in: Circle())
            Text(text)
        }
    }

    private func reload() {
        WidgetCenter.shared.reloadTimelines(ofKind: StarterWidgetKind.countdown)
        withAnimation { reloaded = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation { reloaded = false }
        }
    }
}

#Preview("Window") {
    ContentView()
}

#Preview("Empty widget", traits: .fixedLayout(width: 170, height: 170)) {
    CountdownView(countdown: nil, now: .now, family: .systemSmall).padding(16)
}
