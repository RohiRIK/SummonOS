---
name: MacAqua
description: "Retro Aqua interfaces in SwiftUI. USE WHEN explicitly requesting OS X 10.0–10.6, glossy jelly buttons, or brushed metal. NOT FOR modern macOS (LiquidGlass) or other retro eras."
category: visual
effort: medium
domain: design
---

# MacAqua — OS X Aqua (10.0–10.6)

Build an optional retro visual treatment using Swift 6 and SwiftUI on macOS 15+.
Glossy blue or graphite capsules, fine pinstripes, brushed aluminum, and candy progress.

## Workflow Routing

| Task | Read first |
|------|------------|
| Visual direction and era details | `AquaDesign.md` |
| Implement components | `AquaComponents.md` |
| Choose illustrative colors | `AquaTheme.md` |

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

**Example 1:** “Make this audio player look like OS X Tiger.” → Aqua button styles and brushed-metal content; retain working native window controls.

**Example 2:** “Add an Aqua theme option to our macOS 15 utility.” → Scope retro colors to the selected theme; verify keyboard focus and Reduce Motion.
