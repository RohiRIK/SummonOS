# Sidebar Settings

Use a NavigationSplitView for several app preference sections. A single section
can be a grouped Form in the separate Settings scene. Sidebar navigation is a
project design choice, not a claim that native TabView settings are invalid.

This complete example illustrates local view state. In an app, bind these rows to
the existing settings store; a visual sample does not implement login-item APIs.

```swift
import SwiftUI

struct ModernSettingsView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        var id: Self { self }
        var systemImage: String {
            self == .general ? "gearshape" : "paintpalette"
        }
    }

    @State private var selection: Section? = .general
    @State private var showActivity = true
    @State private var compactRows = false

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Form {
                switch selection {
                case .general:
                    Toggle("Show activity", isOn: $showActivity)
                case .appearance:
                    Toggle("Compact rows", isOn: $compactRows)
                case nil:
                    Text("Select a section")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(selection?.rawValue ?? "Settings")
        }
        .frame(minWidth: 600, minHeight: 380)
    }
}
```

Keep standard padding and allow resizing. Open the Settings window using the
app's existing Settings action after activation, and verify it receives focus.
Keep preferences out of the menu panel even when there is only one setting.
