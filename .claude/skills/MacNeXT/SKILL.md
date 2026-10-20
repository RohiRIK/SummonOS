---
name: MacNeXT
description: "NeXT-inspired interfaces in SwiftUI. USE WHEN explicitly requesting NeXTSTEP, OPENSTEP, chiseled gray controls, or vertical dock tiles. NOT FOR modern macOS (LiquidGlass) or other retro eras."
category: visual
effort: medium
domain: design
---

# MacNeXT — NeXTSTEP and OPENSTEP

Build an optional retro visual treatment using Swift 6 and SwiftUI on macOS 15+.
Sharp chiseled bevels, charcoal surfaces, black title motifs, and square application tiles.

## Workflow Routing

| Task | Read first |
|------|------------|
| Visual direction and era details | `NeXTDesign.md` |
| Implement components | `NeXTComponents.md` |
| Choose illustrative colors | `NeXTTheme.md` |

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

**Example 1:** “Style our developer inspector like a NeXT workstation.” → Chiseled control styles and an in-content title motif; preserve native window chrome.

**Example 2:** “Build a NeXT-style launcher tile list.” → Require real action callbacks and label every tile for accessibility.
