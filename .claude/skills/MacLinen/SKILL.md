---
name: MacLinen
description: "Linen-era interfaces in SwiftUI. USE WHEN explicitly requesting OS X Lion, woven linen, stitched leather, or legal-pad styling. NOT FOR modern macOS (LiquidGlass) or other retro eras."
category: visual
effort: medium
domain: design
---

# MacLinen — OS X Linen and skeuomorphic styling (10.7–10.9 transition)

Build an optional retro visual treatment using Swift 6 and SwiftUI on macOS 15+.
Woven charcoal linen, stitched leather accents, warm stationery, and embossed labels.

## Workflow Routing

| Task | Read first |
|------|------------|
| Visual direction and era details | `LinenDesign.md` |
| Implement components | `LinenComponents.md` |
| Choose illustrative colors | `LinenTheme.md` |

## Workflow

1. Confirm the requested era from the task; use LiquidGlass for unspecified modern UI.
2. Read the relevant reference above, then adapt components to the existing app.
3. Keep native window chrome, keyboard shortcuts, focus, and a separate Settings window functional.
4. Verify Swift 6 compilation at macOS 15, previews, resizing, VoiceOver, and appearance settings.

## Gotchas

- These are era-inspired approximations; palettes are not official Apple/NeXT specifications.
- Historical appearance does not lower the macOS 15 deployment target or permit obsolete APIs.
- Keep native Button semantics and focus indicators; wire required callbacks to real actions.
- Respect Reduce Motion, Reduce Transparency, and contrast; license any added fonts or assets.

## Examples

**Example 1:** “Give my journal an OS X Lion leather-and-linen theme.” → Stitched content header and linen backdrop with readable foreground colors.

**Example 2:** “Add legal-pad paper to a notes window.” → Use the paper component as decoration around an accessible native text editor.
