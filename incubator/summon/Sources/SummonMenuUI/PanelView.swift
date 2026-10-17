import AppKit
import SummonCore
import SwiftUI

/// The menu bar panel: the app's job (summon the agent, recent problems, theme). Preferences live in Settings.
public struct PanelView: View {
    let model: SummonModel
    let openLauncher: () -> Void
    @Environment(\.openSettings) private var openSettings

    public init(model: SummonModel, openLauncher: @escaping () -> Void) {
        self.model = model
        self.openLauncher = openLauncher
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if let error = model.lastError {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .padding(.horizontal, 8)
            }
            PanelDivider()
            MenuRow(title: "Ask Agent", systemImage: "sparkles", shortcut: "⌃⌥⌘A") {
                model.askAgent()
            }
            .disabled(model.defaultAgent == nil || !model.agentInstalled)
            MenuRow(title: "Open Summon Menu", systemImage: "command", shortcut: "⌥Space") {
                openLauncher()
            }
            MenuRow(title: "Diagnose Last Crash", systemImage: "stethoscope", shortcut: nil) {
                model.diagnoseLatest()
            }
            .disabled(model.recentCrashes.isEmpty || model.defaultAgent == nil)

            PanelDivider()
            SectionHeader(title: "Recent Problems")
            if model.recentCrashes.isEmpty {
                Text("No crashes or hangs reported.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            } else {
                ForEach(model.recentCrashes.prefix(5)) { report in
                    CrashRow(report: report, diagnose: { model.diagnose(file: report.file) })
                }
            }

            if !model.themes.isEmpty {
                PanelDivider()
                SectionHeader(title: "Theme")
                ForEach(model.themes) { theme in
                    MenuRow(
                        title: theme.name,
                        systemImage: theme.slug == model.currentThemeSlug ? "checkmark.circle.fill" : "circle",
                        shortcut: nil
                    ) {
                        model.setTheme(theme.slug)
                    }
                }
            }

            PanelDivider()
            MenuRow(title: "Settings…", systemImage: nil, shortcut: "⌘,") {
                NSApp.activate()
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            MenuRow(title: "Quit Summon", systemImage: nil, shortcut: "⌘Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(6)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text("Summon").font(.headline)
                Text(agentLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var agentLine: String {
        guard let agent = model.defaultAgent else { return "No default agent: choose one in Settings" }
        return model.agentInstalled ? agent.name : "\(agent.name) is not installed"
    }
}

/// A command row styled like a system menu item: hover highlight, trailing key hint in tertiary.
struct MenuRow: View {
    let title: String
    let systemImage: String?
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .frame(width: 16)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                Spacer()
                if let shortcut {
                    Text(shortcut).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 24)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering && isEnabled ? AnyShapeStyle(HierarchicalShapeStyle.quaternary) : AnyShapeStyle(Color.clear))
            )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
    }
}

struct CrashRow: View {
    let report: CrashReport
    let diagnose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 16)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(report.program).lineLimit(1)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Diagnose…", action: diagnose)
                .controlSize(.small)
                .help("Hand this report to your default agent")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? AnyShapeStyle(HierarchicalShapeStyle.quaternary) : AnyShapeStyle(Color.clear))
        )
        .onHover { hovering = $0 }
    }

    private var icon: String {
        switch report.kind {
        case .crash: return "exclamationmark.triangle"
        case .hang: return "hourglass"
        case .panic: return "bolt.trianglebadge.exclamationmark"
        case .other: return "doc.text"
        }
    }

    private var detail: String {
        let parts = [report.kind.rawValue.capitalized, report.signal ?? report.exceptionType, report.timestamp.map { String($0.prefix(16)) }]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 4)
    }
}

struct PanelDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 3)
    }
}

#Preview("Panel") {
    PanelView(model: .preview(), openLauncher: {})
}
