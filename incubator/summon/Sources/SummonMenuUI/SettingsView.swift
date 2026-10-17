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
                LabeledContent("Start agent", value: "⌃⌥⌘A")
                LabeledContent("Summon Menu", value: "⌥Space")
            }

            Section("Crash Capture") {
                Toggle("Notify me when an app crashes or hangs", isOn: $model.crashCaptureEnabled)
                Text("Diagnose hands the report to your default agent. Mute stops notifications for that app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !model.themes.isEmpty {
                Section("Theme") {
                    Picker("Theme", selection: themeBinding) {
                        ForEach(model.themes) { theme in
                            Text(theme.name).tag(theme.slug)
                        }
                    }
                }
            }

            Section("General") {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { _, newValue in
                        setOpenAtLogin(newValue)
                    }
                if let loginError {
                    Text(loginError)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 600)
    }

    private var agentBinding: Binding<String> {
        Binding(
            get: { model.defaultAgent?.id ?? "" },
            set: { newValue in
                if !newValue.isEmpty { model.setDefaultAgent(newValue) }
            }
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
