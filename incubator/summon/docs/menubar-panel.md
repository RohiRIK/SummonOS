---
type: Reference
title: Summon menu bar panel
description: Current native panel, search, focus, lifecycle and evidence contract, with outstanding macOS acceptance checks.
tags: [summon, macos, panel, keyboard, accessibility, lifecycle]
---

# Menu bar panel: NSStatusItem + nonactivating panel

Summon's menu bar item is an `NSStatusItem` plus a `StatusPanel` (`NSPanel`), owned by one `PanelController`
(`Sources/SummonMenuUI/StatusPanel.swift`). It replaces `MenuBarExtra`.

The panel:
- takes typing without activating Summon;
- holds the Summon Menu (the former launcher);
- opens from ⌃⌥Space, the CLI and URLs;
- keeps updating while open;
- closes only on the triggers listed below.

This reference reflects source through `18c7688` (2026-11-11). November runtime/inventory/accent changes are
implemented on the branch after the numbered `v0.2.4` baseline; this is not a new release announcement.
Interaction IDs (A1–G3) come from the original v1.5 spec. Current decisions live in
`Sources/SummonCore/PanelLogic.swift` and the controller/view; test coverage does not substitute for native
accessibility or performance acceptance. See [the UX audit](ux-audit.md) for cross-surface status.

## Shape

- **Style mask** `[.nonactivatingPanel, .borderless, .fullSizeContentView]`, set at init.
  - `canBecomeKey = true`, `canBecomeMain = false`, `hidesOnDeactivate = false`.
  - Collection behavior: `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`.
- **Level** is `PanelConfig.level` (`.statusBar`) for every Summon panel, the crash alert included.
- **Content** is one SwiftUI view (`PanelView`) in an `NSHostingController` with `sizingOptions = []`. The view
  reports its displayed height, and `PanelController` sets the window frame itself in a single `setFrame` with the
  top edge pinned. The hosting controller's own resize would keep the bottom-left origin and move the top for a frame.
  From top to bottom:
  - Summon mark/title, selected-agent state (or agent picker), and an update-count button when updates exist;
  - an always-visible search field and breadcrumb back button in submenus;
  - home actions Ask Agent, Make Something and My Apps, optional setup-attention and Undo rows;
  - footer with Activity…, Settings… (⌘,) and Quit Summon (⌘Q).
  There is no separate launcher window, Now/Recent feed, crash list or active-theme pill in the header.
  Preferences belong in the separate Settings window; history belongs in Activity. The Update entry and
  update-count button close the panel and open the separate Updates window.
- **Size and position.**
  - The panel is as tall as its content, capped at the visible screen height minus 8 pt at top and bottom; past that it scrolls.
  - The top edge sits 4 pt under the icon and stays there on resize.
  - Left and right are clamped 8 pt inside `visibleFrame`.
  - With the hotkey, the panel goes under the item on the pointer's display. If that display has no item, it goes
    under the main display's item, mapped to the same distance from the right edge.
- **Live updates.** The panel and Activity share one `ActivityModel` refresh owner. Opening starts panel interest
  and acknowledges only a published refresh generation; actual close ends that interest. Source collection runs
  off the main actor, filesystem changes mark it dirty, and a 60 s reconciliation with 15 s tolerance recovers
  missed notifications. No panel-specific one-second disk reload remains. The header uses coarse running state
  (for example “running 3h”), not a continuously redrawn stopwatch. Cancelled or stale guard/refresh results do
  not publish over a newer query/session. These are source behavior, not a measured frame-time guarantee.

## Status item label

- **Icon only** by default. When enabled in Settings, an open agent session (a `session.start` without a later
  end, under 12 h old) adds elapsed `mm:ss` in monospaced digits.
- `MenuBarStatusWatcher` watches both the event file and its containing/nearest existing directory, so creation
  and replacement rearm the file watch. Its cursor consumes appended records by file position, not timestamp;
  a bounded identity ledger suppresses repeated delivery after reset. One-second ticks run only for a displayed
  session clock; otherwise a 60 s reconciliation backs up filesystem notifications.
- **Setting:** Settings › General › Menu Bar › Show agent time in the menu bar
  (`summon.menuBar.showsAgentTime`, **off by default**).
- **VoiceOver (G3):** the item's label is `Summon`, or `Summon, Claude running for 4 minutes` while a session is
  open, with the time setting on or off (`MenuBarStatus.accessibilityLabel`).

## VoiceOver on open

A click moves the VoiceOver cursor to the status item, so it's silent. A hotkey or URL/CLI open doesn't move the
cursor: the panel is nonactivating, so VoiceOver stays in the other app. Those opens post an
`announcementRequested` notification at high priority (`PanelOpenGuard.announcement`): "Summon menu. Type to
search." after ⌃⌥Space, "Summon menu opened." after a URL or CLI open (no search focus there).

## Keys in the panel

| Key | Does |
|---|---|
| Typing | Searches the whole Summon Menu |
| ↑ ↓ | Move the selection |
| → / Return on a non-runnable submenu | Open it |
| ← / Delete with an empty query | Go up one level; breadcrumb click also goes back |
| Return on an action | Run the entry and close (D3); Update opens its window |
| Esc in a submenu | Go back one level; at the root, close (D1) |
| ⌥Return (default, recordable) | Ask the default agent about current screen context and close |
| ⌘, / ⌘Q | Settings… / Quit Summon (footer) |

## Opening

| From | How |
|---|---|
| Status item | `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`. `NSApp.currentEvent` tells a left click from a right click or ⌃-click. |
| ⌃⌥Space | `SummonHotKey.menuID` with presses and releases, so a held key opens once (C3). |
| Code | `PanelController.open()`, `open(at:)`, `close()`, `toggle()`. These are main-actor and idempotent. `requestOpen()` / `requestClose()` work from any thread (C7). |
| URL | `open -g summon://panel`, `open -g summon://panel/close`, `summon://menu/<id>` (opens at that entry) |
| CLI | `summon panel`, `summon panel --close`, `summon menu summon <id>` (all use `open -g`) |

**Stray typing (`PanelOpenGuard`).** A hotkey or URL/CLI open can land while the user is typing in another app:

- URL and CLI opens make the panel key but don't focus the search field. Click to type, or press Esc.
- Return (and → on a submenu row) is ignored for 300 ms after any non-click open (hotkey, URL, CLI), so a keystroke
  meant for another app can't run an entry's shell action. Clicking a row always works.
- Click and ⌃⌥Space opens focus the search field (A1).

**Cold launch.** A `summon://` URL that launches Summon can arrive before `applicationDidFinishLaunching` made the
panel. `AppDelegate` queues it (`LaunchURLQueue`) and replays it once the panel exists, so `open -g 'summon://menu/<id>'` on a quit
Summon opens the panel at that entry.

The right-click (or ⌃-click) menu has exactly **Settings… ⌘,** and **Quit Summon ⌘Q**. If the panel is open, it
closes first.

## Closing (spec section D, nothing else)

| ID | Trigger | Source |
|---|---|---|
| D1 | Esc at the root; submenu search handles Esc as Back | `StatusPanel.cancelOperation`, search-field key handling |
| D2 | Icon or ⌃⌥Space while open | toggle |
| D3 | An action ran or a separate workflow window was requested | menu entries and rows call `PanelActions.finish` |
| D4 | Another app becomes frontmost | `NSWorkspace.didActivateApplicationNotification`. The previous app and Summon itself are ignored (decision 2). |
| D5 | Space change | `NSWorkspace.activeSpaceDidChangeNotification` |
| D6 | Settings… or Quit | footer or right-click menu |
| D7 | Lock, display sleep, system sleep, user switch | `com.apple.screenIsLocked` (distributed), `screensDidSleep`, `willSleep`, `sessionDidResignActive` |
| D12 | The crash alert appears | `CrashAlertController.onWillPresent` → `PanelController.yieldToCrashAlert()`. The panel closes first, then the alert orders front **without** taking key (a background crash must not catch the Return key typed into another app); a click makes it key. |

- There's no global click monitor, and the panel doesn't close on `didResignKey`.
- Every close removes all its observers and clears the highlight.
- Focus goes back to the previous app. The panel never activated Summon, so ordering it out hands key focus back.
  If Summon did become frontmost in the meantime, the previous app is activated again.
- An app switch, a Space change, Settings, Quit, a lock or the crash alert (D12) leaves focus where the user,
  macOS or the alert put it.
- The panel never pastes (decision 1).

## Proof hooks

All of these use `Logger`/`OSSignposter` with subsystem `local.macplugins.summon` and category `panel`, at notice
level. To watch them: `log stream --predicate 'subsystem == "local.macplugins.summon" AND category == "panel"'`.

- **B1:**
  - A `PanelOpen` `os_signpost` interval runs from the status item's mouse-down to just after `makeKeyAndOrderFront` (ends "no open" if that press closed the panel or showed the menu).
  - A local `leftMouseDown` monitor, which only sees Summon's own events and never closes anything, records the
    status item's mouse-down.
  - The log line `B1 panel ordered front N ms after mouse-down (within|OVER the 200 ms budget)` measures from that
    mouse-down (`PanelTiming`, budget 200 ms warm).
- **D rules:** every close logs `panel closed (<reason>); active monitors: before N, after 0`. `before` is what that
  open installed (7 normally) and `after` must be 0. D12 logs the reason `crashAlert`.
- **A1/A2/G1 focus:** for click and hotkey opens, the search field is focused one run-loop turn after
  `makeKeyAndOrderFront` (`PanelState.focusRequest`), because focus set before the window is key is dropped. URL/CLI
  opens don't request focus.

## Inventory, theme and lifecycle ownership

My Apps uses the same six categories as Settings, including empty ones: Panel Apps, Themes, Art & Wallpapers,
Window Apps, Command-Line Tools and Screensavers. All built-in/custom themes stay visible. Theme/art entries
cannot be dispatched as projects just because their name matches an app. Shared `AppInventoryHealth` counts
repairable items once and keeps readability/palette/optional-art recommendations outside repair totals.
The My Apps repair action runs `summon fix --apps`, not general Mac diagnosis.

The active palette drives panel control tint through `ThemeAccent.swift`. Style and My Apps theme actions and
checkmarks read one observed active selection. Appearance preview does not apply a theme; Apply Theme does.
The header deliberately has no active-theme chip. Finder's Automatic folder tint follows macctl's system accent
refresh, while explicit folder colors remain unchanged; some running clients may still need reopening.

`AppDelegate.applicationWillTerminate` cancels startup work, stops menu/status/model/activity owners, removes
the panel's monitors/observers, unregisters hotkeys and removes URL handling. A persistent hosting view or
watcher is intentional ownership, not evidence by itself of a leak. About is a separate native standard panel,
reachable from Settings › General and the standard About command; its cold-launch path explicitly unhides and
raises AppKit's singleton. About does not check the network or updater when opened.

## Evidence and outstanding Mac checks

Recorded evidence is in the
[runtime audit continuation](../../../docs/plans/2026-11-08-runtime-audit.md#native-acceptance-continuation-2026-11-10),
not a blanket claim that every rule below has passed on every supported OS. The documentation refresh itself
does not run native checks.

- Hosted evidence includes native About metadata/keyboard close, Activity terminal-event delivery and 100 panel
  search cycles with actual query-value readback. A later workload completed 500 cycles, including profiler
  workloads. Recorder failures still prevented full profiling acceptance.
- Native macOS 27.2 evidence exercised 13 equal-timestamp crash reports through the real watcher across its
  five-file batches. The alert showed the newest report and “12 more new reports”; native Dismiss and subsequent
  typed panel search succeeded. This does **not** verify macOS banners, VoiceOver or all crash/focus scenarios.
- One cold-launch attempt had no observable About window; the current branch adds explicit native raising.
  The source fix is not itself proof that every cold-launch/window-server scenario now passes.
- `PanelOpen` ends at ordered-front; `PanelWindowUpdate` ends in AppKit's pre-display update pass. Neither is
  a displayed/composited frame. Isolated comparative GUI profiling, SwiftUI recorder content/completion,
  displayed-frame timing and retained-memory analysis remain acceptance gates. Live malloc samples, RSS and
  retained-graph leak analysis are distinct; absent samples or an empty trace cannot pass.

Remaining/manual scenarios include:

1. **VoiceOver:** hotkey/URL announcements, status-item running label, health/recommendation badges, native About
   fields, search/results and all primary actions. Accessible names in source are not navigation proof.
2. **Keyboard navigation:** ⌃F8 status-menu access and Full Keyboard Access, configurable shortcuts, submenu
   Esc/Delete/Back behavior, and macOS 27 menu-bar keyboard-navigation preference behavior.
3. **Focus safety:** type in another app while opening by hotkey/URL; Return must not run a stray action during
   the 300 ms guard. Clicking back into the previous app keeps the panel open; switching to a third app closes
   it. Repeat during source invalidation and close/reopen without dropped or duplicated input.
4. **Crash and notifications:** a background alert must not steal typing/Return; after an intentional click,
   keyboard actions work. Verify native macOS banners, sound/grouping and task Show Log/Ask Agent actions,
   both with the app running and with CLI fallback. The 13-report Summon-alert result covers only that path.
5. **Appearance:** light/dark, Reduce Transparency, contrast/readability findings and explicit versus Automatic
   Finder folder colors. About content renders do not prove installed-window capture or VoiceOver.
6. **Screens/windows:** full-screen apps, multiple displays/Spaces, lock/sleep/user switching, panel height cap
   and pinned top edge. Settings remains close-only and 780–820 pt wide. Native About should be visible/key
   from cold launch, reopen the same window and return to accessory policy when regular windows close.
7. **Welcome:** four steps at 720 × 480; optional Accessibility; first-run/skip/reopen semantics; ready-step icon
   visibility warning and Try It Now. Settings › General › Show Welcome Again and `summon://welcome` reopen it.


## Deployment floor

- **Minimum macOS 15:** `Package.swift` `.macOS(.v15)`, `Info.plist` `LSMinimumSystemVersion 15.0`.
- The core panel mechanics below are available on macOS 15; newer styling is availability-gated:
  - nonactivating `NSPanel`, `.statusBar`, `.fullScreenAuxiliary`, `.transient`, `.ignoresCycle`;
  - `NSRunningApplication.activate()` (14);
  - `NSHostingController.sizingOptions` (13);
  - `OSSignposter` (12);
  - `onKeyPress` (14);
  - `onGeometryChange` (back-deployed);
  - `TimelineView` (12).
- Hosted native About/visual evidence exists on macOS 15 and 26; macOS 27.2 native evidence covers the specific
  scenarios above. This is not a full runtime/accessibility certification of any OS version.
- Menu bar highlight behavior can vary on newer macOS; verify the visible highlight natively rather than
  equating `button.highlight(true)` with a displayed result.

## Test fixture (E4, debug builds only)

- **On:** build and install a debug app (`scripts/bundle.sh --debug && scripts/install.sh`), then
  `defaults write local.macplugins.summon PanelFixture tall` and relaunch. The panel gets 80
  placeholder rows, so the height cap and inner scroll are visible. Release builds ignore the key (`#if DEBUG`).
- **Off:** `defaults delete local.macplugins.summon PanelFixture`.
