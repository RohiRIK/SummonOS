---
name: LiquidGlass
description: "Modern native macOS design in SwiftUI. USE WHEN building or modernizing windows, settings, or glass controls. NOT FOR explicitly retro eras (MacAqua/MacClassic/MacLinen/MacNeXT/MacYosemite) or Core architecture (MacAppArchitecture)."
category: workflow
effort: medium
domain: design
---

# LiquidGlass

Design modern native macOS UI with system containers. Support macOS 15; apply
Liquid Glass APIs on macOS 26+ with availability checks and material fallbacks.

## Workflow Routing

| Workflow or topic | Trigger | Read first |
|-------------------|---------|------------|
| **ModernizeView** | Modernize a window, activity feed, or settings | `Workflows/ModernizeView.md` |
| Layers and materials | Glass placement and fallbacks | `LayersAndMaterials.md` |
| Settings | Sidebar navigation and grouped forms | `SidebarSettings.md` |
| Chrome | Toolbars, typography, and symbols | `GlassChrome.md` |

## Quick Reference

- Use glass for navigation and controls above content; preserve readable content surfaces.
- Prefer system toolbars, sidebars, lists, and forms before drawing custom effects.
- Use sidebar settings when several sections need navigation; one section can be a grouped Form.
- Prefer semantic SF Symbols for utility actions; check symbol availability at macOS 15.
- Keep Settings separate from menu panels and activate the app when opening its window.

## Gotchas

- `.glassEffect()` requires macOS 26+; gate it and provide a macOS 15 fallback.
- Remove list backgrounds only where a designed material should show through; opacity can improve readability.
- A hidden title does not replace functional close/minimize/zoom buttons or window dragging.
- Preserve keyboard focus and shortcuts; test light/dark, Reduce Transparency, and Increase Contrast.
- Container and geometry APIs have individual availability limits; compile against the deployment target.

## Examples

**Example 1:** “Modernize our multi-section Settings window.” → Read SidebarSettings,
use NavigationSplitView and grouped forms, then verify resizing and keyboard navigation.

**Example 2:** “Add a floating glass action on macOS 15 and 26.” → Read LayersAndMaterials,
use gated glass on 26 and a material fallback on 15; verify contrast in both paths.
