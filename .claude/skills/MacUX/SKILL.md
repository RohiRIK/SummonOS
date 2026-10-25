---
name: MacUX
description: "Advanced macOS UX/UI for SwiftUI apps: HIG (Tahoe and Golden Gate), menu bar icon and panels, full windows, activity feeds and agent status, Liquid Glass, SF Symbols, materials, typography, motion, keyboard, accessibility, polish review. USE WHEN designing, building, redesigning, or reviewing any macOS view, panel, window, status item, or settings screen, or when the user says the UI looks bad, clipped, or unpolished. NOT FOR app structure, data or backend calls (use MacAppArchitecture) or build/verify (use MacAppBuild). For deep SwiftUI API questions also load swiftui-expert-skill."
category: workflow
effort: medium
domain: design
---

# MacUX

Makes plugins look and feel like they shipped with macOS. Bar: "beautiful by default", like Glaze or Raycast apps.

## Workflow Routing

| Workflow | Trigger | File |
|----------|---------|------|
| **DesignPass** | new screen, redesign, "make it look better", any UI complaint or screenshot | `Workflows/DesignPass.md` |

| Surface | Read first |
|---------|-----------|
| The menu bar icon, click behaviour, `MenuBarExtra` vs `NSStatusItem` + `NSPanel` | `MenuBarItem.md` |
| Menu bar panel content | `MenuPanel.md` |
| A full window (main, Activity, library): toolbar, sidebar, inspector, glass, bringing it to the front | `Windows.md` |
| Event lists, history, status overview, running jobs or agents, undo | `ActivityFeeds.md` |

## Quick Reference

- **Status lives in the chrome, problems only when present.** No dashboard tile grids in windows (`Windows.md`, `ActivityFeeds.md`).
- **Use system containers and draw nothing yourself** (`NavigationSplitView`, toolbar, `List`, `Form`, inspector): they track Tahoe → Golden Gate restyles; hand-drawn chrome does not.
- **Menu bar panels: `MenuPanel.md` first.** Copy the system Wi-Fi menu anatomy; HIG says menu, not popover; no glass on content; no `Form`.
- Principles, spacing, type, color, motion: `Principles.md`. Read before the first view. Ends with Glaze design-system rules (flat, semantic roles, one primary action, Settings window, design-reference fidelity).
- Ready-made SwiftUI patterns (panel header, rows, status dot, inline editor, glass, empty/error states): `Patterns.md`.
- System first: system fonts, semantic colors, SF Symbols, standard controls. Custom only when the system has nothing.
- Every action reachable by keyboard. Every icon-only control has `.help()` and an accessibility label.
- Every view file ends with a `#Preview` using fake data (no CoreWLAN, no network). Render it with the Xcode MCP `RenderPreview` tool and read the image before calling a view done.

## Gotchas

- Sidebar Settings (`NavigationSplitView`): never paint the detail pane (`.background(windowBackgroundColor)`) and remove the sidebar toggle (`.toolbar(removing: .sidebarToggle)`). Otherwise the title bar gets an empty band with a floating toggle, unlike System Settings (Summon, 2026-10-25).
- Hard-coded colors (`Color.black`, hex) break dark mode and Increase Contrast. Use `.primary`, `.secondary`, `Color(nsColor: .separatorColor)`, `.tint`.
- Liquid Glass is for floating controls and navigation only, never content (cards, lists, details). Glass cards made the first mac-network panel look wrong. `.glassEffect()` is macOS 26+; gate with `if #available(macOS 26, *)`.
- More than one job in a panel: split it into tabs with `TabSwitcher` (`MenuPanel.md` › Everything in the panel). Editing the app's *job* (mac-network's IP settings) can be a panel tab with `SettingsGroup` rows. App preferences (Open at Login, permissions, theme, any toggle) never go in the panel: Settings window (⌘,), plus onboarding only when a permission is needed up front.
- "Looks like Windows 98" = bordered cards, grouped Form, segmented control, big padding. Fix per `MenuPanel.md`.
- `MenuBarExtra(.window)` sizes to content. Set `.frame(width:)` once on the root; unbounded lists make the panel jump.
- `MenuBarExtra(.window)` keeps its old height when content grows (a banner appears): the top gets clipped and rows overlap, so clicks land on the wrong row. Put `.fixedSize(horizontal: false, vertical: true)` on the panel root.
- `MenuBarExtra(.window)` grows its window with the content (top edge stays) but shrinks it late and toward the bottom edge, so a shorter page drops away from the menu bar. Resize the window yourself on every height change, keeping the top: mac-calendar `FitWindowHeight` (`Components.swift`). Verify by logging `NSWindow.didResizeNotification` frames, not by eye.
- Two views of different height in one panel (month/week): lay out the reference view invisibly (`.opacity(0)`, no hit testing) and overlay the other with a `ScrollView`, so switching never resizes the window.
- Settings window: 580 pt wide, min height 640, scrolling Form (`MenuPanel.md` › App settings).
- A `ScrollView` inside a content-sized panel collapses to one row. Use `.frame(maxHeight: N).fixedSize(horizontal: false, vertical: true)` so it grows with content up to N, then scrolls.
- `.textSelection(cond ? .enabled : .disabled)` does not compile (different types). Pick one.
- Menu bar icon must be a template image (SF Symbol or `isTemplate = true`) so it adapts to light/dark menu bars.
- Spinners for work under 300 ms cause flicker. Delay showing progress, or keep the old value dimmed.
- Numbers that update live need `.monospacedDigit()` or the row jitters.
- A `Window` opened from a menu bar (accessory) app lands **behind** the frontmost app: `NSApp.activate()` is only a request since macOS 14. Use the four-step recipe in `Windows.md` (regular policy, activate, openWindow, raise from `viewDidMoveToWindow`). Seen on Summon's Activity window via `summon://activity`.
- Every `Window` scene in a menu bar app needs `.defaultLaunchBehavior(.suppressed)`, or a ghost window appears at launch or restore.
- `MenuBarExtra` cannot be opened from code, has no right-click menu and no live label. Needing any of those means `NSStatusItem` + `NSPanel` (`MenuBarItem.md`).
- A borderless `NSPanel` refuses key status: override `canBecomeKey` or its text fields never get keystrokes.
- Untrusted strings (crash process names, prompts, file names) can carry bidi overrides and control characters. Sanitise in Core, render with `Text(verbatim:)`. Upside-down glyphs are a rendering bug instead (Core Text in a flipped context, subviews added in `updateNSView`).
- Hide no-op events ("Undid 0 settings"): a feed row must describe a change that happened.
- Tahoe (26) and Golden Gate (27) look different (floating vs edge-to-edge sidebar, soft vs hard scroll edges, menu icons on vs minimal). Check previews on the user's OS; never imitate one version's look by hand.

## Examples

**Example 1: UI complaint with a screenshot**
```
User: "Allow just toggled me, make the Wi-Fi data look nicer"
→ DesignPass: diagnose (overlap + Location When-In-Use) → reference: Control Center module
→ states incl. the screenshot one → build → render all previews → user checks real app → record
```
