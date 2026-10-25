# Starter

A full window app: `WindowGroup` + `NavigationSplitView` with an inspector, a Dock icon, menus with ⌘ shortcuts.
Made with Summon from its window app template, to the SummonOS surface rules for a desktop app
(`docs/ux-surfaces/02-desktop-app.md` in the SummonOS workspace).

## Behavior

| What | How |
|---|---|
| Window | Sidebar, content, inspector (⌥⌘I); resizable from 800 × 550, full screen and Split View |
| Find | ⌘F focuses the sidebar's search field; no matches shows the system's search empty state |
| Actions | Every action is in the menu bar with its shortcut and in each row's context menu |
| Delete | No confirmation: Edit › Undo (⌘Z) puts the item back where it was (HIG: undo over alerts) |
| Settings | ⌘,; close only (minimize and zoom dimmed), 480 pt, changes apply at once |
| First run | A 640 × 440 welcome window (`Onboarding.swift`), once; closing it skips it; Settings › Welcome shows it again |

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the `WindowGroup`, menu commands and `Settings` scenes |
| `Sources/StarterUI/` | Sidebar + detail window, Settings window (Open at Login, the sidebar toggle), `@Observable` model, `#Preview`s |
| `Sources/StarterUI/SummonTheme.swift` | `.themed()`: the Summon theme's accent on every window root, live |
| `Sources/StarterUI/Glass.swift` | `.glassControl()`: Liquid Glass on macOS 26, a material on 15; controls only |
| `Sources/StarterUI/Onboarding.swift` | The first-run window: steps, permission cards with live status (`StarterOnboarding.permissions`, empty by default) |
| `Sources/StarterUI/CloseOnlyWindow.swift` | `.closeOnlyWindow()`: dims minimize and zoom, no full screen (Settings, setup) |
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
