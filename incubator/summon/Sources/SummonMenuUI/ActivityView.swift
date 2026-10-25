import AppKit
import SummonCore
import SwiftUI

/// The Activity window: a plain log of what happened on this Mac, oldest at the top like a terminal, and a bar
/// to ask the agent (about the selected lines, if any). Everything else is on right-click.
public struct ActivityView: View {
    @Bindable var model: ActivityModel
    @State private var prompt = ""
    @State private var selected: Set<ActivityEvent.ID> = []
    @State private var pendingUndo: PendingUndo?
    @FocusState private var promptFocused: Bool

    public init(model: ActivityModel) {
        self.model = model
    }

    public var body: some View {
        log
            .searchable(text: $model.query, placement: .toolbar, prompt: "Search")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $model.filter) {
                        ForEach(ActivityModel.Filter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 380)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { askBar }
            .containerBackground(.thinMaterial, for: .window)
            .frame(minWidth: 640, minHeight: 420)
            .confirmationDialog(pendingUndo?.title ?? "", isPresented: undoBinding, presenting: pendingUndo) { undo in
                Button("Undo", role: .destructive) { undo.run(model) }
            } message: { undo in
                Text(undo.message)
            }
            .onAppear {
                if let id = model.selection { selected = [id] }
                guard model.live else { return }
                // An accessory app's window gets no Dock icon or ⌘Tab; become a regular app while it is open.
                NSApp.setActivationPolicy(.regular)
                NSApp.activate()
                model.startAutoRefresh()
            }
            .onDisappear {
                guard model.live else { return }
                model.stopAutoRefresh()
                NSApp.setActivationPolicy(.accessory)
            }
            .onChange(of: model.selection) { _, newValue in
                // The panel can open the window on one event.
                if let newValue { selected = [newValue] }
            }
    }

    // MARK: Log

    /// Oldest first, like a terminal; checkpoint lines are folded into the agent start they belong to.
    private var lines: [ActivityEvent] {
        model.visibleEvents.filter(ActivityLog.isShown).sorted { $0.date < $1.date }
    }

    private var log: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                if let error = model.lastError {
                    Text(verbatim: error).foregroundStyle(.red)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, event in
                    if index == 0 || !Calendar.current.isDate(event.date, inSameDayAs: lines[index - 1].date) {
                        Text(verbatim: Self.dayTitle(event.date))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, index == 0 ? 0 : 8)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                    }
                    LogLine(event: event)
                        .tag(event.id)
                        .id(event.id)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .defaultScrollAnchor(.bottom)
            .contextMenu(forSelectionType: ActivityEvent.ID.self) { ids in
                menu(for: ids)
            }
            .onCopyCommand {
                [NSItemProvider(object: ActivityLog.transcript(events(selected)) as NSString)]
            }
            .overlay {
                if lines.isEmpty {
                    ContentUnavailableView(
                        model.query.isEmpty ? "Nothing Yet" : "No Matches",
                        systemImage: model.query.isEmpty ? "text.alignleft" : "magnifyingglass",
                        description: Text(model.query.isEmpty
                            ? "What the agent, your settings and crashes do shows up here."
                            : "Nothing matches \u{201C}\(model.query)\u{201D}.")
                    )
                }
            }
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: lines.last?.id) { _, _ in scrollToEnd(proxy) }
        }
    }

    @ViewBuilder private func menu(for ids: Set<ActivityEvent.ID>) -> some View {
        Button(ids.count > 1 ? "Ask Agent About \(ids.count) Lines…" : "Ask Agent About This…") {
            selected = ids
            promptFocused = true
        }
        .disabled(!canRun)
        Button("Copy") { copy(ids) }
        if ids.count == 1, let event = events(ids).first {
            if let file = event.refs["file"] {
                Divider()
                Button("Diagnose…") { model.summon.diagnose(file: file) }.disabled(!canRun)
                Button("Show in Finder") { model.reveal(file) }
            }
            if let snapshot = event.refs["snapshot"], event.refs["undoes"] == nil {
                Divider()
                Button("Undo This Change…") { pendingUndo = .snapshot(snapshot) }
                    .disabled(model.busy || model.macctlPath == nil)
            } else if let checkpoint = event.refs["checkpoint"], event.kind != EventKind.sessionUndo {
                Divider()
                Button("Undo This Session…") { pendingUndo = .checkpoint(checkpoint) }
                    .disabled(model.busy)
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = lines.last?.id else { return }
        proxy.scrollTo(last, anchor: .bottom)
    }

    private func events(_ ids: Set<ActivityEvent.ID>) -> [ActivityEvent] {
        model.events.filter { ids.contains($0.id) }
    }

    private func copy(_ ids: Set<ActivityEvent.ID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ActivityLog.transcript(events(ids)), forType: .string)
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: Ask bar

    private var askBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                TextField(promptPlaceholder, text: $prompt)
                    .textFieldStyle(.plain)
                    .focused($promptFocused)
                    .onSubmit(run)
                Button(selected.isEmpty ? "Ask" : "Ask About \(selected.count) Line\(selected.count == 1 ? "" : "s")", action: run)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!canRun)
                    .help(canRun ? "Opens the agent in a new terminal" : agentProblem)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.ultraThinMaterial)
    }

    private var canRun: Bool {
        model.summon.defaultAgent != nil && model.summon.agentInstalled
    }

    private var promptPlaceholder: String {
        guard let agent = model.summon.defaultAgent else { return "Choose an agent in Settings to ask it here" }
        return selected.isEmpty ? "Ask \(agent.name)…" : "What should \(agent.name) look at? (empty: explain and fix)"
    }

    private var agentProblem: String {
        guard let agent = model.summon.defaultAgent else { return "No default agent: choose one in Settings" }
        return "\(agent.name) is not installed: \(agent.installHint)"
    }

    private func run() {
        guard canRun else { return }
        if selected.isEmpty {
            model.runAgent(prompt: prompt)
        } else {
            model.runAgent(prompt: ActivityLog.askPrompt(question: prompt, events: events(selected)))
            selected = []
        }
        prompt = ""
    }

    // MARK: Undo

    private var undoBinding: Binding<Bool> {
        Binding(get: { pendingUndo != nil }, set: { if !$0 { pendingUndo = nil } })
    }

    enum PendingUndo {
        case snapshot(String)
        case checkpoint(String)

        var title: String {
            switch self {
            case .snapshot: return "Undo this change?"
            case .checkpoint: return "Undo this agent session?"
            }
        }

        var message: String {
            switch self {
            case .snapshot: return "The settings go back to the values they had before."
            case .checkpoint: return "Every macOS setting changed since the session started goes back. Files in ~/.config come back only when it is a git repo."
            }
        }

        @MainActor func run(_ model: ActivityModel) {
            switch self {
            case .snapshot(let id): model.undo(snapshot: id)
            case .checkpoint(let id): model.undo(checkpoint: id)
            }
        }
    }
}

/// Structured two-line activity row with native SF Symbol indicators (NO EMOJIS), clear time column, and contextual diffs.
struct LogLine: View {
    let event: ActivityEvent

    private var iconName: String {
        switch event.category {
        case .problem:
            return event.kind == "hang" ? "hourglass.badge.exclamationmark" : "exclamationmark.triangle.fill"
        case .agent:
            return "sparkles"
        case .settings:
            return event.kind.contains("undo") ? "arrow.uturn.backward.circle.fill" : "slider.horizontal.3"
        case .checkpoint:
            return "clock.arrow.circlepath"
        case .theme:
            return "paintbrush.pointed.fill"
        case .mac:
            return "desktopcomputer"
        }
    }

    private var iconColor: Color {
        switch event.category {
        case .problem:
            return event.kind == "hang" ? .orange : .red
        case .agent:
            return .accentColor
        case .settings:
            return event.kind.contains("undo") ? .green : .cyan
        case .checkpoint:
            return .indigo
        case .theme:
            return .purple
        case .mac:
            return .teal
        }
    }

    private var detailText: String? {
        if !event.changes.isEmpty {
            return event.changes.map { change in
                let from = ActivityLog.short(change.from ?? "unset")
                let to = ActivityLog.short(change.to)
                return "\(change.id): \(from) → \(to)"
            }.joined(separator: ", ")
        }
        if let detail = event.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
            return detail.components(separatedBy: .newlines).first
        }
        return nil
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Timestamp column
            Text(event.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 38, alignment: .leading)
                .padding(.top, 2)

            // Native Apple SF Symbol icon
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 20, height: 20)
                .background(Circle().fill(iconColor.opacity(0.12)))
                .padding(.top, 1)

            // Title + Detail
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: ActivityLog.clean(event.title))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(event.category == .problem ? (event.kind == "hang" ? .orange : .red) : .primary)
                    .lineLimit(1)

                if let detail = detailText {
                    Text(verbatim: detail)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            // Category tag
            Text(event.category.rawValue.capitalized)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.04), in: Capsule())
                .padding(.top, 2)
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .help(ActivityLog.line(event))
    }
}

#Preview("Activity") {
    ActivityView(model: .preview())
        .frame(width: 760, height: 520)
}
