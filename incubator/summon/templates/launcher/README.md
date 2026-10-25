# Starter

A command launcher: a global shortcut (⌥Space by default) shows a Spotlight-style bar over any app, even a
full-screen one; type, pick with the keyboard, and it opens the app and vanishes. `LSUIElement`, no Dock icon,
a small menu bar menu that people can hide. Made with Summon from its `launcher` template. The starter's job is
opening apps; replace `AppCatalog` with your own items and keep the panel.

Built to the SummonOS surface rules for a launcher (`docs/ux-surfaces/04-command-launcher.md` in the SummonOS
workspace): Apple reserves ⌘Space for Spotlight, so the default is ⌥Space and people record their own.

## Behavior

| What | How |
|---|---|
| Open | The global shortcut (`RegisterEventHotKey`, no permission prompt), the menu bar menu, or `LauncherController.open()` |
| Show | Pre-warmed: the panel is made at launch and kept hidden, so opening is one `orderFront`, with no window animation |
| Shape | 680 pt wide; a 56 pt bar that grows a results list as you type (to about 450 pt); the top edge never moves |
| Focus | `.nonactivatingPanel` + `canBecomeKey`: the field takes keys, the frontmost app keeps its menu bar |
| Keys | ↑↓ select, ↩ open, ⌘1…⌘9 open that row, ⌘K actions (Open, Show in Finder, Copy Path), ⌘, Settings, Esc closes |
| Close | Esc, a click anywhere else (the panel loses key), a Space change, or after opening |
| Drop | Drop a file on the bar, then pick an app: it opens that file |
| Errors | A status line in the footer, no alert; it stays until the next keystroke |
| Settings | Open at Login, Show in menu bar, the shortcut recorder (refuses ⌘Space and other system shortcuts) |
| Reopen | Opening the app again from the Finder shows Settings: the way back when the menu bar item is hidden |

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the invisible opener window and the `Settings` scene |
| `Sources/StarterUI/LauncherPanel.swift` | `LauncherPanel` (`NSPanel`, pinned top edge) and `LauncherController` |
| `Sources/StarterUI/LauncherView.swift` | Search bar, results, ⌘K actions, footer, file drop |
| `Sources/StarterUI/StarterModel.swift` | Query, ranked results, selection, status; opens apps through `NSWorkspace` |
| `Sources/StarterUI/AppDelegate.swift` | Creates the launcher, registers the hotkey, owns the menu bar menu |
| `Sources/StarterUI/HotKey.swift` | Global shortcuts through Carbon `RegisterEventHotKey` |
| `Sources/StarterUI/ShortcutRecorder.swift` | The Settings row that records a shortcut |
| `Sources/StarterUI/StatusMenu.swift` | A template SF Symbol in the menu bar with a plain `NSMenu` |
| `Sources/StarterUI/SettingsOpener.swift` | Opens the Settings window from AppKit code |
| `Sources/StarterUI/SummonTheme.swift`, `Glass.swift` | `.themed()` (the Summon theme's accent) and `.glassControl()` |
| `Sources/StarterUI/CloseOnlyWindow.swift` | `.closeOnlyWindow()` on Settings: minimize and zoom dimmed, no full screen |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: the launcher and Settings to PNGs, for `summon project shots` |
| `Sources/StarterCore/` | `AppCatalog`, `FuzzyMatch`, `KeyCombo` (reserved shortcuts), `SummonThemeFile`; Foundation only, tested |
| `Resources/` | `Info.plist` (bundle id `local.summon.launcher-starter`, `LSUIElement`), `AppIcon.icns` |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, works without Xcode), plist, bundle |

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app       # then press ⌥Space
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
