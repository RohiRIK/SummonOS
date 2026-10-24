# Starter

`menubar-panel-starter`: the menubar-starter counter, but the menu bar item is an
`NSStatusItem` plus a nonactivating `NSPanel` instead of `MenuBarExtra`. Same rules: the app's job in the panel,
`Settings…` and `Quit` in the footer, every preference in a separate Settings window, a tested Core.

Start a plugin from it with `tools/mp new <name> --panel`.

## Which starter?

Stay on `menubar-starter` (`MenuBarExtra(.window)`) when the panel is opened only by clicking and its content is
simple. Take this one when the app needs any of these:

| Need | Why `MenuBarExtra` can't | How this starter does it |
|---|---|---|
| Open from a hotkey, URL or CLI | No API to open or close it from code | `PanelController.open()`, `close()`, `toggle()` |
| Typing while another app stays frontmost | Keystrokes need the app active, which takes the other app's menu bar | `.nonactivatingPanel` + `canBecomeKey`: the panel is key, the app is not active |
| Over fullscreen apps, on every Space | No control over the window | `.statusBar` level, `.fullScreenAuxiliary`, `.canJoinAllSpaces` |
| A live label (text, number, monospaced) | The label is re-rendered as an image with limited updates | `PanelController.setLabel(title:accessibilityLabel:)` on the status button |

The full comparison and its sources: `docs/research/2026-10-18-mac-gui-design/03-menubar-and-window-mechanics.md`.
Summon's panel (`incubator/summon/Sources/SummonMenuUI/StatusPanel.swift`) is the full version: global hotkey,
URL opens, right-click menu, focus handed back to the previous app, top edge pinned while the content resizes.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the invisible opener window and the `Settings` scene |
| `Sources/StarterUI/StatusPanel.swift` | `StatusPanel` (`NSPanel`), `PanelController`, `SettingsOpener` |
| `Sources/StarterUI/AppDelegate.swift` | Creates the controller; keeps the label live with `withObservationTracking` |
| `Sources/StarterUI/` | Views, the `@Observable` model, `#Preview`s (library product, so previews run) |
| `Sources/StarterCore/` | Logic, Foundation only, tested |
| `Tests/StarterCoreTests/` | swift-testing |
| `Resources/Info.plist` | Bundle id `local.macplugins.menubar-panel-starter`, `LSUIElement` |

## Behavior

- **Opens** on a click on the icon, or from code.
- **Closes** on Esc, on a click anywhere else (the panel loses key), and on a Space change.
- **Settings…** closes the panel and opens the Settings window. SwiftUI's `openSettings` only works inside a
  scene, so the request goes through `SettingsOpener` in an invisible, always-open window.
- **Keys** while open: Return adds one, ⌘, opens Settings, ⌘Q quits, Esc closes.

To add a global hotkey, register it with Carbon's `RegisterEventHotKey` (no Accessibility permission needed) and
call `panel.toggle()`; Summon's `HotKeyCenter.swift` is a copyable example.

## Build

```bash
swift build --scratch-path ~/Library/Caches/macplugins/menubar-panel-starter
swift test --scratch-path ~/Library/Caches/macplugins/menubar-panel-starter
```

Requires macOS 15+ and Swift 6. Bundling, previews and the check gate: `MacAppBuild/Scaffold.md` and
`MacAppBuild/Verify.md` (copy `scripts/` from mac-network).
