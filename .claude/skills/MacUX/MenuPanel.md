# Menu bar panel: look like the system menu

The bar for any menu bar extra: it should be indistinguishable in style from the system
Wi-Fi / Bluetooth / Control Center menus. Reference implementation:
`plugins/mac-network/Sources/MacNetworkUI/` (`Components.swift`, `MainScreen.swift`, `SettingsScreen.swift`).

## HIG rules (from the menu bar, menus, materials pages)

- "Display a menu — not a popover — when people click your menu bar extra." Use
  `MenuBarExtra { } .menuBarExtraStyle(.menu)` when every action is a command. Use `.window`
  only for text input, live data, or lists, and then make it look like a menu.
- Menu bar icon: SF Symbol or template image; the menu bar is 24 pt high.
- Ellipsis (…) on any command that needs more input before it completes
  ("IP Settings…", "Apply…" when a password prompt follows, "Forget This Network…").
- Liquid Glass is for the control/navigation layer only. **Never put glass on content**
  (cards, lists, detail blocks). Standard materials in the content layer; the panel window
  already has the system material.
- Label menu items with verbs or nouns in title case; show the key equivalent at the trailing
  edge in tertiary color.

## Anatomy of the system Wi-Fi menu (what to copy)

```
Wi-Fi                                   [switch]    <- .headline title + small switch
(●) Harbor                                  🔒      <- current: 26 pt circle, accent fill, white glyph
    5 GHz                                           <- .subheadline secondary under the name
    IP address   192.0.2.24                         <- Option-click style details, indented to
    Router       192.0.2.1                             the text column (42 pt), .subheadline
Known Networks                                      <- section header .subheadline semibold secondary
(○) Office                                  🔒      <- other rows: circle with .quaternary fill
Other Networks                               ›      <- collapsible, chevron rotates 90°
───────────────────────────────────────────         <- Divider inset 8 pt
IP Settings…                                 S      <- command rows, key hint in .tertiary
Wi-Fi Settings…                                     <- opens System Settings pane
```

Measurements: panel width 300-320, outer padding 6, row horizontal padding 8, row min height 24
(network rows ~32 with the 26 pt icon), hover highlight `RoundedRectangle(cornerRadius: 6).fill(.quaternary)`,
no borders, no cards, no grouped boxes.

## Settings / edit screens inside the panel

- Header row: `chevron.left` + `.headline` title, the whole row is the back button (Esc too).
- Label/value `Grid`: labels trailing-aligned, `.secondary`; values are small controls
  (`.controlSize(.small)`, `.roundedBorder` fields, pop-up `Picker` with `.fixedSize()`).
- Use System Settings wording for the same setting (e.g. "Configure IPv4: Using DHCP / Manually",
  "Subnet mask", "DNS servers"). Users already know those words.
- Bottom row: `Cancel` + default-action button, trailing, small. No explanatory footer text;
  put that in `.help()` on the button.
- **No `Form`** in a `.window` menu bar extra: a grouped Form is a scroll view with no ideal
  height and gets clipped ("the tab is cut off"). Use `VStack` + `Grid`.
- Segmented controls for a two-way setting look like Windows-era toolbars here; prefer a
  pop-up (`Picker` default style) as System Settings does.

## Feedback

- Errors for a row appear under that row (red `.subheadline`, indented to the text column),
  not in a banner at the top where they are off-screen.
- Progress for a row: `ProgressView().controlSize(.mini)` at the trailing edge of that row.

## Live-data module (Control Center style)

User feedback: plain rows for live data looked unfinished; they wanted "nice, clean" with a background.
The fix that landed (`plugins/mac-network/Sources/MacNetworkUI/ConnectionModule.swift`):

- One rounded tile per current object: `.background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))`,
  padding 12. A standard fill, not glass, no border, no shadow. This is a Control Center module, not a web card.
- Header: 32 pt accent circle icon, name `.body.weight(.semibold)`, one `.subheadline` secondary line
  joining facts with " · " (band · rate · dBm).
- Live numbers in a 2×2 `Grid` of stat cells: caption + symbol on top, value `.callout.weight(.semibold)`
  `.monospacedDigit()` below, cell fill `.quinary` radius 8 (stacks lighter on the tile).
  Optional 6 pt health dot (green/orange/red) with the meaning also in `accessibilityValue`.
- Static facts (addresses) below the grid as label-left / value-right rows, `.subheadline`.
- Permission banner: tinted tile (`.tint.opacity(0.08)`), 28 pt tinted circle icon, title + one-line
  reason, trailing `.borderedProminent` small button. Button text changes to "Settings…" once macOS
  will no longer prompt.

## Everything in the panel, split into tabs (from CodexBar)

User preference (2026-09-29): keep all features inside the menu bar panel; no extra windows. **App settings
(Open at Login, theme, permissions, any toggle) are the exception: they always go in a separate Settings
window (⌘,), never as rows in the panel** (see AGENTS.md › Panel vs Settings window). A separate
IP Settings window was built and rejected. CodexBar (github.com/steipete/CodexBar, MIT, installed at
/Applications/CodexBar.app) solves the same problem with a switcher at the top of its menu. We copied it:

- `TabSwitcher`: equal-width segments, SF Symbol (fixed 16 pt frame so labels align) above a `.caption`
  title; selected = `.tint` fill + white, others = secondary text + `.quaternary` hover; radius 8, min height 44.
- One tab per job: Overview (live module) · Wi-Fi (list + switch) · IP Settings (editing). Shared footer
  (settings link, Open at Login, Quit) under every tab. Keys 1-3 switch tabs.
- Editing inside a tab: `SettingsGroup` (section title + `.quinary` rounded group) with `SettingsRow`
  (`SettingsRowLabel` title + subtitle left, control right) and `RowDivider`. Looks like a grouped Form but
  sizes to content; a real `Form` clips in the panel.
- Fields: `.textFieldStyle(.plain)`, trailing aligned, `maxWidth` ~140. Read-only values as secondary
  text, never disabled fields. Pop-ups `.labelsHidden()` with a `maxWidth` so long names cannot overflow.
- Footer of an editing tab: status left, `Revert` + `.borderedProminent` `Apply…` right, enabled only when dirty.
- Reference: `plugins/mac-network/Sources/MacNetworkUI/` (`Components.swift`, `PanelTabs.swift`, `IPSettingsTab.swift`).

## App settings and onboarding (user-requested, CodexBar style)

The panel is for the app's job; the app's own settings get a real window. Refines the rule above:
network features stay in panel tabs; permissions, login item, and theme live in Settings.

- Panel footer: only `Settings…` (⌘,) and `Quit` (⌘Q). No toggles in the footer.
- `Settings { SettingsView(model:) }` with a `TabView` (General · Permissions · Appearance), each pane
  built from `SettingsGroup` / `SettingsRow`. Open from the panel with `dismiss()`,
  `NSApp.activate()`, `openSettings()`, or it opens behind other apps.
- **Settings window size (user, 2026-09-30: 440–460 pt "so tiny"): 580 pt wide**, so row descriptions fit
  on one line. One grouped `Form` with many sections: `.frame(minWidth: 580, minHeight: 640)`, no
  `.fixedSize`. The Form scrolls; a content-sized Form grows past the screen as sections are added. The
  Settings window opens at its *minimum* size (ideal sizes are ignored), so the minimum is the default.
  Short `TabView` panes: `.frame(width: 580)` + `.fixedSize(horizontal: false, vertical: true)` is fine.
  Reference: `plugins/mac-calendar/Sources/MacCalendarUI/SettingsView.swift`.
- Onboarding: `Window(id:)` with `.defaultLaunchBehavior(onboarded ? .suppressed : .presented)`
  (macOS 15+) and `@AppStorage("onboarded")`; app icon tile, one-sentence why, permission rows, Continue.
  Reopen from Settings › General. `NSApp.activate()` in `onAppear`.
- Permission rows are shared views used by both onboarding and Settings, so they never drift. Each shows
  live status and the single action that changes it (Allow → Open Settings… → ✓ Allowed).
  Needs an observable permission source (`@Observable` `LocationAccess`).
- Themes: `@AppStorage` theme (System/Light/Dark) + accent (system or a named color), applied with one
  `.themed(theme, accent)` modifier (`preferredColorScheme` + `tint`) on every window root, panel included.
  Accent picker = round swatches like System Settings.
- Reference: `plugins/mac-network/Sources/MacNetworkUI/SettingsWindow.swift`, `Preferences.swift`.
