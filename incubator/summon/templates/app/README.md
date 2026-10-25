# Starter

A full window app: `WindowGroup` + `NavigationSplitView`, a Dock icon, menus with ⌘ shortcuts. Made with Summon from its window app template.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the `WindowGroup`, menu commands and `Settings` scenes |
| `Sources/StarterUI/` | Sidebar + detail window, Settings window (Open at Login, the sidebar toggle), `@Observable` model, `#Preview`s |
| `Sources/StarterUI/SummonTheme.swift` | `.themed()`: the Summon theme's accent on every window root, live |
| `Sources/StarterUI/Glass.swift` | `.glassControl()`: Liquid Glass on macOS 26, a material on 15; controls only |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: light and dark PNGs, used by `summon project shots` |
| `Sources/StarterCore/` | Logic, Foundation only, tested (`SummonThemeFile` reads the Summon theme) |
| `Resources/` | `Info.plist`: Bundle id `local.summon.app-starter`; `AppIcon.icns` (a placeholder: replace it with the summon-art skill) |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, which also works without Xcode), and the rest; writes `build/check-report.md` |

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
