---
name: MacYosemite
description: "Flat vibrancy interfaces in SwiftUI. USE WHEN explicitly requesting Yosemite–Catalina styling, frosted sidebars, or pre-Liquid-Glass controls. NOT FOR modern macOS (LiquidGlass) or other retro eras."
category: visual
effort: medium
domain: design
---

# MacYosemite — OS X flat vibrancy (10.10–10.15)

Build an optional retro visual treatment using Swift 6 and SwiftUI on macOS 15+.
Frosted vibrancy, restrained borders, flat accent controls, and Mojave-inspired dark surfaces.

## Workflow Routing

| Task | Read first |
|------|------------|
| Visual direction and era details | `YosemiteDesign.md` |
| Implement components | `YosemiteComponents.md` |
| Choose illustrative colors | `YosemiteTheme.md` |

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

**Example 1:** “Give this inspector a Yosemite frosted-sidebar theme.” → Use system vibrancy with window activity tracking and legible content.

**Example 2:** “Add a Catalina-inspired dark theme to a utility.” → Use semantic text colors, test light/dark modes, and retain keyboard focus.
