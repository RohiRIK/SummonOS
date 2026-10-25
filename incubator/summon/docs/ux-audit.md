# Summon against the UX surface table (2026-10-25)

This audit checks each Summon surface against the [surface table](../../../docs/ux-surfaces/surface-table.md) and the
per-surface research in `docs/ux-surfaces/`. Where a research page corrects the table, the page wins.

**Status labels:** **OK** means it matches. **Fixed** means it was fixed in this PR. **Open** means it's a gap that
still needs a change. **By design** means it's a deliberate difference, with the reason given.

| Table column | Summon surface | Code |
|---|---|---|
| 1 Menu bar | `NSStatusItem` + nonactivating `StatusPanel` | `StatusPanel.swift`, `PanelView.swift`, [menubar-panel.md](menubar-panel.md) |
| 2 Desktop app | Activity window | `ActivityView.swift` |
| 3 Settings | `Settings` scene, sidebar + grouped forms | `SettingsView.swift` |
| 4 Launcher | Merged into the menu bar panel (type to search) | `PanelView.swift` |
| 5 HUD | Crash alert (closest fit: small nonactivating panel above other windows) | `CrashAlertView.swift` |
| 6 Onboarding | None | |
| 7 System extensions | None | |

## 1. Menu bar panel

| Dimension | Status | Notes |
|---|---|---|
| Menu or panel | OK | HIG prefers a menu. The panel is justified because it shows live agent state and a searchable tree, which a menu can't hold. |
| Anatomy | OK | Borderless, no traffic lights, drops 4 pt under the icon. |
| Size | OK | 320 pt (`PanelConfig.width`, = `PANEL_W` in visual QA), height follows the content, capped at the screen, not resizable. |
| Focus | By design | Esc closes. Another app becoming frontmost closes it (D4), but clicking back into the app the user came from doesn't (spec decision 2, so the user can copy text into the search). The frontmost app keeps its menu bar (`.nonactivatingPanel`). |
| Materials, icon | OK | Liquid Glass on 26, `.menu` before. Template icon. The orange tint means "needs attention", a real state, and VoiceOver says it too. |
| Typography | OK | System styles for most rows. The search field (14 pt) and the breadcrumb (11–12 pt) use fixed sizes, all at or above the 10 pt minimum. |
| Keyboard | OK | ⌃⌥Space (recordable), ↑↓ → ←, Return, Esc, ⌘, and ⌘Q. |
| Drag & drop | Open (low) | No drop target on the icon. Nothing in Summon takes a dropped file yet. |
| Alerts | OK | Errors show inline. The undo confirmation is an `NSAlert`, but only after the panel closes and `NSApp.activate()` runs, which the research allows for a real confirmation. |
| Context menu | OK | Right-click shows Settings… and Quit, and the footer has the same two. |
| Performance | OK | The 1 s refresh runs only while the panel is open. With the panel closed, a 2 s check of the event log's modification date keeps the icon's live clock current; the research allows polling when the icon itself shows live data. |
| Dock | OK | `LSUIElement`. |
| People decide on the icon | Open | HIG: let people remove the menu bar item. The item isn't `.removalAllowed` and Settings has no "Show in menu bar". The hotkey and `summon panel` already give a second way in. |
| Color alone | Fixed | A menu entry's health dot was color only. VoiceOver now reads its badge. |

## 2. Activity window

| Dimension | Status | Notes |
|---|---|---|
| Anatomy | OK | Standard window, toolbar search and filter, all three traffic lights. |
| Layout | By design | One log list with no sidebar or inspector. The table's split view is for apps with collections to browse; Activity is a single log. |
| Size | By design | Minimum 640 × 420, default 980 × 640. The table's 800 × 550 is a convention for a sidebar plus a canvas, and Activity has no sidebar. |
| Focus, Dock | OK | Becomes `.regular` (Dock and ⌘Tab) while open and goes back to `.accessory` on close. |
| Context menu | OK | Ask, Copy, Diagnose, Show in Finder, Undo on every line, plus ⌘C. |
| Alerts | OK | Undo uses `confirmationDialog` (a sheet on the window). The empty state is a `ContentUnavailableView`. |
| Quick Look | Open (low) | Space doesn't preview a crash report. "Show in Finder" covers it for now. |

## 3. Settings window

| Dimension | Status | Notes |
|---|---|---|
| Anatomy | Fixed | HIG: dim minimize and zoom. They were enabled and Settings could go full screen. Now only close works (`SettingsWindowChrome`). |
| Size | Fixed | Was at least 860 × 560 and freely resizable. Now 780–820 wide (owner's 760–820) and at least 520 tall. |
| Focus | OK | Every opener calls `openSettings()` and then `NSApp.activate()` (`ActivityOpener`). |
| Materials | OK | Grouped forms. There's no app-only Light/Dark picker; Summon's theme changes the whole Mac through macctl, with undo. |
| Controls | OK | Instant apply. Shortcut recorders have Reset. |
| Keyboard | OK | ⌘, plus sidebar search. |
| Permissions | OK | Accessibility shows its status, has an Allow… deep link, and re-checks every 2 s while off. Automation is asked for the first time a browser or Finder script runs, which is what HIG Privacy wants. |
| Notifications prompt | By design | It's asked at launch. HIG asks to wait unless the app needs it, and Summon does: task results (on by default) need banners. |
| Export/import | Open (low) | None. |
| Dock policy toggle | Open (low) | No "menu bar / Dock / both" choice. Activity already puts Summon in the Dock while it's open. |

## 4. Launcher

| Dimension | Status | Notes |
|---|---|---|
| Separate launcher | By design | The launcher was merged into the menu bar panel (PR #61, 2026-10-21): one place to type, under the icon. So its width is the panel's 320 pt, not the table's 600–750. |
| Hotkey | OK | ⌃⌥Space, not ⌘Space (reserved for Spotlight), and recordable. Uses Carbon `RegisterEventHotKey`, so there's no permission prompt. |
| Over full-screen apps | OK (Mac check 9) | `.statusBar` level, `[.canJoinAllSpaces, .fullScreenAuxiliary]`. |
| Pre-warmed | OK | The panel is made at launch and shown with `makeKeyAndOrderFront`. B1 signposts measure the open (200 ms budget). |
| ⌘K actions, ⌘1–9 | Open (low) | Rows have one action each. |

## 5. Crash alert (HUD)

| Dimension | Status | Notes |
|---|---|---|
| Focus | OK (Mac check 5) | Nonactivating, `hidesOnDeactivate = false`, takes key only when clicked. |
| Mission Control, ⌘` | Fixed | It now has `.transient` and `.ignoresCycle` and is left out of the Window menu, like the panel. |
| Size | By design | 440 pt. It's an alert with a title, a frame and two actions, not an ambient HUD, so the HUD's 120–320 pt doesn't apply. |
| Motion | OK | 0.15 s fade-out, which is still fine with Reduce Motion on. |

## 6. Onboarding

**Open.** There's no first-run flow. A first launch shows only an icon in the menu bar. Per the research, a short
wizard is worth it for an `LSUIElement` app that needs setup. For Summon, that means:

1. Choose the default agent (and offer to install one).
2. Accessibility, explained first, with a live check.
3. Show the ⌃⌥Space hotkey and point at the menu bar icon.

This is a product change, so it waits for the owner's decision.

## 7. System extensions

No widget, notch view or Finder Quick Action. Nothing in Summon needs one today.
