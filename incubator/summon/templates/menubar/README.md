# Starter

A menu bar app: a status item with a panel (`MenuBarExtra`, `.window` style), `LSUIElement`, no Dock icon. Made with Summon from its menu bar app template.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the `MenuBarExtra` and `Settings` scenes |
| `Sources/StarterUI/` | Panel, Settings window (Open at Login, Show count in the menu bar), `@Observable` model, `#Preview`s |
| `Sources/StarterUI/Components.swift` | Menu rows with hover and key hints, the module tile, headers, dividers |
| `Sources/StarterUI/SummonTheme.swift` | `.themed()`: the Summon theme's accent on every window root, live |
| `Sources/StarterUI/Glass.swift` | `.glassControl()`: Liquid Glass on macOS 26, a material on 15; controls only |
| `Sources/StarterUI/CloseOnlyWindow.swift` | `.closeOnlyWindow()` on Settings: minimize and zoom dimmed, no full screen |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: light and dark PNGs, used by `summon project shots` |
| `Sources/StarterCore/` | Logic, Foundation only, tested (`SummonThemeFile` reads the Summon theme) |
| `Resources/` | `Info.plist`: Bundle id `local.summon.menubar-starter`, `LSUIElement`; `AppIcon.icns` (a placeholder: replace it with the summon-art skill) |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, which also works without Xcode), and the rest; writes `build/check-report.md` |

The menu bar setting changes the label between icon and count; it does not hide the status item. Use the
`menubar-panel` starter when a hideable icon and a programmatic way back into the app are needed.

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
