# Starter

A floating HUD: a small dark pill that stays above other apps' windows, on every Space and over full-screen
apps, without ever taking the keyboard from the app you are typing in. `LSUIElement`, no Dock icon, a small menu
bar menu that people can hide. Made with Summon from its `hud` template. The starter's job is a stopwatch;
replace it with your own live thing (a recording bar, a meter, a now-playing strip) and keep the panel.

Built to the SummonOS surface rules for a HUD (`docs/ux-surfaces/05-floating-hud.md` in the SummonOS workspace).
Apple's rule first: prefer a standard panel; a HUD is for a few controls over content that must stay visible.

## Behavior

| What | How |
|---|---|
| Level | `.floating`, `.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`, never key: clicks work, keys stay with the frontmost app |
| Stays | `hidesOnDeactivate = false` (an `NSPanel` hides when its app deactivates by default), `.canJoinAllSpaces`, `.fullScreenAuxiliary` |
| Hidden from | Mission Control and ⌘\` (`.transient`, `.ignoresCycle`), the Dock and ⌘Tab (`LSUIElement`) |
| Move | Drag from anywhere and let go: it glides to the nearest corner, carried by the throw. Reduce Motion: it snaps without the throw or the glide |
| Controls | Start/Pause always visible; Reset and Hide fade to 30% until the pointer is over the HUD. All have accessibility labels |
| State | A red dot and border while running, an amber pause mark while paused: a shape and a color, never color alone |
| Numbers | Monospaced digits; the time is computed from dates and redrawn once a second only while running |
| Right-click | Start/Pause, Reset, Opacity (25–100%), Size, Move To (corner), Hide, Settings…, Quit |
| Shortcut | Start or pause from anywhere: none by default, recorded in Settings (`RegisterEventHotKey`, no permission prompt) |
| Settings | Open at Login, Show in menu bar, the shortcut, size, opacity |
| Reopen | Opening the app again from the Finder brings the HUD back and shows Settings |

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the invisible opener window and the `Settings` scene |
| `Sources/StarterUI/HUDPanel.swift` | `HUDPanel` (`NSPanel`), `HUDController` (show, hide, corners, snapping), `HUDDragArea` |
| `Sources/StarterUI/HUDView.swift` | The pill: state mark, elapsed time, buttons, dark glass background |
| `Sources/StarterUI/StarterModel.swift` | The stopwatch, the corner, Settings requests |
| `Sources/StarterUI/AppDelegate.swift` | Creates the HUD, its right-click menu, the menu bar menu and the shortcut |
| `Sources/StarterUI/HotKey.swift`, `ShortcutRecorder.swift` | Global shortcuts (Carbon) and the Settings row that records one |
| `Sources/StarterUI/StatusMenu.swift` | `ActionMenu` (an `NSMenu` built from closures) and the menu bar item |
| `Sources/StarterUI/SettingsOpener.swift` | Opens the Settings window from AppKit code |
| `Sources/StarterUI/SummonTheme.swift`, `Glass.swift` | `.themed()` (the Summon theme's accent) and `.glassControl()` |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: the HUD and Settings to PNGs, for `summon project shots` |
| `Sources/StarterCore/` | `Stopwatch`, `CornerSnap` (throw and corner math), `HUDSize`, `KeyCombo`, `SummonThemeFile`; tested |
| `Resources/` | `Info.plist` (bundle id `local.summon.hud-starter`, `LSUIElement`), `AppIcon.icns` |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, works without Xcode), plist, bundle |

For a live meter or video, draw with Core Animation layers rather than redrawing SwiftUI per sample, and pause
when the panel is covered (`NSWindow.occlusionState`).

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
