---
name: MacUX
description: "Advanced macOS UX/UI for SwiftUI apps: HIG, menu bar panels, Liquid Glass, SF Symbols, materials, typography, motion, keyboard, accessibility, polish review. USE WHEN designing, building, redesigning, or reviewing any macOS view, panel, or settings screen, or when the user says the UI looks bad, clipped, or unpolished. NOT FOR app structure, data or backend calls (use MacAppArchitecture) or build/verify (use MacAppBuild). For deep SwiftUI API questions also load swiftui-expert-skill."
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

## Quick Reference

- **Menu bar panels: `MenuPanel.md` first.** Copy the system Wi-Fi menu anatomy; HIG says menu, not popover; no glass on content; no `Form`.
- Principles, spacing, type, color, motion: `Principles.md`. Read before the first view. Ends with Glaze design-system rules (flat, semantic roles, one primary action, Settings window, design-reference fidelity).
- Ready-made SwiftUI patterns (panel header, rows, status dot, inline editor, glass, empty/error states): `Patterns.md`.
- System first: system fonts, semantic colors, SF Symbols, standard controls. Custom only when the system has nothing.
- Every action reachable by keyboard. Every icon-only control has `.help()` and an accessibility label.
- Every view file ends with a `#Preview` using fake data (no CoreWLAN, no network). Render it with the Xcode MCP `RenderPreview` tool and read the image before calling a view done.

## Gotchas

- Hard-coded colors (`Color.black`, hex) break dark mode and Increase Contrast. Use `.primary`, `.secondary`, `Color(nsColor: .separatorColor)`, `.tint`.
- Liquid Glass is for floating controls and navigation only, never content (cards, lists, details). Glass cards made the first mac-network panel look wrong. `.glassEffect()` is macOS 26+; gate with `if #available(macOS 26, *)`.
- More than one job in a panel: split it into tabs with `TabSwitcher`, keep editing in-panel with `SettingsGroup` rows (`MenuPanel.md` › Everything in the panel). Network features stay in panel tabs; app settings/permissions/theme go to a Settings window + onboarding (`MenuPanel.md`).
- "Looks like Windows 98" = bordered cards, grouped Form, segmented control, big padding. Fix per `MenuPanel.md`.
- `MenuBarExtra(.window)` sizes to content. Set `.frame(width:)` once on the root; unbounded lists make the panel jump.
- `MenuBarExtra(.window)` keeps its old height when content grows (a banner appears): the top gets clipped and rows overlap, so clicks land on the wrong row. Put `.fixedSize(horizontal: false, vertical: true)` on the panel root.
- A `ScrollView` inside a content-sized panel collapses to one row. Use `.frame(maxHeight: N).fixedSize(horizontal: false, vertical: true)` so it grows with content up to N, then scrolls.
- `.textSelection(cond ? .enabled : .disabled)` does not compile (different types). Pick one.
- Menu bar icon must be a template image (SF Symbol or `isTemplate = true`) so it adapts to light/dark menu bars.
- Spinners for work under 300 ms cause flicker. Delay showing progress, or keep the old value dimmed.
- Numbers that update live need `.monospacedDigit()` or the row jitters.

## Examples

**Example 1: UI complaint with a screenshot**
```
User: "Allow just toggled me, make the Wi-Fi data look nicer"
→ DesignPass: diagnose (overlap + Location When-In-Use) → reference: Control Center module
→ states incl. the screenshot one → build → render all previews → user checks real app → record
```
