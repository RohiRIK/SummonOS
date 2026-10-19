import AppKit
import SummonCore
import SwiftUI

/// The menu bar panel: the app's job (summon the agent, recent problems, theme). Preferences live in Settings.
public struct PanelView: View {
    let model: SummonModel
    let activity: ActivityModel
    let openLauncher: () -> Void
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    public init(model: SummonModel, activity: ActivityModel, openLauncher: @escaping () -> Void) {
        self.model = model
        self.activity = activity
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
            MenuRow(title: "Open Summon Menu", systemImage: "command", shortcut: "⌃⌥Space") {
                openLauncher()
            }
            MenuRow(title: "Activity…", systemImage: "list.bullet.rectangle", shortcut: nil) {
                showActivity(selecting: nil)
            }

            // Problems only when present; history lives in the Activity window, theme in Settings.
            if !model.panelProblems.isEmpty {
                PanelDivider()
                HStack {
                    SectionHeader(title: "Recent Problems")
                    Spacer()
                    Button("Clear") { model.archiveProblems(model.panelProblems) }
                        .buttonStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                        .help("Archive these; they stay in Activity")
                }
                ForEach(latestPerProgram.prefix(3), id: \.report.id) { item in
                    CrashRow(report: item.report, count: item.count, diagnose: { model.diagnose(file: item.report.file) })
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
        .frame(width: 300)
        .containerBackground(.ultraThinMaterial, for: .window)
        .task {
            if activity.live { await activity.refresh() }
        }
    }

    private func showActivity(selecting id: ActivityEvent.ID?) {
        activity.selection = id
        NSApp.activate()
        openWindow(id: ActivityOpener.windowID)
    }

    /// One row per program (newest report first), so a crash loop does not fill the panel.
    private var latestPerProgram: [(report: CrashReport, count: Int)] {
        let problems = model.panelProblems
        let counts = Dictionary(grouping: problems, by: \.program).mapValues(\.count)
        var seen = Set<String>()
        return problems
            .filter { seen.insert($0.program).inserted }
            .map { ($0, counts[$0.program] ?? 1) }
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
        guard model.agentInstalled else { return "\(agent.name) is not installed" }
        if let since = activity.status?.agent.since, activity.status?.agent.running == true {
            return "\(agent.name) · running since \(since.formatted(date: .omitted, time: .shortened))"
        }
        return agent.name
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
    let count: Int
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
        // The whole row diagnoses, not only the button: the row is the problem.
        .contentShape(Rectangle())
        .onTapGesture(perform: diagnose)
        .accessibilityAddTraits(.isButton)
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
        case .memory: return "memorychip"
        case .other: return "doc.text"
        }
    }

    private var detail: String {
        let what = report.kind == .memory ? (report.process == nil ? "Ran low" : "Stopped") : report.kind.rawValue.capitalized
        let parts: [String?] = [what, report.signal ?? report.exceptionType, count > 1 ? "\(count) times" : nil]
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
    let activity = ActivityModel.preview()
    return PanelView(model: activity.summon, activity: activity, openLauncher: {})
}
