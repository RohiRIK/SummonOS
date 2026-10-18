import ServiceManagement
import SummonCore
import SwiftUI

/// The Settings window (⌘,): a sidebar of sections, one grouped form each. Every app preference lives here,
/// never in the menu bar panel.
public struct SettingsView: View {
    @Bindable var model: SummonModel
    @State private var section: SettingsSection? = .initial

    public init(model: SummonModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $section) { item in
                Label(item.title, systemImage: item.systemImage)
                    .tag(item)
            }
            .navigationSplitViewColumnWidth(170)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsSectionView(section: section ?? .initial, model: model)
                .navigationTitle((section ?? .initial).title)
        }
        .frame(width: 640, height: 440)
        .task { await model.loadShippedSkills() }
    }
}

/// One section's rows. Split out so each section has its own preview.
struct SettingsSectionView: View {
    let section: SettingsSection
    @Bindable var model: SummonModel

    var body: some View {
        switch section {
        case .general: GeneralSettings()
        case .agents: AgentsSettings(model: model)
        case .terminal: TerminalSettings(model: model)
        case .notifications: NotificationSettings(model: model)
        case .appearance: AppearanceSettings(model: model)
        case .tasks: TasksSettings(model: model)
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        setOpenAtLogin(newValue)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            } footer: {
                Text("Powered by caffeine and questionable choices.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .formStyle(.grouped)
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = SMAppService.mainApp.status == .requiresApproval
                ? "Allow Summon in System Settings › General › Login Items."
                : nil
        } catch {
            loginError = error.localizedDescription
        }
    }
}

// MARK: Agents

struct AgentsSettings: View {
    @Bindable var model: SummonModel
    /// The agent whose model and skills are shown; starts on the default agent.
    @State private var editing: String = ""
    @State private var modelDraft: String = ""

    /// Agents with something to set: a model option or their own skill folder.
    private var configurable: [Agent] {
        AgentRegistry.all.filter { $0.modelFlag != nil || $0.skillFolder != nil }
    }

    private var editingAgent: Agent? {
        configurable.first { $0.id == editing }
    }

    var body: some View {
        Form {
            Section {
                Picker("Default agent", selection: defaultAgentBinding) {
                    Text("None").tag("")
                    ForEach(AgentRegistry.all, id: \.id) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                if let agent = model.defaultAgent, !model.agentInstalled {
                    LabeledContent("Install") {
                        Text(agent.installHint)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Picker("Agent", selection: $editing) {
                    ForEach(configurable, id: \.id) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                if let agent = editingAgent, agent.modelFlag != nil {
                    TextField("Model", text: $modelDraft, prompt: Text("Default"))
                        .onSubmit { model.setAgentModel(modelDraft, for: agent.id) }
                }
            }

            if let agent = editingAgent, agent.skillFolder != nil, !model.shippedSkills.isEmpty {
                Section("Skills") {
                    ForEach(model.shippedSkills, id: \.self) { skill in
                        Toggle(skill, isOn: skillBinding(skill, agent: agent.id))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if editingAgent == nil {
                let preferred = model.defaultAgent?.id
                editing = configurable.first { $0.id == preferred }?.id ?? configurable.first?.id ?? ""
            }
            modelDraft = model.agentSettings.model(for: editing) ?? ""
        }
        .onChange(of: editing) { _, id in
            modelDraft = model.agentSettings.model(for: id) ?? ""
        }
        .onChange(of: model.agentSettings) { _, settings in
            modelDraft = settings.model(for: editing) ?? ""
        }
    }

    private var defaultAgentBinding: Binding<String> {
        Binding(
            get: { model.defaultAgent?.id ?? "" },
            set: { newValue in
                if !newValue.isEmpty { model.setDefaultAgent(newValue) }
            }
        )
    }

    private func skillBinding(_ skill: String, agent id: String) -> Binding<Bool> {
        Binding(
            get: { model.agentSettings.skills(for: id, shipped: model.shippedSkills).contains(skill) },
            set: { on in model.setAgentSkill(skill, on: on, for: id) }
        )
    }
}

// MARK: Terminal

struct TerminalSettings: View {
    @Bindable var model: SummonModel

    var body: some View {
        Form {
            Picker("Open in", selection: terminalBinding) {
                ForEach(model.installedTerminals, id: \.self) { terminal in
                    Text(terminal.name).tag(terminal)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var terminalBinding: Binding<TerminalApp> {
        Binding(
            get: { model.terminal },
            set: { newValue in model.setTerminal(newValue) }
        )
    }
}

// MARK: Notifications

struct NotificationSettings: View {
    @Bindable var model: SummonModel

    var body: some View {
        Form {
            Section {
                Toggle("Crashes and hangs", isOn: $model.crashCaptureEnabled)
                Toggle("Task results", isOn: $model.taskNotificationsEnabled)
            }
            if !model.mutedPrograms.isEmpty {
                Section("Muted") {
                    ForEach(model.mutedPrograms, id: \.self) { program in
                        LabeledContent {
                            Button("Unmute") { model.unmute(program: program) }
                        } label: {
                            Text(verbatim: program)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Appearance

struct AppearanceSettings: View {
    @Bindable var model: SummonModel

    var body: some View {
        if model.themes.isEmpty {
            ContentUnavailableView("No Themes", systemImage: "paintpalette")
        } else {
            Form {
                Picker("Theme", selection: themeBinding) {
                    ForEach(model.themes) { theme in
                        Text(theme.name).tag(theme.slug)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { model.currentThemeSlug ?? "" },
            set: { newValue in model.setTheme(newValue) }
        )
    }
}

// MARK: Tasks

/// Recurring agent tasks (`summon task`): a prompt the agent runs on a schedule and reports back on.
struct TasksSettings: View {
    @Bindable var model: SummonModel
    @State private var adding = false

    var body: some View {
        Group {
            if let problem = model.tasksError {
                ContentUnavailableView("Tasks Unreadable", systemImage: "exclamationmark.triangle", description: Text(problem))
            } else if model.tasks.isEmpty {
                ContentUnavailableView {
                    Label("No Tasks", systemImage: "clock.arrow.circlepath")
                } description: {
                    Text("A task is a prompt your agent runs on a schedule, like a morning crash summary.")
                } actions: {
                    Button("Add Task…") { adding = true }
                }
            } else {
                Form {
                    Section {
                        ForEach(model.tasks) { task in
                            TaskRow(task: task, model: model)
                        }
                    } footer: {
                        Text("Tasks can look and report but not change your Mac. Results go to Activity.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let error = model.lastError {
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Spacer()
                        Button("Add Task…") { adding = true }
                    }
                }
                .formStyle(.grouped)
            }
        }
        .sheet(isPresented: $adding) {
            TaskEditor(model: model)
        }
    }
}

struct TaskRow: View {
    let task: AgentTask
    @Bindable var model: SummonModel

    var body: some View {
        LabeledContent {
            HStack(spacing: 10) {
                if model.runningTasks.contains(task.id) {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Run Now") { model.runTask(task.id) }
                }
                Toggle("On", isOn: enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Menu {
                    Button("Remove", role: .destructive) { model.removeTask(task.id) }
                } label: {
                    Image(systemName: "ellipsis")
                        .accessibilityLabel("More")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: task.id)
                Text(task.prompt)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(status)
                    .font(.caption)
                    .foregroundStyle(failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            }
        }
    }

    private var enabled: Binding<Bool> {
        Binding(get: { task.enabled }, set: { model.setTask(task.id, enabled: $0) })
    }

    private var lastRun: LoggedEvent? { model.lastTaskRuns[task.id] }

    private var failed: Bool {
        guard let status = lastRun?.refs["status"] else { return false }
        return status != TaskRunStatus.ok.rawValue
    }

    private var status: String {
        let summary = task.schedule.summary
        let schedule = task.enabled ? summary.prefix(1).uppercased() + String(summary.dropFirst()) : "Off"
        guard let lastRun else { return schedule + " · never run" }
        let when = lastRun.time.formatted(.relative(presentation: .named))
        let result = lastRun.refs["status"].flatMap(TaskRunStatus.init(rawValue:)).map(Self.describe) ?? "ran"
        return "\(schedule) · \(result) \(when)"
    }

    static func describe(_ status: TaskRunStatus) -> String {
        switch status {
        case .ok: return "finished"
        case .failed: return "failed"
        case .timeout: return "timed out"
        case .skipped: return "skipped"
        }
    }
}

/// The Add Task sheet: a name, a prompt and a plain repeat choice. Anything finer is `summon task add`.
struct TaskEditor: View {
    @Bindable var model: SummonModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var prompt = ""
    @State private var repeatChoice: TaskRepeat = .weekdays
    @State private var time = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var hours = 6
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text(verbatim: "morning-crashes"))
                Section("Prompt") {
                    TextEditor(text: $prompt)
                        .font(.body)
                        .frame(minHeight: 90)
                        .accessibilityLabel("Prompt")
                }
                Section {
                    Picker("Repeat", selection: $repeatChoice) {
                        ForEach(TaskRepeat.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    if repeatChoice == .hourly {
                        Stepper("Every \(hours) hours", value: $hours, in: 1...24)
                    } else {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                }
                if let error {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            HStack {
                if !name.isEmpty, !AgentTask.isValidID(name) {
                    Text("Use lowercase letters, digits and dashes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || saving)
            }
            .padding(16)
        }
        .frame(width: 460, height: 440)
    }

    private var canSave: Bool {
        AgentTask.isValidID(name) && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let schedule = repeatChoice.schedule(hours: hours, hour: parts.hour ?? 9, minute: parts.minute ?? 0)
        saving = true
        Task {
            let added = await model.addTask(name: name, prompt: prompt, schedule: schedule)
            saving = false
            if added {
                dismiss()
            } else {
                error = model.lastError
            }
        }
    }
}

// MARK: Previews

#Preview("Settings") {
    SettingsView(model: .preview())
}

#Preview("General") {
    SettingsSectionView(section: .general, model: .preview())
        .frame(width: 470, height: 440)
}

#Preview("Agents") {
    SettingsSectionView(section: .agents, model: .preview())
        .frame(width: 470, height: 440)
}

#Preview("Terminal") {
    SettingsSectionView(section: .terminal, model: .preview())
        .frame(width: 470, height: 440)
}

#Preview("Notifications") {
    SettingsSectionView(section: .notifications, model: .preview())
        .frame(width: 470, height: 440)
}

#Preview("Appearance") {
    SettingsSectionView(section: .appearance, model: .preview())
        .frame(width: 470, height: 440)
}

#Preview("Tasks") {
    SettingsSectionView(section: .tasks, model: .preview())
        .frame(width: 470, height: 440)
}

#Preview("Add Task") {
    TaskEditor(model: .preview())
}
