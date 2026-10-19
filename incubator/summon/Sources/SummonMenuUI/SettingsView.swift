import ServiceManagement
import SummonCore
import SwiftUI

/// The Settings window (⌘,): one toolbar tab per section (the macOS app-settings layout), one grouped form each.
/// Every app preference lives here, never in the menu bar panel.
public struct SettingsView: View {
    @Bindable var model: SummonModel

    /// Terminal lives on Agents › All Agents now (where agents open), so it has no tab of its own.
    static let sections = SettingsSection.allCases.filter { $0 != .terminal }

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
            content.frame(width: 780, height: 560)
        } else {
            content.frame(width: 580).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general: GeneralSettings(model: model)
        case .agents: AgentsSettings(model: model)
        case .terminal: AllAgentsDetail(model: model)  // no tab of its own: Agents › All Agents
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

    @State private var cleanPlan: SummonCleaner.Plan?
    @State private var confirmingClean = false
    let model: SummonModel

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
                LabeledContent {
                    Button("Clean Now…") {
                        Task {
                            cleanPlan = await model.cleanPreview()
                            confirmingClean = true
                        }
                    }
                } label: {
                    Text("Keep ~/Summon tidy")
                    Text("Once a day, old task logs and art go to the Trash. Apps are never touched.")
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
        .confirmationDialog(cleanTitle, isPresented: $confirmingClean) {
            if let plan = cleanPlan, !plan.trash.isEmpty {
                Button("Move to Trash") { model.cleanNow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(cleanMessage)
        }
    }

    private var cleanTitle: String {
        guard let count = cleanPlan?.trash.count, count > 0 else { return "~/Summon is tidy" }
        return "Move \(count) item\(count == 1 ? "" : "s") to the Trash?"
    }

    /// The first items and every note (things left as they are, for the user to look at).
    private var cleanMessage: String {
        guard let plan = cleanPlan else { return "Could not read ~/Summon." }
        let items = plan.trash.prefix(6).map { "• \(($0.path as NSString).lastPathComponent): \($0.reason)" }
        let more = plan.trash.count > 6 ? ["…and \(plan.trash.count - 6) more"] : []
        let notes = plan.notes.map { "Note: \($0)" }
        let lines = items + more + notes
        return lines.isEmpty ? "Nothing to clean." : lines.joined(separator: "\n")
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

/// Agents, Hermes-style but lean: the agents on the left (status and Default at a glance), and the same four
/// sections for every agent on the right: Account, Model, Skills, Plugins.
struct AgentsSettings: View {
    @Bindable var model: SummonModel
    @State private var selected: String?

    /// Installed agents first, then the rest; each id once.
    private var agents: [Agent] {
        let installed = Set(model.installedAgentIDs)
        return AgentRegistry.all.filter { installed.contains($0.id) } + AgentRegistry.all.filter { !installed.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                Label("All Agents", systemImage: "square.stack.3d.up")
                    .tag(Self.allTag)
                Section("Installed") {
                    ForEach(agents.filter { model.installedAgentIDs.contains($0.id) }, id: \.id) { agent in
                        AgentListRow(agent: agent, model: model).tag(agent.id)
                    }
                }
                Section("Not installed") {
                    ForEach(agents.filter { !model.installedAgentIDs.contains($0.id) }, id: \.id) { agent in
                        AgentListRow(agent: agent, model: model).tag(agent.id)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            if selected == Self.allTag {
                AllAgentsDetail(model: model)
            } else if let agent = agents.first(where: { $0.id == selected }) {
                AgentDetail(agent: agent, model: model)
                    .id(agent.id)
            } else {
                ContentUnavailableView("No Agent", systemImage: "sparkles")
            }
        }
        .task {
            // Fill every status dot, not only the open agent's.
            for id in model.installedAgentIDs where model.agentStatus[id] == nil {
                await model.checkAgent(id)
            }
            await model.loadCatalog()
        }
        .onAppear {
            if selected == nil { selected = Self.allTag }
        }
    }
}

extension AgentsSettings {
    static let allTag = "\u{0}all"
}

/// The defaults every agent starts from: which agent Ask Agent opens, where agents open, the skills they get,
/// and the plugins Summon recommends for all of them. Each agent's own page can then differ.
struct AllAgentsDetail: View {
    @Bindable var model: SummonModel

    var body: some View {
        Form {
            Section("All Agents") {
                Picker("Default agent", selection: Binding(get: { model.defaultAgent?.id ?? "" },
                                                           set: { if !$0.isEmpty { model.setDefaultAgent($0) } })) {
                    if model.defaultAgent == nil { Text("None").tag("") }
                    ForEach(AgentRegistry.all.filter { model.installedAgentIDs.contains($0.id) }, id: \.id) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }
                Picker("Open agents in", selection: Binding(get: { model.terminal }, set: { model.setTerminal($0) })) {
                    ForEach(model.installedTerminals, id: \.self) { Text($0.name).tag($0) }
                }
            }

            let all = model.shippedSkills
            let on = model.agentSettings.defaultSkills(shipped: all)
            Section {
                ForEach(all, id: \.self) { skill in
                    Toggle(isOn: Binding(get: { on.contains(skill) }, set: { model.setDefaultSkill(skill, on: $0) })) {
                        Text(skill)
                        if let description = model.skillDescriptions[skill] { Text(description).lineLimit(2) }
                    }
                    .disabled(skill == "summon")
                }
            } header: {
                HStack {
                    Text("Skills every agent gets")
                    Spacer()
                    Text("\(on.count) of \(all.count) on").foregroundStyle(.secondary)
                }
            }

            Section("Shared plugins") {
                ForEach(PluginCatalog.all) { plugin in
                    let states = model.catalogInstalled[plugin.id] ?? [:]
                    LabeledContent {
                        if states.values.contains(false) {
                            Button("Install in All") { model.installEverywhere(plugin.id) }
                                .disabled(model.pluginWork != nil)
                        } else if !states.isEmpty {
                            Text("In every agent").foregroundStyle(.secondary)
                        }
                    } label: {
                        Text(plugin.name)
                        Text(plugin.summary + (states.isEmpty ? "" : " " + states.sorted { $0.key < $1.key }
                            .map { (AgentRegistry.find($0.key)?.name ?? $0.key) + ($0.value ? "" : " (not yet)") }.joined(separator: ", ")))
                    }
                }
                if let work = model.pluginWork { Text(work).foregroundStyle(.secondary) }
            }
        }
        .formStyle(.grouped)
    }
}

/// Name, a status dot (green connected, orange not connected, grey unknown or not installed) and "Default".
struct AgentListRow: View {
    let agent: Agent
    let model: SummonModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .accessibilityLabel(status)
            VStack(alignment: .leading, spacing: 0) {
                Text(agent.name)
                if model.defaultAgent?.id == agent.id {
                    Text("Default").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .help(status)
    }

    private var installed: Bool { model.installedAgentIDs.contains(agent.id) }

    private var color: Color {
        guard installed else { return .secondary.opacity(0.4) }
        switch model.agentStatus[agent.id]?.login.loggedIn {
        case true?: return .green
        case false?: return .orange
        case nil: return .secondary
        }
    }

    private var status: String {
        guard installed else { return "Not installed" }
        switch model.agentStatus[agent.id]?.login.loggedIn {
        case true?: return "Connected"
        case false?: return "Not connected"
        case nil: return "Not checked yet"
        }
    }
}

/// One agent's page. Every agent gets the same sections; what an agent cannot do says so in one line.
struct AgentDetail: View {
    let agent: Agent
    @Bindable var model: SummonModel
    @State private var custom = false
    @State private var modelDraft = ""
    @State private var skillQuery = ""
    @State private var pluginDraft = ""

    private var installed: Bool { model.installedAgentIDs.contains(agent.id) }
    private var models: [String] { model.agentStatus[agent.id]?.models ?? [] }
    private var currentModel: String { model.agentSettings.model(for: agent.id) ?? "" }

    var body: some View {
        Form {
            account
            if installed {
                modelSection
                skills
                plugins
            }
        }
        .formStyle(.grouped)
        .task {
            guard installed else { return }
            await model.checkAgent(agent.id)
            await model.loadPlugins(agent.id)
        }
        .onAppear { modelDraft = currentModel }
    }

    // MARK: Account

    private var account: some View {
        Section {
            if installed {
                LabeledContent("Account") {
                    HStack(spacing: 8) {
                        if model.checkingAgents.contains(agent.id) {
                            ProgressView().controlSize(.small)
                        } else {
                            switch model.agentStatus[agent.id]?.login.loggedIn {
                            case true?:
                                Text(["Connected", model.agentStatus[agent.id]?.login.detail].compactMap { $0 }.joined(separator: " · "))
                                    .foregroundStyle(.secondary)
                            case false?:
                                Text("Not connected").foregroundStyle(.orange)
                                Button("Log In…") { model.logIn(agent.id) }
                            case nil:
                                Text("Unknown").foregroundStyle(.secondary)
                            }
                            Button {
                                Task { await model.checkAgent(agent.id) }
                            } label: { Image(systemName: "arrow.clockwise") }
                                .buttonStyle(.borderless)
                                .help("Check again")
                                .accessibilityLabel("Check again")
                        }
                    }
                }
                LabeledContent("Default agent") {
                    if model.defaultAgent?.id == agent.id {
                        Text("Yes").foregroundStyle(.secondary)
                    } else {
                        Button("Make Default") { model.setDefaultAgent(agent.id) }
                    }
                }
            } else {
                LabeledContent("Install") {
                    Text(agent.installHint)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        } header: {
            Text(agent.name)
        }
    }

    // MARK: Model

    @ViewBuilder private var modelSection: some View {
        Section("Model") {
            if agent.modelFlag == nil {
                LabeledContent("Model", value: "Set in \(agent.name)'s own settings")
            } else if !models.isEmpty, models.count <= 60, !custom {
                Picker("Model", selection: pickerBinding) {
                    Text("Agent default").tag("")
                    Divider()
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                    if !currentModel.isEmpty, !models.contains(currentModel) { Text(currentModel).tag(currentModel) }
                    Divider()
                    Text("Custom…").tag(Self.customTag)
                }
            } else {
                TextField("Model", text: $modelDraft, prompt: Text(models.isEmpty ? "Agent default" : "Search \(models.count) models"))
                    .textInputSuggestions {
                        ForEach(suggestions, id: \.self) { Text($0).textInputCompletion($0) }
                    }
                    .onSubmit { model.setAgentModel(modelDraft, for: agent.id) }
                if custom {
                    Button("Choose from List") { custom = false }
                }
            }
        }
    }

    static let customTag = "\u{0}custom"

    private var pickerBinding: Binding<String> {
        Binding(
            get: { currentModel },
            set: { value in
                if value == Self.customTag {
                    modelDraft = currentModel
                    custom = true
                } else {
                    model.setAgentModel(value, for: agent.id)
                }
            }
        )
    }

    private var suggestions: [String] {
        let query = modelDraft.trimmingCharacters(in: .whitespaces).lowercased()
        return Array((query.isEmpty ? models : models.filter { $0.lowercased().contains(query) }).prefix(30))
    }

    // MARK: Skills

    @ViewBuilder private var skills: some View {
        let all = model.shippedSkills
        let on = model.agentSettings.skills(for: agent.id, shipped: all)
        Section {
            if agent.skillFolder == nil {
                Text("\(agent.name) has no skills folder; it gets the skill files in each prompt instead.")
                    .foregroundStyle(.secondary)
            } else {
                if all.count > 6 {
                    TextField("Search", text: $skillQuery, prompt: Text("Search skills"))
                }
                ForEach(all.filter { skillQuery.isEmpty || $0.localizedCaseInsensitiveContains(skillQuery) }, id: \.self) { skill in
                    Toggle(isOn: Binding(get: { on.contains(skill) }, set: { model.setAgentSkill(skill, on: $0, for: agent.id) })) {
                        Text(skill)
                        if let description = model.skillDescriptions[skill] {
                            Text(description).lineLimit(2)
                        }
                    }
                    // The router is how "summon, <anything>" reaches the other skills: always on.
                    .disabled(skill == "summon")
                }
            }
        } header: {
            HStack {
                Text("Skills")
                Spacer()
                if agent.skillFolder != nil, !all.isEmpty {
                    if model.agentSettings.isCustom(agent.id) {
                        Text("Custom · \(on.count) of \(all.count)").foregroundStyle(.secondary)
                        Button("Use All Agents") { model.useDefaultSkills(for: agent.id) }
                            .buttonStyle(.link)
                    } else {
                        Text("Same as All Agents · \(on.count) of \(all.count)").foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: Plugins

    @ViewBuilder private var plugins: some View {
        let installedPlugins = model.agentPlugins[agent.id] ?? []
        let recommended = PluginCatalog.all.filter { $0.builds[agent.id] != nil }
        Section(agent.id == "codex" ? "MCP servers" : "Plugins") {
            if model.agentPlugins[agent.id] == nil {
                Text("Loading…").foregroundStyle(.secondary)
            } else if installedPlugins.isEmpty {
                Text("None yet").foregroundStyle(.secondary)
            }
            ForEach(installedPlugins) { plugin in
                LabeledContent {
                    HStack {
                        Text(plugin.enabled == false ? "Off" : (plugin.version ?? "")).foregroundStyle(.secondary)
                        if let catalog = recommended.first(where: { $0.isInstalled(for: agent.id, in: [plugin]) }) {
                            Button("Fix…") { model.fixPlugin(catalog.id, agent: agent.id) }
                                .help("Hand \(catalog.name) for \(agent.name) to your agent to diagnose and fix")
                        }
                    }
                } label: {
                    Text(verbatim: plugin.name)
                }
            }
            ForEach(recommended.filter { !$0.isInstalled(for: agent.id, in: installedPlugins) }) { catalog in
                LabeledContent {
                    Button("Install") { model.addPlugin(catalog.builds[agent.id] ?? "", to: agent.id) }
                        .disabled(model.pluginWork != nil || model.agentPlugins[agent.id] == nil)
                } label: {
                    Text(catalog.name)
                    Text("Recommended · \(catalog.summary)")
                }
            }
            if AgentPlugins.canAdd(agent) {
                HStack {
                    TextField("Add plugin", text: $pluginDraft, prompt: Text(Self.pluginExample(agent)))
                        .onSubmit(addPlugin)
                    Button("Add", action: addPlugin)
                        .disabled(pluginDraft.trimmingCharacters(in: .whitespaces).isEmpty || model.pluginWork != nil)
                }
            } else if agent.id != "codex" {
                Text("\(agent.name) has no plugins to manage here.").foregroundStyle(.secondary)
            }
            if let work = model.pluginWork {
                Text(work).foregroundStyle(.secondary)
            }
        }
    }

    static func pluginExample(_ agent: Agent) -> String {
        switch agent.id {
        case "claude": return "name@marketplace"
        case "pi": return "npm:package"
        case "agy": return "/path/to/plugin"
        default: return "package"
        }
    }

    private func addPlugin() {
        let spec = pluginDraft.trimmingCharacters(in: .whitespaces)
        guard !spec.isEmpty else { return }
        model.addPlugin(spec, to: agent.id)
        pluginDraft = ""
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
