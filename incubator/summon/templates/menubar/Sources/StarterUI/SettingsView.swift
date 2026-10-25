import ServiceManagement
import SwiftUI

/// The Settings window (⌘,): every app preference lives here, never in the panel. One control per row, no
/// explanatory text. Changes apply at once (no Save). Close only: minimize and zoom are dimmed (HIG Settings).
/// Layout rule: a grouped Form while there are fewer than 3 sections; from 3 sections up, a NavigationSplitView
/// with a sidebar of sections, each a grouped Form (about 760-820 pt wide, LiquidGlass/SidebarSettings.md).
public struct SettingsView: View {
    @AppStorage(StarterSettings.showCountKey) private var showCount = false

    public init() {}

    public var body: some View {
        Form {
            Section("General") {
                OpenAtLoginToggle()
            }
            Section("Menu Bar") {
                Toggle("Show count in the menu bar", isOn: $showCount)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .closeOnlyWindow()
    }
}

/// Open at Login through `SMAppService.mainApp` (no helper app). It shows the real state, so a change made in
/// System Settings › General › Login Items shows here too. Works from the bundled app (`scripts/bundle.sh`).
struct OpenAtLoginToggle: View {
    @State private var isOn = SMAppService.mainApp.status == .enabled
    @State private var error: String?

    var body: some View {
        Toggle("Open at Login", isOn: Binding(get: { isOn }, set: { change($0) }))
            .onAppear { isOn = SMAppService.mainApp.status == .enabled }
        if let error {
            Text(error).font(.subheadline).foregroundStyle(.red)
        }
    }

    private func change(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        let status = SMAppService.mainApp.status
        isOn = status == .enabled
        if status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }
}

/// The menu bar item: an icon, or the count when the setting is on.
public struct MenuBarLabel: View {
    @AppStorage(StarterSettings.showCountKey) private var showCount = false
    private let model: StarterModel

    public init(model: StarterModel) {
        self.model = model
    }

    public var body: some View {
        if showCount {
            Text("\(model.counter.value)")
        } else {
            Image(systemName: "plus.circle")
        }
    }
}

#Preview("Settings") {
    SettingsView()
}
