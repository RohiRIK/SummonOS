---
type: Research
title: "Surface 2: full desktop app"
description: "The main app window (sidebar, canvas, inspector), checked cell by cell against the HIG and AppKit/SwiftUI docs."
tags: [design, ux, surfaces, window]
created: 2026-10-25
---

# Surface 2: full desktop app (`NSWindow` / main workspace)

Column 2 of the [surface table](surface-table.md), checked 2026-10-25. Verdicts as in
[Surface 1](01-menu-bar.md#surface-1-menu-bar-app-menubarextra--popover): **Apple**, **Convention**, **Fix**.
Liquid Glass details (inset sidebar, glass toolbar, concentric corners) are in
[macOS design language](../research/2026-10-18-mac-gui-design/02-hig-tahoe-golden-gate.md).

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | Deep workspace for sustained work | **Apple** | HIG Windows: the *primary* window "presents the main navigation and content of an app". |
| Window anatomy | Unified title bar + toolbar, 3 traffic lights, sidebar + canvas + inspector | **Apple** | `NavigationSplitView` + `.inspector`; toolbar items in glass groups on 26. HIG: "Avoid creating custom window UI"; avoid critical actions in a bottom bar. |
| Sizing | min 800 × 550, resizable, full screen, Split View, Stage Manager | **Apple** (behavior) / **Convention** (numbers) | HIG: "Make sure that your windows adapt fluidly to different sizes." No Apple minimum; pick one where the sidebar plus a readable canvas still fit (800 × 550 is reasonable). Use the system full screen (`toggleFullScreen`), which handles the camera housing. Default `windowResizability` for a `WindowGroup` is `contentMinSize`. |
| Focus | Stays open behind other apps; ⌘W closes window, ⌘Q quits | **Apple** | HIG Keyboards: ⌘W "Close the active window", ⌘Q "Quit the app". Whether closing the last window quits is a choice: utility apps usually stay running. Restore windows on relaunch (HIG Launching). |
| Materials | Sidebar material for navigation; opaque window background for canvas | **Apple** | On 26 the sidebar is Liquid Glass, and the HIG says "Don't use Liquid Glass in the content layer": the canvas stays an opaque system background. |
| Typography | Body 13–14, section titles 17–22 bold, sidebar 13 | **Apple** (close) | HIG macOS: Body 13, Title 2 17, Title 1 22, Large Title 26. Use text styles, not 14 pt body; sidebar rows take the system size automatically. |
| Controls | Tables, split views, toolbars, segmented controls, inspectors, multi-select | **Apple** | Standard toolkit. HIG Context Menus: support context menus on every item, consistently. |
| Keyboard | Full menu bar (File, Edit, View, Window, Help), ⌘1/2/3, ⌘F | **Apple** | HIG The menu bar: support the system menus in order, keep items visible (disable, don't hide), use standard shortcuts. ⌘F = Find; ⌥⌘F jumps to the search field; ⌃⌘F = full screen. ⌘1…9 for sidebar sections is a common convention. |
| Drag & drop | Drag in from Finder, reorder with springs, drag back out | **Apple** | HIG Drag and drop: support it everywhere, offer menu alternatives, allow undo, let people drag to the Finder in a format you can reopen, badge multi-item drags. |
| Audio/video | AVKit player, scrubbing, Space play/pause, J/K/L, export queue | **Apple** (AVKit) / **Convention** (J/K/L) | `AVPlayerView` gives standard controls. J/K/L is a pro-editor convention, only for editing apps. |
| Alerts | Sheets attached to the window; empty states with illustration + CTA | **Apple** | `NSAlert.beginSheetModal(for:)` runs the alert as a sheet. HIG Alerts: use sparingly, not for undoable actions, never at launch. HIG Sheets: one at a time, reasonable size, brief. |
| Context menu | Right-click everywhere; Space = Quick Look | **Apple** | HIG Context Menus: short, most-used first, no shortcuts shown in them, hide (not dim) unavailable items. Quick Look via `QLPreviewPanel` / `.quickLookPreview`. |
| Motion | 200–300 ms spatial continuity, springs | **Convention** | Use system animations; HIG Motion: avoid motion on frequent interactions, respect Reduce Motion. |
| Performance | Lazy lists, background work, App Nap | **Apple** | `LazyVStack` / `List`, work off the main actor, and `ProcessInfo.beginActivity` only around work that must not nap. |
| Dock | `.regular`: Dock icon, badge, Dock menu, ⌘Tab | **Apple** | HIG Dock menus: high-value items (open windows, a few actions), also available elsewhere. |

## What the table leaves out

- **State restoration:** reopen windows where people left them (HIG Launching).
- **Undo:** every edit, drop and delete undoable (HIG Undo and redo); this is what lets you skip confirmation alerts.
- **No app-only appearance setting** (HIG Dark Mode) and test with Increase Contrast and Reduce Transparency.

## Sources

- HIG: [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [The menu bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [Going full screen](https://developer.apple.com/design/human-interface-guidelines/going-full-screen), [Drag and drop](https://developer.apple.com/design/human-interface-guidelines/drag-and-drop), [Alerts](https://developer.apple.com/design/human-interface-guidelines/alerts), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Dock menus](https://developer.apple.com/design/human-interface-guidelines/dock-menus), [Launching](https://developer.apple.com/design/human-interface-guidelines/launching)
- API: [`windowResizability(_:)`](https://developer.apple.com/documentation/swiftui/scene/windowresizability(_:)), [`NSAlert.beginSheetModal(for:completionHandler:)`](https://developer.apple.com/documentation/appkit/nsalert/beginsheetmodal(for:completionhandler:)), [`ProcessInfo.beginActivity`](https://developer.apple.com/documentation/foundation/processinfo/beginactivity(options:reason:))
