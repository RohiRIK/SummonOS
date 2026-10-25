---
type: Research
title: "Surface 4: command launcher"
description: "A Spotlight-style keyboard launcher panel, checked against the HIG and AppKit docs; the default hotkey must not be Cmd-Space."
tags: [design, ux, surfaces, launcher]
created: 2026-10-25
---

# Surface 4: command launcher (`NSPanel`, Spotlight style)

Column 4 of the [surface table](surface-table.md), checked 2026-10-25. Verdicts as in
[Surface 1](01-menu-bar.md#surface-1-menu-bar-app-menubarextra--popover). The HIG has no page for launchers, so most
cells are **Convention** (Spotlight, Raycast, Alfred); the API cells are checked against AppKit.

## One correction

**Don't default to ⌘Space.** The HIG's standard shortcuts reserve Command-Space for Spotlight (and
Option-Command-Space for Spotlight's results window, Control-Command-Space for Special Characters, Control-Space
for input sources). Ship with no hotkey or with ⌥Space (the Alfred/Raycast habit), and let people record their
own. Know that ⌥Space types a non-breaking space in normal typing, so a global ⌥Space takes that away. The HIG
also says to avoid Control as a modifier and to prefer Command.

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | Type & go: summon, type, run, vanish | **Convention** | Spotlight's model. |
| Window anatomy | Borderless floating panel, big search field, results, shortcut footer | **Convention** | `NSPanel` with `[.borderless, .nonactivatingPanel, .fullSizeContentView]`; override `canBecomeKey` → `true` or the field never gets keys. |
| Sizing | 600–750 wide; 56 pt bar grows to ~450 | **Convention** | Fix the top edge while the height grows (set the frame from the top, not the origin). |
| Focus | Takes keys over any app, even full screen; vanishes on focus loss or Esc | **Apple** (API) | `.nonactivatingPanel` = "does not activate the owning app", so the frontmost app keeps its menu bar. Over full-screen apps add `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary]`. Close in `resignKey` and `cancelOperation(_:)`. |
| Materials | Ultra-thick HUD blur, 1 px inner border (white 15% dark) | **Convention** | Pre-26: `NSVisualEffectView` `.hudWindow` or `.popover`, `.behindWindow`. 26: regular Liquid Glass. A hairline border helps over busy windows; with Increase Contrast use the system border. Not a forced dark look. |
| Typography | Query 18–22 light/regular, results 13–14 medium, key badges 11 mono | **Convention** | Query around Title 1 (22). Results at body/headline. Don't use Light below 18 pt (legibility). |
| Controls | Keyboard-highlighted rows, chips, ⌘K action menu | **Convention** | ⌘K for actions is a Raycast convention, not a system shortcut (the HIG has none for ⌘K), so it's free to use. |
| Keyboard | ⌘Space / ⌥Space, ↑↓ Tab, Enter, ⌘1…9 | **Fix** (⌘Space) | See the correction. Register with Carbon `RegisterEventHotKey` (no permission prompt) rather than a global `NSEvent` monitor (needs Accessibility/Input Monitoring). |
| Drag & drop | Drop a file to use it as an argument | **Convention** | Panel content view registers for file URLs. |
| Audio/video | Text media commands, Space previews | **Convention** | Quick Look for the preview. |
| Alerts | 2-second inline status in the footer | **Convention** | Matches HIG Alerts ("avoid using an alert merely to provide information"). Errors stay until the next keystroke, not 2 s. |
| Context menu | ⌘K action panel (copy, reveal, delete) | **Convention** | Also allow right-click on a row (HIG Context Menus: support them consistently). |
| Motion | Appears at once; list height animates; field never shifts | **Convention** | No window animation on show (`animationBehavior = .none`). Respect Reduce Motion for the list. |
| Performance | Pre-warmed, < 16 ms to show | **Convention** | Create the panel at launch and `orderOut`, then `makeKeyAndOrderFront` on the hotkey. 16 ms is a target, measure with signposts. |
| Dock | Hidden | **Apple** (API) | Part of an `LSUIElement` app; the panel's `collectionBehavior` `.transient` keeps it out of Mission Control. |

## Sources

- HIG: [Keyboards › Standard keyboard shortcuts and Custom keyboard shortcuts](https://developer.apple.com/design/human-interface-guidelines/keyboards), [Searching](https://developer.apple.com/design/human-interface-guidelines/searching), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts)
- API: [`NSWindow.StyleMask.nonactivatingPanel`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel), [`fullScreenAuxiliary`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary), [`canJoinAllSpaces`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces), [`transient`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/transient)
- Mechanics with code: [Menu bar and window mechanics § 1.2](../research/2026-10-18-mac-gui-design/03-menubar-and-window-mechanics.md)
