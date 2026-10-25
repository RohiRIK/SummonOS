# Starter

A menu bar app whose item is an `NSStatusItem` plus a nonactivating `NSPanel` instead of `MenuBarExtra`,
`LSUIElement`, no Dock icon. Made with Summon from its `menubar-panel` template. Same rules as the `menubar`
template: the app's job in the panel, `Settings…` and `Quit` in the footer, every preference in a separate
Settings window, a tested Core.

## Which menu bar template?

Stay on `menubar` (`MenuBarExtra(.window)`) when the panel is opened only by clicking and its content is simple.
Take this one when the app needs any of these:

| Need | Why `MenuBarExtra` can't | How this template does it |
|---|---|---|
| Open from a hotkey, URL or CLI | No API to open or close it from code | `PanelController.open()`, `close()`, `toggle()` |
| Typing while another app stays frontmost | Keystrokes need the app active, which takes the other app's menu bar | `.nonactivatingPanel` + `canBecomeKey`: the panel is key, the app is not active |
| Over fullscreen apps, on every Space | No control over the window | `.statusBar` level, `.fullScreenAuxiliary`, `.canJoinAllSpaces` |
| A live label (text, number, monospaced) | The label is re-rendered as an image with limited updates | `PanelController.setLabel(title:accessibilityLabel:)` on the status button |

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the invisible opener window and the `Settings` scene |
| `Sources/StarterUI/StatusPanel.swift` | `StatusPanel` (`NSPanel`), `PanelController`, `SettingsOpener` |
| `Sources/StarterUI/AppDelegate.swift` | Creates the controller; keeps the label live with `withObservationTracking` |
| `Sources/StarterUI/PanelView.swift` | The panel: a live-data tile, one command per row, the footer |
| `Sources/StarterUI/Components.swift` | Menu rows with hover and key hints, the module tile, headers, dividers |
| `Sources/StarterUI/SummonTheme.swift` | `.themed()`: the Summon theme's accent on every window root, live |
| `Sources/StarterUI/Glass.swift` | `.glassControl()`: Liquid Glass on macOS 26, a material on 15; controls only |
| `Sources/StarterUI/SettingsView.swift` | Settings window: Open at Login (`SMAppService`), the menu bar toggle |
| `Sources/StarterUI/Onboarding.swift` | The first-run window: steps, permission cards with live status |
| `Sources/StarterUI/CloseOnlyWindow.swift` | `.closeOnlyWindow()`: dims minimize and zoom, no full screen (Settings, setup) |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: the panel to PNGs, used by `summon project shots` |
| `Sources/StarterCore/` | Logic, Foundation only, tested (`SummonThemeFile` reads the theme) |
| `Resources/` | `Info.plist` (bundle id `local.summon.menubar-panel-starter`, `LSUIElement`), `AppIcon.icns` |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, works without Xcode), plist, bundle |

## Behavior

- **Opens** on a click on the icon, or from code.
- **Closes** on Esc, on a click anywhere else (the panel loses key), and on a Space change.
- **Settings…** closes the panel and opens the Settings window. SwiftUI's `openSettings` only works inside a
  scene, so the request goes through `SettingsOpener` in an invisible, always-open window.
- **Keys** while open: Return adds one, ⌘, opens Settings, ⌘Q quits, Esc closes.
- **Right-click** (or ⌃-click) the icon: a plain menu with Settings… and Quit.
- **Show in menu bar** (Settings): people decide whether the icon is there. Hidden, the app is reachable from code
  and by opening it again in the Finder, which shows Settings.
- **First run:** a 640 × 440 welcome window (`Onboarding.swift`) ends by pointing at the menu bar icon. The app shows
  in the Dock only while it is open. Closing it skips it; Settings › Welcome shows it again. Add a permission card
  only for a permission the app can't work without (`StarterOnboarding.permissions`, empty by default).
- **Settings** window: close only (minimize and zoom dimmed), 480 pt, changes apply at once.

To add a global hotkey, register it with Carbon's `RegisterEventHotKey` (no Accessibility permission needed) and
call `panel.toggle()`.

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
