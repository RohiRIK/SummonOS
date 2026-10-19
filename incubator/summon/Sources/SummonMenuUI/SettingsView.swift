import ServiceManagement
import SummonCore
import SwiftUI

/// The Settings window (⌘,): one toolbar tab per section (the macOS app-settings layout), one grouped form each.
/// Every app preference lives here, never in the menu bar panel.
public struct SettingsView: View {
    @Bindable var model: SummonModel

    static let sections = SettingsSection.allCases

    public init(model: SummonModel) {
        self.model = model
    }

    public var body: some View {
        TabView {
            ForEach(Self.sections) { section in
                SettingsSectionView(section: section, model: model)
                    .tabItem { Label(section.title, systemImage: section.systemImage) }
            }
        }
        .frame(width: 580)
        .task { await model.loadShippedSkills() }
    }
}

/// One section's rows. Split out so each section has its own preview.
struct SettingsSectionView: View {
    let section: SettingsSection
    @Bindable var model: SummonModel

    var body: some View {
        // Short tabs fit their rows; Agents (a row per skill) gets room and scrolls.
        if section == .agents {
            content.frame(height: 520)
        } else {
            content.fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
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
                            // The router is how "summon, <anything>" reaches the other skills: always on.
                            .disabled(skill == "summon")
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

/// Recurring agent tasks, view only: what runs, when, with which agent, and how the last run went.
/// Tasks are made by describing them to the agent (`summon task new`, or "summon, every morning…").
struct TasksSettings: View {
    let model: SummonModel

    var body: some View {
        Form {
            Section {
                if model.tasks.isEmpty {
                    Text("No tasks yet.").foregroundStyle(.secondary)
                }
                ForEach(model.tasks) { task in
                    LabeledContent {
                        if let result = model.taskResults[task.id] {
                            Text(result == "failed" ? "Last run failed" : "Last run done")
                                .foregroundStyle(result == "failed" ? .red : .secondary)
                        }
                    } label: {
                        Text(verbatim: task.name)
                        Text(verbatim: "\(task.schedule.summary) · \(task.agent.flatMap { AgentRegistry.find($0)?.name } ?? "Default agent")")
                    }
                    .help(task.prompt)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: Previews

#Preview("Settings") {
    SettingsView(model: .preview())
}

#Preview("General") {
    SettingsSectionView(section: .general, model: .preview())
        .frame(width: 580)
}

#Preview("Agents") {
    SettingsSectionView(section: .agents, model: .preview())
        .frame(width: 580)
}

#Preview("Terminal") {
    SettingsSectionView(section: .terminal, model: .preview())
        .frame(width: 580)
}

#Preview("Notifications") {
    SettingsSectionView(section: .notifications, model: .preview())
        .frame(width: 580)
}

#Preview("Appearance") {
    SettingsSectionView(section: .appearance, model: .preview())
        .frame(width: 580)
}

#Preview("Tasks") {
    SettingsSectionView(section: .tasks, model: .preview())
        .frame(width: 580)
}
