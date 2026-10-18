import ServiceManagement
import SummonCore
import SwiftUI

/// Every app preference lives here, never in the menu bar panel.
public struct SettingsView: View {
    @Bindable var model: SummonModel
    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    public init(model: SummonModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section("Agent") {
                Picker("Default agent", selection: agentBinding) {
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
                if model.installedTerminals.count > 1 {
                    Picker("Open in", selection: terminalBinding) {
                        ForEach(model.installedTerminals, id: \.self) { terminal in
                            Text(terminal.name).tag(terminal)
                        }
                    }
                }
            }

            Section("Notifications") {
                Toggle("Crashes and hangs", isOn: $model.crashCaptureEnabled)
                ForEach(model.mutedPrograms, id: \.self) { program in
                    LabeledContent {
                        Button("Unmute") { model.unmute(program: program) }
                    } label: {
                        Text(verbatim: program)
                        Text("Muted")
                    }
                }
            }

            if !model.themes.isEmpty {
                Section("Appearance") {
                    Picker("Theme", selection: themeBinding) {
                        ForEach(model.themes) { theme in
                            Text(theme.name).tag(theme.slug)
                        }
                    }
                }
            }

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
            } header: {
                Text("General")
            } footer: {
                Text("Powered by caffeine and questionable choices.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 490)
    }

    private var agentBinding: Binding<String> {
        Binding(
            get: { model.defaultAgent?.id ?? "" },
            set: { newValue in
                if !newValue.isEmpty { model.setDefaultAgent(newValue) }
            }
        )
    }

    private var terminalBinding: Binding<TerminalApp> {
        Binding(
            get: { model.terminal },
            set: { newValue in model.setTerminal(newValue) }
        )
    }

    private var themeBinding: Binding<String> {
        Binding(
            get: { model.currentThemeSlug ?? "" },
            set: { newValue in model.setTheme(newValue) }
        )
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

#Preview("Settings") {
    SettingsView(model: .preview())
}
