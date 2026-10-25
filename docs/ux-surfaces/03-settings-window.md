---
type: Research
title: "Surface 3: Settings window"
description: "The app's Settings window, checked cell by cell against the HIG and SwiftUI docs, with three corrections to the table."
tags: [design, ux, surfaces, settings]
created: 2026-10-25
---

# Surface 3: Settings window (`Settings` scene)

Column 3 of the [surface table](surface-table.md), checked 2026-10-25. Verdicts as in
[Surface 1](01-menu-bar.md#surface-1-menu-bar-app-menubarextra--popover). Our standing rule still applies: every
preference lives here, never in the menu bar panel ([AGENTS.md](../../AGENTS.md#panel-vs-settings-window-user-preference)).

## Three corrections

1. **Minimize off too, not only full screen.** HIG Settings: "**Dim a settings window's minimize and maximize
   buttons.** It's quick to open a custom settings window using … Command–Comma, so there's no need to keep
   the window in the Dock." The table keeps Minimize enabled.
2. **No Light/Dark/System override.** HIG Dark Mode: "**Avoid offering an app-specific appearance setting.**"
   HIG Settings also says not to duplicate systemwide settings. Drop the appearance picker. (Summon's
   *whole-Mac* theme is different: it changes the system, through macctl, with undo.)
3. **Width: our owner's preference beats the table.** Apple publishes no width. The HIG says the window
   "accommodates the size of the current pane", which is the SwiftUI default (`Settings` uses `contentSize`
   resizability). Rohi asked for 760–820 pt with a sidebar (2026-09-30, `MacUX/MenuPanel.md`), wider than the
   table's 680. Toolbar-tab Settings size each pane to its content, typically 500–600 pt.

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | Set & forget; clarity over flair | **Apple** | HIG: few settings, good defaults, infrequent options only; task options stay in the task's own UI. |
| Window anatomy | Title bar, close + minimize, no full screen; top icon tabs or sidebar + grouped form | **Fix** (minimize) | Close only. HIG names the toolbar of panes as the standard ("a toolbar that includes buttons for switching between views — called panes"), noncustomizable, always showing the active pane; window title = the current pane's name (or "*App* Settings" if there is one pane); reopen on the last pane. A sidebar is fine for many sections (System Settings does it); keep it noncustomizable too. |
| Sizing | 480–600 (tabs) or 680 (sidebar), height animates per tab | **Convention** → see correction 3 | `Settings` uses `.contentSize` by default; animate height between panes. Sidebar: 760–820 × min 520. |
| Focus | `NSApp.activate()` when opened from the menu bar; ⌘W closes Settings only | **Apple** + **Convention** | `NSApp.activate()` (macOS 14) asks for activation; it "doesn't guarantee" it. From an `LSUIElement` app, `SettingsLink` and `openSettings` need care: see [mechanics 3.4](../research/2026-10-18-mac-gui-design/03-menubar-and-window-mechanics.md). |
| Materials | Neutral background, elevated cards, Light/Dark/System override | **Apple** / **Fix** (override) | `Form` + `.formStyle(.grouped)` gives the system look. No appearance override (correction 2). |
| Typography | Labels 13, group headers 12 semibold, footnotes 11 secondary | **Apple** (close) | Let `Form` set it: rows at body (13), section headers and footers at system sizes. Don't hard-code. |
| Controls | Toggles, checkboxes, pop-ups, steppers, shortcut recorder; no Save (instant apply) | **Apple** (convention Apple follows) | Instant apply through `@AppStorage`. A shortcut recorder has no system control; build one or use a small vetted view. |
| Keyboard | ⌘, opens; Tab cycles; optional sidebar search | **Apple** | HIG Settings and Keyboards: ⌘, opens the app's settings. Settings item belongs in the App menu, never a toolbar button in other windows. |
| Drag & drop | Drop JSON backups, license files, icons onto wells | **Convention** | Only if the app has those things. |
| Audio/video | Device pickers, live level meter, resolution/FPS/codec, output folder | **Convention** | For media apps only. Stop the meter when the pane is hidden. |
| Permissions | Permissions list with status dots and deep links to System Settings | **Convention** (strong) | No public API lists every privacy pane URL; use the documented checks (`AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, `AVCaptureDevice.authorizationStatus`) for status, and refresh when the app becomes active. Color plus text (HIG: never color alone). |
| Context menu | Reset to defaults per section; export/import | **Convention** | Reasonable; confirm reset only if it can't be undone. |
| Motion | Height morph 200 ms between tabs | **Convention** | What `contentSize` Settings already do; keep it, respect Reduce Motion. |
| Performance | Free the view tree on close | **Apple** (default) | SwiftUI tears the scene's content down on close; just don't hold the view model in a global. |
| Dock | Houses the activation-policy toggle (menu bar only / Dock / both) | **Convention** | `setActivationPolicy(_:)` can switch at runtime; never call it in `App.init()` (`NSApp` is nil). After `.regular` the app needs a real App menu. |

## Sources

- HIG: [Settings](https://developer.apple.com/design/human-interface-guidelines/settings) (macOS section), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- API: [`Settings`](https://developer.apple.com/documentation/swiftui/settings), [`windowResizability(_:)`](https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)) ("Settings windows use the contentSize strategy"), [`SettingsLink`](https://developer.apple.com/documentation/swiftui/settingslink), [`OpenSettingsAction`](https://developer.apple.com/documentation/swiftui/opensettingsaction), [`NSApplication.activate()`](https://developer.apple.com/documentation/appkit/nsapplication/activate()), [`setActivationPolicy(_:)`](https://developer.apple.com/documentation/appkit/nsapplication/setactivationpolicy(_:)), [`CGPreflightScreenCaptureAccess()`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())
