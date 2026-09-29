# SwiftUI patterns for menu bar panels

Compose views from these. Each compiles on macOS 14+ (glass parts on 26+).

## Panel shell

```swift
struct PanelView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var screen: Screen = .main
    enum Screen { case main, settings }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch screen {
            case .main: MainScreen(openSettings: { screen = .settings })
                    .transition(.move(edge: .leading).combined(with: .opacity))
            case .settings: SettingsScreen(back: { screen = .main })
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(width: 320)
        .animation(.snappy, value: screen)
        .onKeyPress(.escape) {
            if screen == .main { dismiss() } else { screen = .main }
            return .handled
        }
    }
}
```

## Header with toggle

```swift
HStack {
    Text("Wi-Fi").font(.headline)
    Spacer()
    Toggle("Wi-Fi", isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
}
.padding(.bottom, 8)
```

## Menu row, circle icon, section header

Current versions live in `plugins/mac-network/Sources/MacNetworkUI/Components.swift` (`MenuRow`, `CommandRow`, `CircleIcon`, `MenuSectionHeader`, `MenuDivider`). Copy those. Older row shape below.

```swift
struct Row<Trailing: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).frame(width: 18).foregroundStyle(.secondary)
            Text(title)
            Spacer()
            trailing.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(hovering ? Color.primary.opacity(0.08) : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
```

## Signal icon (variable value + smooth change)

```swift
Image(systemName: "wifi", variableValue: Double(strength) / 100)
    .symbolRenderingMode(.hierarchical)
    .contentTransition(.symbolEffect(.replace))
    .accessibilityValue("\(strength) percent")
```

## Status dot

```swift
Circle().fill(ok ? .green : .red).frame(width: 7, height: 7)
    .accessibilityLabel(ok ? "Connected" : "Disconnected")
```

## Key-value detail grid

```swift
Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
    GridRow { Text("IP").foregroundStyle(.secondary); Text(ip).textSelection(.enabled) }
    GridRow { Text("Ping").foregroundStyle(.secondary); Text(ping).monospacedDigit() }
}
.font(.callout)
```

## Click-only action with inline result

```swift
Button { Task { await lookup() } } label: {
    if loading { ProgressView().controlSize(.small) } else { Text("Look up via ipify.org") }
}
.buttonStyle(.link)
.disabled(loading)
```

## Settings screen

See `MenuPanel.md` and `plugins/mac-network/Sources/MacNetworkUI/SettingsScreen.swift`: `Grid` of trailing labels and small controls, pop-up pickers, no `Form`.

## Empty / error / permission states

```swift
ContentUnavailableView {
    Label("Location access needed", systemImage: "location.slash")
} description: {
    Text("macOS hides Wi-Fi names until the app can use Location Services.")
} actions: {
    Button("Open Settings") {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!)
    }
}
```

## Keyboard hint

```swift
Button("Refresh", action: refresh).keyboardShortcut("r", modifiers: [])
    .help("Refresh (R)")
```
