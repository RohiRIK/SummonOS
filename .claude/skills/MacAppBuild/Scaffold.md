# Scaffold

Start every new plugin with `mp new` from the workspace root:

```bash
tools/mp new <name> --kind menubar        # or menubar-panel, app, cli, screensaver
```

It copies Summon's template for that kind (`incubator/summon/templates/<kind>/`, the one set of templates, built
and checked in CI) to `$MACPLUGINS_HOME/scratch/<name>/`, renames `Starter` to the PascalCase name (`MacBattery`)
and `<kind>-starter` to the kebab-case name (`mac-battery`), switches the bundle prefix `local.summon.` to
`local.macplugins.`, runs `git init`, and registers it in `plugins.json`. Never write a new plugin anywhere
else. Repos come later, with the owner's OK: `tools/mp promote <name> --yes` (see `docs/tools.md`).

This is for plugins of this workspace. Apps a user makes through Summon do not go here: they start with
`summon project new <name> --kind menubar|menubar-panel|app|cli|screensaver` in `~/Summon/Apps/<name>` from the
same templates, are listed only in Summon's private `~/.config/summon/projects.json`, and get a private repo only
through `summon project repo`.

Every template ships with `scripts/check.sh` (the gate), `scripts/test.sh` (works with the Command Line Tools
only), `LICENSE`, `PROJECT-CONTEXT.md`, and, for the UI kinds, the shared kit: `Components.swift` (menu rows),
`SummonTheme.swift` (`.themed()`), `Glass.swift` (`.glassControl()`), `Screenshots.swift` (`--screenshot`), an
Open at Login toggle in Settings, and a placeholder `Resources/AppIcon.icns`. In the snippets on this page, `App`
stands for the PascalCase name and `<name>` for the kebab-case name.

## Layout

```
scratch/<name>/                 plugins/<name>/ after mp promote
├── Package.swift
├── Sources/
│   ├── App/            @main only
│   ├── AppUI/          views, @Observable model, #Previews (library product)
│   └── AppCore/        logic, services, tool wrappers (tested)
├── Tests/AppCoreTests/
├── Resources/          Info.plist (CFBundleIconFile AppIcon), AppIcon.icns
├── scripts/            check.sh, test.sh, bundle.sh (from the template; pr-report.sh from mac-network)
├── docs/previews/      rendered previews (tracked; README + PR comments embed them)
├── .gitignore          .build/ build/ .DS_Store .swiftpm/ graphify-out/
├── LICENSE             MIT only (upstream notices in THIRD_PARTY_NOTICES.md)
└── README.md
```

No `.github/workflows`: there is no GitHub Actions billing. `scripts/check.sh` is the gate.

## Package.swift

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "App",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "App", targets: ["App"]),
        // Library product so Xcode makes a scheme for it: SwiftUI previews do not run in executable targets.
        .library(name: "AppUI", targets: ["AppUI"]),
    ],
    targets: [
        .target(name: "AppCore"),
        .target(name: "AppUI", dependencies: ["AppCore"]),
        .executableTarget(name: "App", dependencies: ["AppUI"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore"]),
    ]
)
```

## Sources/App/App.swift

```swift
import AppUI
import SwiftUI

@main
struct AppMain: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("App", systemImage: "circle") {
            PanelView(model: model)
        }
        .menuBarExtraStyle(.window)
    }
}
```

`AppModel` and `PanelView` are `public` in `AppUI` (public `init` too).

## Resources/Info.plist

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>App</string>
    <key>CFBundleIdentifier</key><string>local.macplugins.<name></string>
    <key>CFBundleName</key><string>App</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
```

Add usage strings (`NSLocationUsageDescription`, …) when a feature needs them.

## Scripts (from the template)

- `scripts/test.sh`: `swift test` with the build cache in `~/Library/Caches/macplugins/<name>` and
  the Command Line Tools `Testing.framework` flags when Xcode is not selected.
- `scripts/bundle.sh`: release build, wrap in `build/App.app` with `AppIcon.icns`, ad-hoc sign.
- `scripts/check.sh`: build + `scripts/test.sh` + plist lint + bundle, writes `build/check-report.md`.
- `scripts/pr-report.sh` (copy from the public `mac-network` repo): runs the gate and comments the report plus
  `docs/previews/*.png` on the PR.

With only the Command Line Tools, the Core tests pass but a UI target does not compile (`#Preview`, `@State` and
other SwiftUI macros need Xcode's plugins): build UI kinds with Xcode selected, or in CI.
