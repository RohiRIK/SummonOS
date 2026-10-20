# Menu bar panel: NSStatusItem + nonactivating panel

Summon's menu bar item is an `NSStatusItem` plus a `StatusPanel` (`NSPanel`), owned by one `PanelController`
(`Sources/SummonMenuUI/StatusPanel.swift`). It replaces `MenuBarExtra`.

The panel:
- takes typing without activating Summon;
- holds the Summon Menu (the former launcher);
- opens from ⌃⌥Space, the CLI and URLs;
- keeps updating while open;
- closes only on the triggers listed below.

Behavior follows the interaction spec v1.3 (IDs A1–G3). The decision rules live in
`Sources/SummonCore/PanelLogic.swift` and are unit-tested without AppKit (`Tests/SummonCoreTests/PanelLogicTests.swift`).

## Shape

- **Style mask** `[.nonactivatingPanel, .borderless, .fullSizeContentView]`, set at init.
  - `canBecomeKey = true`, `canBecomeMain = false`, `hidesOnDeactivate = false`.
  - Collection behavior: `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`.
- **Level** is `PanelConfig.level` (`.statusBar`) for every Summon panel, the crash alert included.
- **Content** is one SwiftUI view (`PanelView`) in an `NSHostingController` with `sizingOptions = [.preferredContentSize]`.
  From top to bottom:
  - header with the agent line;
  - search field and menu tree (the former launcher);
  - Ask Agent and Activity…;
  - footer with Settings… (⌘,) and Quit Summon (⌘Q).
- **Size and position.**
  - The panel is as tall as its content, capped at the visible screen height minus 8 pt at top and bottom; past that it scrolls.
  - The top edge sits 4 pt under the icon and stays there on resize.
  - Left and right are clamped 8 pt inside `visibleFrame`.
  - With the hotkey, the panel goes under the item on the pointer's display. If that display has no item, it goes
    under the main display's item, mapped to the same distance from the right edge.
- **Live updates.** While open, the view refreshes Activity every 1 s, and the agent row shows elapsed `mm:ss`
  (`PanelClock`). There's no menu-tracking run loop, so updates draw as they happen.

## Keys in the panel

| Key | Does |
|---|---|
| Typing | Searches the whole Summon Menu |
| ↑ ↓ | Move the selection |
| → / Return on a submenu | Open it |
| ← | Go up one level |
| Return | Run the entry and close (D3) |
| Esc | Close (D1) |
| ⌘, / ⌘Q | Settings… / Quit Summon (footer) |

## Opening

| From | How |
|---|---|
| Status item | `button.sendAction(on: [.leftMouseUp, .rightMouseUp])`. `NSApp.currentEvent` tells a left click from a right click or ⌃-click. |
| ⌃⌥Space | `SummonHotKey.menuID` with presses and releases, so a held key opens once (C3). |
| Code | `PanelController.open()`, `open(at:)`, `close()`, `toggle()`. These are main-actor and idempotent. `requestOpen()` / `requestClose()` work from any thread (C7). |
| URL | `open -g summon://panel`, `open -g summon://panel/close`, `summon://menu/<id>` (opens at that entry) |
| CLI | `summon panel`, `summon panel --close`, `summon menu summon <id>` (all use `open -g`) |

The right-click (or ⌃-click) menu has exactly **Settings… ⌘,** and **Quit Summon ⌘Q**. If the panel is open, it
closes first.

## Closing (spec section D, nothing else)

| ID | Trigger | Source |
|---|---|---|
| D1 | Esc | `StatusPanel.cancelOperation`, and `onKeyPress(.escape)` in the search field |
| D2 | Icon or ⌃⌥Space while open | toggle |
| D3 | An action ran | menu entries and rows call `PanelActions.finish` |
| D4 | Another app becomes frontmost | `NSWorkspace.didActivateApplicationNotification`. The previous app and Summon itself are ignored (decision 2). |
| D5 | Space change | `NSWorkspace.activeSpaceDidChangeNotification` |
| D6 | Settings… or Quit | footer or right-click menu |
| D7 | Lock, display sleep, system sleep, user switch | `com.apple.screenIsLocked` (distributed), `screensDidSleep`, `willSleep`, `sessionDidResignActive` |

- There's no global click monitor, and the panel doesn't close on `didResignKey`.
- Every close removes all its observers and clears the highlight.
- Focus goes back to the previous app. The panel never activated Summon, so ordering it out hands key focus back.
  If Summon did become frontmost in the meantime, the previous app is activated again.
- An app switch, a Space change, Settings, Quit or a lock leaves focus where the user or macOS put it.
- The panel never pastes (decision 1).

## Proof hooks

- **B1:** the `PanelOpen` `os_signpost` interval, subsystem `local.macplugins.summon`, category `panel`. It also logs
  "panel ordered front N ms after the click event". The status button only sends its action on mouse-up, so the log
  measures from mouse-up. Mouse-down to ordered front needs the Mac screen recording.
- **D rules:** every close logs `panel closed (<reason>); active monitors: N`. Expect 0. To watch it:
  `log stream --level info --predicate 'subsystem == "local.macplugins.summon" && category == "panel"'`.

## Deployment floor

- **Minimum macOS 15:** `Package.swift` `.macOS(.v15)`, `Info.plist` `LSMinimumSystemVersion 15.0`.
- Every API used here exists on macOS 15:
  - nonactivating `NSPanel`, `.statusBar`, `.fullScreenAuxiliary`, `.transient`, `.ignoresCycle`;
  - `NSRunningApplication.activate()` (14);
  - `NSHostingController.sizingOptions` (13);
  - `OSSignposter` (12);
  - `onKeyPress` (14);
  - `onGeometryChange` (back-deployed);
  - `TimelineView` (12).
- **Verified only on macOS 26.x.** The macOS 15 target is compile-checked, but runtime is unverified until a 15 machine or VM exists.
- macOS 27 betas: `button.highlight(true)` reportedly doesn't stick (FB23330269). The panel still works, but the highlight may not show.

## Test fixture (E4)

- **On:** `defaults write local.macplugins.summon PanelFixture -string tall`, then relaunch. The panel gets 80
  placeholder rows, so the height cap and inner scroll are visible.
- **Off:** `defaults delete local.macplugins.summon PanelFixture`.
