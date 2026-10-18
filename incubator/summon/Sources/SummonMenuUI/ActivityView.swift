import AppKit
import SummonCore
import SwiftUI

/// The Activity window as a log (Console.app layout): one line per event, oldest at the top, following new
/// lines like `tail -f`; the selected line's details and actions (or the status overview) in the drawer below;
/// a bar to ask the agent, with the selected lines attached.
public struct ActivityView: View {
    @Bindable var model: ActivityModel
    @State private var prompt = ""
    @State private var selected: Set<ActivityEvent.ID> = []
    @State private var follow = true
    @FocusState private var promptFocused: Bool

    public init(model: ActivityModel) {
        self.model = model
    }

    public var body: some View {
        VSplitView {
            logPane
                .frame(minHeight: 220)
            drawer
                .frame(minHeight: 140, idealHeight: 230)
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Filter")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Picker("Show", selection: $model.filter) {
                    ForEach(ActivityModel.Filter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Toggle(isOn: $follow) {
                    Label("Follow", systemImage: "arrow.down.to.line")
                }
                .help("Keep the newest line in view")
                Button {
                    copy(selected.isEmpty ? Set(model.visibleEvents.map(\.id)) : selected)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .help(selected.isEmpty ? "Copy every visible line" : "Copy the selected lines (⌘C)")
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            runBar
        }
        .frame(minWidth: 760, minHeight: 480)
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
        .onChange(of: selected) { _, newValue in
            model.selection = newValue.count == 1 ? newValue.first : nil
        }
        .onChange(of: model.selection) { _, newValue in
            // The panel can open the window on one event.
            if let newValue, !selected.contains(newValue) {
                selected = [newValue]
                follow = false
            }
        }
    }

    // MARK: Log

    /// Oldest first, like a terminal.
    private var lines: [ActivityEvent] {
        model.visibleEvents.sorted { $0.date < $1.date }
    }

    private var logPane: some View {
        ScrollViewReader { proxy in
            List(selection: $selected) {
                if let error = model.lastError {
                    Text(verbatim: "ERROR  \(error)")
                        .foregroundStyle(.red)
                }
                ForEach(Array(lines.enumerated()), id: \.element.id) { index, event in
                    if index == 0 || !Calendar.current.isDate(event.date, inSameDayAs: lines[index - 1].date) {
                        DaySeparator(day: event.date)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                    }
                    LogLine(event: event)
                        .tag(event.id)
                        .id(event.id)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 18)
            .contextMenu(forSelectionType: ActivityEvent.ID.self) { ids in
                Button("Ask Agent About \(ids.count == 1 ? "This Line" : "\(ids.count) Lines")…") {
                    selected = ids
                    promptFocused = true
                }
                .disabled(!canRun)
                Button("Copy") { copy(ids) }
            }
            .onCopyCommand {
                [NSItemProvider(object: ActivityLog.transcript(events(for: selected)) as NSString)]
            }
            .overlay {
                if lines.isEmpty {
                    ContentUnavailableView(
                        model.query.isEmpty ? "No Activity Yet" : "No Matches",
                        systemImage: model.query.isEmpty ? "terminal" : "magnifyingglass",
                        description: Text(model.query.isEmpty
                            ? "Settings changes, checkpoints, agent sessions and crashes show up here."
                            : "Nothing matches \u{201C}\(model.query)\u{201D}.")
                    )
                }
            }
            .onAppear { scrollToEnd(proxy) }
            .onChange(of: lines.last?.id) { _, _ in
                if follow { scrollToEnd(proxy) }
            }
            .onChange(of: follow) { _, newValue in
                if newValue { scrollToEnd(proxy) }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        guard let last = lines.last?.id else { return }
        proxy.scrollTo(last, anchor: .bottom)
    }

    private func events(for ids: Set<ActivityEvent.ID>) -> [ActivityEvent] {
        model.events.filter { ids.contains($0.id) }
    }

    private func copy(_ ids: Set<ActivityEvent.ID>) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ActivityLog.transcript(events(for: ids)), forType: .string)
    }

    // MARK: Drawer

    @ViewBuilder private var drawer: some View {
        if let event = model.selectedEvent {
            EventDetailView(model: model, event: event)
        } else {
            OverviewView(model: model)
        }
    }

    // MARK: Run bar

    private var runBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.tint)
                if !selected.isEmpty {
                    Button {
                        selected = []
                    } label: {
                        Label("\(selected.count) line\(selected.count == 1 ? "" : "s")", systemImage: "xmark.circle.fill")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("These lines go to the agent with your question. Click to detach them.")
                }
                TextField(promptPlaceholder, text: $prompt)
                    .textFieldStyle(.plain)
                    .focused($promptFocused)
                    .onSubmit(run)
                Button(action: run) {
                    Label(selected.isEmpty ? "Run" : "Ask", systemImage: "return")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!canRun)
                .help(canRun ? "Start the agent in a new terminal (a checkpoint is taken first)" : agentProblem)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(.bar)
    }

    private var canRun: Bool {
        model.summon.defaultAgent != nil && model.summon.agentInstalled
    }

    private var promptPlaceholder: String {
        guard let agent = model.summon.defaultAgent else { return "Choose a default agent in Settings to run it here" }
        if !selected.isEmpty { return "Ask \(agent.name) about the selected lines… (empty: explain and fix)" }
        return "Ask \(agent.name)… (select lines to ask about them)"
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
            model.runAgent(prompt: ActivityLog.askPrompt(question: prompt, events: events(for: selected)))
        }
        prompt = ""
    }
}

// MARK: - Lines

/// `14:02:31  INFO   agent       Started Claude Code  folder=~/Work`: level coloured, everything else quiet.
struct LogLine: View {
    let event: ActivityEvent

    var body: some View {
        let level = ActivityLog.level(event)
        HStack(spacing: 14) {
            Text(event.date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits)))
                .foregroundStyle(.tertiary)
                .fixedSize()
                .help(event.date.formatted(date: .complete, time: .standard))
            Text(verbatim: level.rawValue)
                .fontWeight(.semibold)
                .foregroundStyle(Self.color(level))
                .fixedSize()
                .frame(width: 40, alignment: .leading)
            Text(verbatim: ActivityLog.source(event))
                .foregroundStyle(.secondary)
                .fixedSize()
                .frame(width: 76, alignment: .leading)
            Text(verbatim: ActivityLog.message(event))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
            Text(verbatim: ActivityLog.fields(event))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11.5, design: .monospaced))
        .lineLimit(1)
    }

    static func color(_ level: ActivityLog.Level) -> Color {
        switch level {
        case .info: return .secondary
        case .warn: return .orange
        case .error: return .red
        }
    }
}

/// `── Today ──` between days, the way `journalctl` marks a reboot.
struct DaySeparator: View {
    let day: Date

    var body: some View {
        HStack(spacing: 8) {
            line
            Text(verbatim: Self.title(day))
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(.tertiary)
                .fixedSize()
            line
        }
        .padding(.vertical, 2)
    }

    private var line: some View {
        Rectangle().fill(.quaternary).frame(height: 1)
    }

    static func title(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

enum EventStyle {
    static func symbol(_ event: ActivityEvent) -> String {
        switch event.category {
        case .settings: return event.kind == "setting.undo" ? "arrow.uturn.backward.circle" : "slider.horizontal.3"
        case .theme: return "paintpalette"
        case .agent:
            switch event.kind {
            case EventKind.sessionEnd: return "stop.circle"
            case EventKind.sessionStart: return "play.circle"
            default: return "sparkles"
            }
        case .checkpoint: return event.kind == EventKind.sessionUndo ? "arrow.uturn.backward.circle" : "clock.arrow.circlepath"
        case .problem: return event.kind == "hang" ? "hourglass" : "exclamationmark.triangle"
        }
    }

    static func tint(_ event: ActivityEvent) -> Color {
        switch event.category {
        case .settings, .theme: return .accentColor
        case .agent: return .purple
        case .checkpoint: return .teal
        case .problem: return .orange
        }
    }
}

// MARK: - Overview (nothing selected)

struct OverviewView: View {
    let model: ActivityModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Status").font(.title2.weight(.semibold))
                if let status = model.status {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 12) {
                        StatusLine(symbol: "sparkles", title: "Agent", value: agentText(status),
                                   state: status.agent.running ? .active : (status.agent.installed ? .ok : .warning))
                        StatusLine(symbol: "slider.horizontal.3", title: "macctl", value: macctlText(status),
                                   state: status.macctl.installed && status.macctl.problems.isEmpty ? .ok : .warning)
                        StatusLine(symbol: "clock.badge.checkmark", title: "Last change", value: lastChangeText(status), state: .neutral)
                        StatusLine(symbol: "clock.arrow.circlepath", title: "Checkpoint", value: checkpointText(status),
                                   state: status.configIsRepo ? .ok : .warning)
                        StatusLine(symbol: "exclamationmark.triangle", title: "Problems",
                                   value: status.recentProblems == 0 ? "None in the last day" : "\(status.recentProblems) in the last day",
                                   state: status.recentProblems == 0 ? .ok : .warning)
                    }
                    if !status.warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Needs attention").font(.headline)
                            ForEach(status.warnings, id: \.self) { warning in
                                Label(warning, systemImage: "exclamationmark.circle")
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                    if let change = status.lastChange, let snapshot = change.refs["snapshot"] {
                        HStack {
                            UndoSnapshotButton(model: model, snapshotID: snapshot, title: "Undo Last Change")
                            Button("Show Change") { model.selection = change.id }
                        }
                    }
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func agentText(_ status: SummonStatus) -> String {
        guard let name = status.agent.name else { return "None chosen (Settings)" }
        guard status.agent.installed else { return "\(name), not installed" }
        guard status.agent.running, let since = status.agent.since else { return "\(name), idle" }
        let folder = status.agent.folder.map { " in \($0)" } ?? ""
        return "\(name), running since \(since.formatted(date: .omitted, time: .shortened))\(folder)"
    }

    private func macctlText(_ status: SummonStatus) -> String {
        guard status.macctl.installed else { return "Not installed: settings changes are not recorded" }
        return status.macctl.problems.isEmpty ? "Ready" : status.macctl.problems.joined(separator: "; ")
    }

    private func lastChangeText(_ status: SummonStatus) -> String {
        guard let change = status.lastChange else { return "None yet" }
        return "\(change.title), \(change.date.formatted(.relative(presentation: .named)))"
    }

    private func checkpointText(_ status: SummonStatus) -> String {
        guard let checkpoint = status.lastCheckpoint else { return "None yet: one is taken when the agent starts" }
        return "\(ActivityLog.clean(checkpoint.label)), \(checkpoint.createdAt.formatted(.relative(presentation: .named)))"
    }
}

struct StatusLine: View {
    enum Tone { case ok, active, warning, neutral }

    let symbol: String
    let title: String
    let value: String
    let state: Tone

    var body: some View {
        GridRow(alignment: .firstTextBaseline) {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Circle().fill(dotColor).frame(width: 7, height: 7)
                Text(value).textSelection(.enabled)
            }
        }
    }

    private var dotColor: Color {
        switch state {
        case .ok: return .green
        case .active: return .accentColor
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }
}

// MARK: - Detail

struct EventDetailView: View {
    let model: ActivityModel
    let event: ActivityEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: EventStyle.symbol(event))
                        .font(.title2)
                        .foregroundStyle(EventStyle.tint(event))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text(event.date.formatted(date: .complete, time: .standard))
                            .foregroundStyle(.secondary)
                    }
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var content: some View {
        switch event.category {
        case .settings:
            settings
        case .checkpoint:
            checkpoint
        case .problem:
            problem
        case .agent, .theme:
            plain
        }
    }

    @ViewBuilder private var settings: some View {
        ChangesTable(changes: event.changes)
        if let undone = event.refs["undoes"] {
            Text("This undid snapshot \(undone).").foregroundStyle(.secondary)
        } else if let snapshot = event.refs["snapshot"] {
            let overlaps = model.laterOverlaps(snapshot)
            if !overlaps.isEmpty {
                Label("Later changes touch the same settings (\(overlaps.map(\.id).joined(separator: ", "))). Undo puts back the values from before this change and overwrites them.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            UndoSnapshotButton(model: model, snapshotID: snapshot, title: "Undo This Change")
            Text("Snapshot \(snapshot)").font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    @ViewBuilder private var checkpoint: some View {
        if let detail = event.detail { Text(detail).foregroundStyle(.secondary) }
        if event.kind == "checkpoint", let id = event.refs["checkpoint"] {
            let changed = model.changes(after: id)
            Text(changed.isEmpty ? "No settings changed after this checkpoint." : "Settings changed after this checkpoint")
                .font(.headline)
            ForEach(changed, id: \.id) { snapshot in
                ChangesTable(changes: snapshot.changes)
            }
            UndoCheckpointButton(model: model, checkpointID: id)
            Text("Checkpoint \(id)").font(.caption).foregroundStyle(.tertiary).textSelection(.enabled)
        }
    }

    @ViewBuilder private var problem: some View {
        if let detail = event.detail { Text(detail).font(.body.monospaced()).textSelection(.enabled) }
        if let file = event.refs["file"] {
            if let report = model.sources.crashes.first(where: { $0.file == file }), !report.topFrames.isEmpty {
                Text("Top frames").font(.headline)
                Text(report.topFrames.prefix(8).joined(separator: "\n"))
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
            }
            HStack {
                Button("Diagnose…") { model.summon.diagnose(file: file) }
                    .disabled(model.summon.defaultAgent == nil || !model.summon.agentInstalled)
                Button("Show in Finder") { model.reveal(file) }
                if let report = model.sources.crashes.first(where: { $0.file == file }) {
                    Button("Mute \(report.program)") { model.summon.mute(program: report.program) }
                }
            }
        }
    }

    @ViewBuilder private var plain: some View {
        if let detail = event.detail {
            Text(detail).textSelection(.enabled)
        }
        let keys = event.refs.keys.sorted()
        if !keys.isEmpty {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(keys, id: \.self) { key in
                    GridRow {
                        Text(key.capitalized).foregroundStyle(.secondary)
                        Text(event.refs[key] ?? "").textSelection(.enabled)
                    }
                }
            }
        }
        if let id = event.refs["checkpoint"] {
            UndoCheckpointButton(model: model, checkpointID: id)
        }
    }
}

struct ChangesTable: View {
    let changes: [SettingChange]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("Setting")
                Text("Before")
                Text("After")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(changes, id: \.id) { change in
                GridRow {
                    Text(change.id).font(.body.monospaced())
                    Text(change.from ?? "unset").foregroundStyle(.secondary)
                    Text(change.to)
                }
                .textSelection(.enabled)
            }
        }
    }
}

struct UndoSnapshotButton: View {
    let model: ActivityModel
    let snapshotID: String
    let title: String
    @State private var confirming = false

    var body: some View {
        Button(title) { confirming = true }
            .disabled(model.busy || model.macctlPath == nil)
            .confirmationDialog("Undo snapshot \(snapshotID)?", isPresented: $confirming) {
                Button("Undo", role: .destructive) { model.undo(snapshot: snapshotID) }
            } message: {
                Text("macctl puts back the values these settings had before, and records the undo as a new snapshot.")
            }
    }
}

struct UndoCheckpointButton: View {
    let model: ActivityModel
    let checkpointID: String
    @State private var confirming = false

    var body: some View {
        Button("Undo Everything Since This Checkpoint") { confirming = true }
            .disabled(model.busy)
            .confirmationDialog("Go back to checkpoint \(checkpointID)?", isPresented: $confirming) {
                Button("Undo Session", role: .destructive) { model.undo(checkpoint: checkpointID) }
            } message: {
                Text("Every macOS setting changed since then goes back. Files in ~/.config come back only when it is a git repo; files created since stay.")
            }
    }
}

#Preview("Activity: overview") {
    ActivityView(model: .preview())
        .frame(width: 900, height: 600)
}

#Preview("Activity: profile change") {
    ActivityView(model: .preview(selecting: 1))
        .frame(width: 900, height: 600)
}
