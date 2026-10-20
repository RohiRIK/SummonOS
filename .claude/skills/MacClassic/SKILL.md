---
name: MacClassic
description: "Classic Mac interfaces in SwiftUI. USE WHEN explicitly requesting System 7, Mac OS 8/9, Platinum bevels, or Chicago typography. NOT FOR modern macOS (LiquidGlass) or other retro eras."
category: visual
effort: medium
domain: design
---

# MacClassic — System 7 and Mac OS 8/9 Platinum

Build an optional retro visual treatment using Swift 6 and SwiftUI on macOS 15+.
Crisp raised and recessed bevels, six-line title motifs, grayscale surfaces, and bitmap-inspired typography.

## Workflow Routing

| Task | Read first |
|------|------------|
| Visual direction and era details | `ClassicDesign.md` |
| Implement components | `ClassicComponents.md` |
| Choose illustrative colors | `ClassicTheme.md` |

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

**Example 1:** “Give this soundboard a Mac OS 9 theme.” → Platinum controls and an in-content striped header; preserve the native title bar.

**Example 2:** “Create a System 7 style settings pane.” → Keep preferences in the Settings window; test focus, text contrast, and resizing.
