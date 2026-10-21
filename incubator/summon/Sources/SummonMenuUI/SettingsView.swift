import AppKit
import ServiceManagement
import SummonCore
import SwiftUI

/// All targets reachable in the Settings sidebar.
public enum SettingsPanel: Hashable {
    case general
    case agents
    case terminal
    case notifications
    case appearance
    case tasks
    case agent(String)
}

/// The Settings window (⌘,): modern macOS sidebar navigation with grouped forms.
/// Every app preference lives here, never in the menu bar panel.
public struct SettingsView: View {
    @Bindable var model: SummonModel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var selection: SettingsPanel? = .general
    @State private var query = ""

    static let sections = SettingsSection.allCases

    private var filteredSections: [SettingsSection] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return Self.sections }
        return Self.sections.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var allAgents: [Agent] {
        let installed = Set(model.installedAgentIDs)
        return AgentRegistry.all.filter { installed.contains($0.id) } + AgentRegistry.all.filter { !installed.contains($0.id) }
    }

    private var filteredAgents: [Agent] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return allAgents }
        return allAgents.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }

    public init(model: SummonModel) {
        self.model = model
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selection) {
                Section {
                    ForEach(filteredSections) { section in
                        Label {
                            Text(section.title)
                                .font(.system(size: 13, weight: .regular))
                        } icon: {
                            Image(systemName: section.systemImage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(section.badgeColor, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .tag(section.panel)
                    }
                }

                Section {
                    ForEach(filteredAgents, id: \.id) { agent in
                        SidebarAgentRow(agent: agent, model: model)
                            .tag(SettingsPanel.agent(agent.id))
                    }
                } header: {
                    HStack {
                        Text("Agents")
                        Spacer()
                        Text("\(model.installedAgentIDs.count) on")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $query, placement: .sidebar, prompt: "Search settings...")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 860, idealWidth: 900, minHeight: 560, idealHeight: 620)
        .task {
            await model.loadShippedSkills()
            for id in model.installedAgentIDs where model.agentStatus[id] == nil {
                await model.checkAgent(id)
            }
            await model.loadCatalog()
        }
    }

    @ViewBuilder private var detailView: some View {
        if let selection {
            VStack(alignment: .leading, spacing: 0) {
                detailHeader(for: selection)

                detailContent(for: selection)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView("Select a Section", systemImage: "gearshape")
        }
    }

    @ViewBuilder private func detailHeader(for panel: SettingsPanel) -> some View {
        HStack(spacing: 14) {
            switch panel {
            case .general:
                headerIcon(systemName: "gearshape.fill", color: .gray)
                headerText(title: "General", subtitle: "System defaults, startup behavior, and global shortcuts")
            case .agents:
                headerIcon(systemName: "sparkles", color: .purple)
                headerText(title: "All Agents", subtitle: "Installed coding agents, model connections, and providers")
            case .terminal:
                headerIcon(systemName: "terminal.fill", color: .black)
                headerText(title: "Terminal", subtitle: "Default terminal emulator, launch behavior, and window styling")
            case .notifications:
                headerIcon(systemName: "bell.badge.fill", color: .red)
                headerText(title: "Notifications", subtitle: "Alert triggers, crash warnings, and sound effects")
            case .appearance:
                headerIcon(systemName: "paintpalette.fill", color: .blue)
                headerText(title: "Appearance", subtitle: "Theme palettes, colors, and visual styling")
            case .tasks:
                headerIcon(systemName: "clock.arrow.circlepath", color: .orange)
                headerText(title: "Tasks", subtitle: "Automation schedule, recurring maintenance, and log rotation")
            case .agent(let id):
                if let agent = AgentRegistry.find(id) {
                    AgentBrandIcon(agentId: agent.id, size: 24)
                        .frame(width: 36, height: 36)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    headerText(title: agent.name, subtitle: "AI assistant settings, provider login, and custom model")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    private func headerIcon(systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 36, height: 36)
            .background(color, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: color.opacity(0.25), radius: 3, y: 1.5)
    }

    private func headerText(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func detailContent(for panel: SettingsPanel) -> some View {
        switch panel {
        case .general:
            GeneralSettings(model: model)
        case .agents:
            AllAgentsDetail(model: model)
        case .terminal:
            TerminalSettings(model: model)
        case .notifications:
            NotificationSettings(model: model)
        case .appearance:
            AppearanceSettings(model: model)
        case .tasks:
            TasksSettings(model: model)
        case .agent(let id):
            if let agent = AgentRegistry.find(id) {
                AgentDetail(agent: agent, model: model)
                    .id(agent.id)
            } else {
                ContentUnavailableView("Unknown Agent", systemImage: "questionmark")
            }
        }
    }
}

/// One section's rows. Split out so each section has its own preview.
struct SettingsSectionView: View {
    let section: SettingsSection
    @Bindable var model: SummonModel

    var body: some View {
        content
            .navigationTitle(section.title)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general: GeneralSettings(model: model)
        case .agents: AllAgentsDetail(model: model)
        case .terminal: TerminalSettings(model: model)
        case .notifications: NotificationSettings(model: model)
        case .appearance: AppearanceSettings(model: model)
        case .tasks: TasksSettings(model: model)
        }
    }
}

extension SettingsSection {
    var panel: SettingsPanel {
        switch self {
        case .general: return .general
        case .agents: return .agents
        case .terminal: return .terminal
        case .notifications: return .notifications
        case .appearance: return .appearance
        case .tasks: return .tasks
        }
    }

    var badgeColor: Color {
        switch self {
        case .general: return Color.blue
        case .agents: return Color.purple
        case .terminal: return Color.cyan
        case .notifications: return Color.red
        case .appearance: return Color.pink
        case .tasks: return Color.orange
        }
    }
}

/// Agent row displayed in the Settings sidebar with its connection status dot.
struct SidebarAgentRow: View {
    let agent: Agent
    let model: SummonModel

    private var installed: Bool { model.installedAgentIDs.contains(agent.id) }
    private var isDefault: Bool { model.defaultAgent?.id == agent.id }

    var body: some View {
        HStack(spacing: 8) {
            AgentBrandIcon(agentId: agent.id, size: 16)
                .foregroundStyle(installed ? .primary : .secondary)
                .frame(width: 18, height: 18)

            Text(agent.name)
                .font(.system(size: 13, weight: isDefault ? .medium : .regular))
                .foregroundStyle(installed ? .primary : .secondary)

            Spacer()

            if isDefault {
                Text("Default")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
            }

            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
        }
    }

    private var statusColor: Color {
        guard installed else { return .secondary.opacity(0.3) }
        switch model.agentStatus[agent.id]?.login.loggedIn {
        case true?: return .green
        case false?: return .orange
        case nil: return .green.opacity(0.8)
        }
    }
}

// MARK: General

struct GeneralSettings: View {
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    @State private var cleanPlan: SummonCleaner.Plan?
    @State private var confirmingClean = false
    @Bindable var model: SummonModel

    var body: some View {
        Form {
            Section("System") {
                Picker("Default agent", selection: Binding(
                    get: { model.defaultAgent?.id ?? "" },
                    set: { if !$0.isEmpty { model.setDefaultAgent($0) } }
                )) {
                    if model.defaultAgent == nil { Text("None").tag("") }
                    ForEach(AgentRegistry.all.filter { model.installedAgentIDs.contains($0.id) }, id: \.id) { agent in
                        Text(agent.name).tag(agent.id)
                    }
                }

                Picker("Default terminal", selection: Binding(
                    get: { model.terminal },
                    set: { model.setTerminal($0) }
                )) {
                    ForEach(model.installedTerminals, id: \.self) { term in
                        Text(term.name).tag(term)
                    }
                }

                Toggle("Start at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        setOpenAtLogin(newValue)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }

                LabeledContent("Summon workspace") {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.open(model.paths.home)
                    }
                }
            }

            Section("Automation & Storage") {
                Picker("Agent execution", selection: Binding(get: { model.executionMode }, set: { model.setExecutionMode($0) })) {
                    ForEach(AgentExecutionMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .help("Agent controls uses the agent's own permission behavior. Unattended bypasses supported harness approvals and sandboxing. Checkpoints cover only supported settings and captured config files.")

                Toggle(isOn: Binding(get: { model.repoPolicy == .always }, set: { model.setRepoPolicy($0 ? .always : .ask) })) {
                    Text("Create a private GitHub repo for every new app")
                    Text("With screenshots and CI. Always private. Off: Summon asks each time.")
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
            }

            Section {
                ShortcutRecorderRow(
                    title: "Open Summon Panel (Global)",
                    shortcut: model.globalMenuShortcut,
                    defaultShortcut: .defaultGlobalMenu,
                    available: !model.unavailableHotKeys.contains(model.globalMenuShortcut.displayString),
                    onRecord: { model.setGlobalMenuShortcut($0) },
                    onReset: { model.resetGlobalMenuShortcut() }
                )
                ShortcutRecorderRow(
                    title: "Ask Default Agent (Global)",
                    shortcut: model.globalAgentShortcut,
                    defaultShortcut: .defaultGlobalAgent,
                    available: !model.unavailableHotKeys.contains(model.globalAgentShortcut.displayString),
                    onRecord: { model.setGlobalAgentShortcut($0) },
                    onReset: { model.resetGlobalAgentShortcut() }
                )
                ShortcutRecorderRow(
                    title: "Quick-Launch Agent (in Panel)",
                    shortcut: model.panelAgentShortcut,
                    defaultShortcut: .defaultPanelAgent,
                    available: true,
                    onRecord: { model.setPanelAgentShortcut($0) },
                    onReset: { model.resetPanelAgentShortcut() }
                )
            } header: {
                Text("Keyboard Shortcuts")
            } footer: {
                Text("Global shortcuts work anywhere in macOS. Quick-Launch Agent triggers directly from the search bar or anywhere in the Summon panel. Click Record on any shortcut to customize it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Text("Powered by caffeine and questionable choices.")
                        .font(.footnote)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(role: .destructive) {
                        NSApp.terminate(nil)
                    } label: {
                        Text("Quit Summon")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
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
            AgentBrandIcon(agentId: agent.id, size: 14)
                .foregroundStyle(installed ? .primary : .secondary)
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

// MARK: Terminal

struct TerminalSettings: View {
    @Bindable var model: SummonModel
    @State private var installingTerminal: TerminalApp? = nil
    @State private var installError: String? = nil

    var body: some View {
        Form {
            Section("Default Terminal") {
                Picker("Open agents in", selection: Binding(
                    get: { model.terminal },
                    set: { model.setTerminal($0) }
                )) {
                    ForEach(model.installedTerminals, id: \.self) { term in
                        Text(term.name).tag(term)
                    }
                }
            }

            Section {
                ForEach(TerminalApp.allCases, id: \.self) { term in
                    let isInstalled = model.installedTerminals.contains(term)
                    let isDefault = model.terminal == term

                    HStack(spacing: 8) {
                        Label(term.name, systemImage: "terminal")

                        if isDefault {
                            Text("Default")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.12), in: Capsule())
                        }

                        Spacer()

                        if isInstalled {
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Installed")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                if !isDefault {
                                    Button("Make Default") {
                                        model.setTerminal(term)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        } else if term.caskName != nil {
                            if installingTerminal == term {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Installing \(term.name)…")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button("Install with Homebrew") {
                                    install(term)
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                        } else {
                            Text("Not Found")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }

                if let installError {
                    Text(installError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.top, 4)
                }
            } header: {
                Text("Detected & Available Terminals")
            } footer: {
                Text("Summon launches your default terminal for agents in ~/Summon. Ghostty and kitty can be automatically installed via Homebrew.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func install(_ term: TerminalApp) {
        installError = nil
        installingTerminal = term
        Task {
            do {
                try await model.installTerminal(term)
                installingTerminal = nil
            } catch {
                installingTerminal = nil
                installError = error.localizedDescription
            }
        }
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
    @State private var previewSlug: String = ""
    @State private var applySuccess = false

    private var store: ThemeStore {
        ThemeStore(paths: model.paths)
    }

    private var activeTheme: Theme? {
        model.themes.first { $0.slug == model.currentThemeSlug }
    }

    private var selectedTheme: Theme? {
        model.themes.first { $0.slug == previewSlug } ?? activeTheme ?? model.themes.first
    }

    private var previousTheme: Theme? {
        guard let prev = model.previousThemeSlug else { return nil }
        return model.themes.first { $0.slug == prev }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "paintpalette.fill")
                            .foregroundStyle(.blue)
                        Text("System-Wide Aesthetic")
                            .font(.headline)
                    }
                    Text("Applying a theme automatically sets your desktop wallpaper, switches macOS light/dark mode, updates your terminal colors (Ghostty), and tints window borders.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Theme Preview & Selection") {
                if model.themes.isEmpty {
                    Text("No themes installed.").foregroundStyle(.secondary)
                } else {
                    Picker("Select Theme", selection: $previewSlug) {
                        ForEach(model.themes) { theme in
                            HStack {
                                Text(theme.name)
                                if theme.slug == model.currentThemeSlug {
                                    Text("(Active)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(theme.slug)
                        }
                    }
                    .onAppear {
                        if previewSlug.isEmpty {
                            previewSlug = model.currentThemeSlug ?? model.themes.first?.slug ?? ""
                        }
                    }

                    if let theme = selectedTheme {
                        ThemePreviewCard(theme: theme, store: store)

                        HStack(spacing: 12) {
                            if theme.slug == model.currentThemeSlug {
                                Label("Currently Active", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline.weight(.medium))
                            } else {
                                Button {
                                    model.setTheme(theme.slug)
                                    applySuccess = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        applySuccess = false
                                    }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: applySuccess ? "checkmark" : "sparkles")
                                        Text(applySuccess ? "Applied!" : "Apply Theme")
                                    }
                                    .frame(minWidth: 110)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                            }

                            Spacer()

                            if let prev = previousTheme, prev.slug != model.currentThemeSlug {
                                Button {
                                    previewSlug = prev.slug
                                    model.revertTheme()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "arrow.uturn.backward")
                                        Text("Undo: Revert to \(prev.name)")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct ThemePreviewCard: View {
    let theme: Theme
    let store: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = store.wallpaperURL(theme),
               let nsImage = NSImage(contentsOf: url) {
                ZStack(alignment: .bottomTrailing) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                        )

                    HStack(spacing: 4) {
                        Image(systemName: theme.isDark ? "moon.fill" : "sun.max.fill")
                        Text(theme.appearance.capitalized)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(8)
                }
            }

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(theme.name)
                        .font(.headline)
                    if let source = theme.source {
                        Text(source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 6) {
                    ColorDot(hex: theme.colors.accent, label: "Accent")
                    ColorDot(hex: theme.colors.accent2, label: "Accent 2")
                    ColorDot(hex: theme.colors.background, label: "Background")
                    ColorDot(hex: theme.colors.foreground, label: "Foreground")
                    ColorDot(hex: theme.colors.muted, label: "Muted")
                    ColorDot(hex: theme.colors.borderActive, label: "Border")
                }
            }
            .padding(.horizontal, 2)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ColorDot: View {
    let hex: String
    let label: String

    var body: some View {
        Circle()
            .fill(Color(hex: hex) ?? .gray)
            .frame(width: 16, height: 16)
            .overlay(Circle().stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            .help("\(label): \(hex)")
    }
}

extension Color {
    init?(hex: String) {
        var clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        if clean.count == 3 {
            clean = clean.map { "\($0)\($0)" }.joined()
        }
        guard clean.count == 6, let int = UInt64(clean, radix: 16) else { return nil }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
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

/// One fixed shortcut; "Unavailable" when another app owned it at launch (panel spec C4).
private struct ShortcutRow: View {
    let title: String
    let keys: String
    let available: Bool

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                if !available {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .help("Another app owns this shortcut. Free it there, then relaunch Summon.")
                }
                Text(keys)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .strikethrough(!available)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

/// An interactive shortcut recorder row allowing the user to record custom shortcut keys.
private struct ShortcutRecorderRow: View {
    let title: String
    let shortcut: PanelShortcut
    let defaultShortcut: PanelShortcut
    var available: Bool = true
    let onRecord: (PanelShortcut) -> Void
    let onReset: () -> Void

    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                if !available {
                    Text("Unavailable")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .help("Another app owns this shortcut. Free it there, or record a different shortcut.")
                }

                if isRecording {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Press keys… (Esc to cancel)")
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.blue.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.blue, lineWidth: 1))

                    Button("Cancel") {
                        stopRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Text(shortcut.displayString)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.primary)
                        .strikethrough(!available)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5))

                    Button("Record") {
                        startRecording()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if shortcut != defaultShortcut {
                        Button("Reset to \(defaultShortcut.displayString)") {
                            onReset()
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        stopRecording()
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                stopRecording()
                return nil
            }

            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let hasCommand = flags.contains(.command)
            let hasOption = flags.contains(.option)
            let hasControl = flags.contains(.control)
            let hasShift = flags.contains(.shift)

            // Must include at least one modifier
            guard hasCommand || hasOption || hasControl || hasShift else {
                return nil
            }

            let keyCode = UInt32(event.keyCode)
            var keyName = ""
            if keyCode == 36 || keyCode == 76 { // Return or Enter
                keyName = "return"
            } else if keyCode == 49 { // Space
                keyName = "space"
            } else if keyCode == 48 { // Tab
                keyName = "tab"
            } else if let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty {
                keyName = chars
            } else {
                return nil
            }

            let display = PanelShortcut.format(
                key: keyName,
                keyCode: keyCode,
                isCommand: hasCommand,
                isOption: hasOption,
                isControl: hasControl,
                isShift: hasShift
            )

            let newShortcut = PanelShortcut(
                key: keyName,
                keyCode: keyCode,
                displayString: display,
                isCommand: hasCommand,
                isOption: hasOption,
                isControl: hasControl,
                isShift: hasShift
            )

            onRecord(newShortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        isRecording = false
    }
}
