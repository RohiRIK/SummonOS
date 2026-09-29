# App shapes

Pick one per surface. Mixing the wrong two (a menu *and* a click handler that opens a window)
is the classic bug.

| Need | Shape | API |
|---|---|---|
| A few commands, toggles, a status line | **Native menu** (HIG default for menu bar extras) | `MenuBarExtra { Button… Toggle… Divider() }` with `.menuBarExtraStyle(.menu)` |
| Live data, lists, text input, rich rows | **Menu-style panel** | `MenuBarExtra { View }.menuBarExtraStyle(.window)`; style it like the system menu (`MacUX/MenuPanel.md`) |
| Programmatic open/close, right-click menu, custom icon view | **Status item + popover/panel** | `NSStatusItem` + `NSPopover(.transient)` or `NSPanel`; wrap SwiftUI in `NSHostingController` |
| Floating HUD / overlay that must not steal focus | **Non-activating panel** | `NSPanel(styleMask: [.nonactivatingPanel, …])`, `level = .floating`, `collectionBehavior` |
| Preferences | **Settings window**, not the panel | `Settings { SettingsView() }` scene; open with `SettingsLink` or `@Environment(\.openSettings)`; ⌘, works |
| Documents, sidebars, long workflows | **Window app** | `WindowGroup` / `Window` + `NavigationSplitView` |

## Rules

- Menu bar only app: `LSUIElement = true` (no Dock icon). A Settings window in such an app needs
  `NSApp.activate()` before opening, or it appears behind other apps.
- `MenuBarExtra(.window)` gives no API to close the panel from code except `dismiss` inside it. If you
  need open/close from elsewhere (hotkey, notification click), use `NSStatusItem` + `NSPopover`.
- Keep in-panel editing small (one screen, a few fields). Anything with sections or many options goes
  to the Settings window. Glaze keeps all app preferences in the Settings window with ⌘, for this reason.
- Let the user choose to show the menu bar item (setting or first-run). Never depend on it being visible:
  the system hides extras when space is short.
- Starting sizes for real windows (from Glaze): utility 420×500, settings/form 520×600, list-detail
  800×650, three-column 1000×700, dashboard 1100×800. Min 390×456. Initial height ≤ 850.

## Launch at login

`SMAppService.mainApp.register()` / `.unregister()`, behind a Settings toggle. Read `.status`
(`.requiresApproval` means the user must allow it in System Settings > General > Login Items).
Do not register in debug builds.
