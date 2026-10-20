# MacAqua — OS X Aqua Design System (10.0–10.6)

MacAqua captures the golden era of Steve Jobs' skeuomorphic design: Mac OS X Cheetah (10.0), Jaguar, Panther, Tiger, and Snow Leopard (10.6). Aqua is tactile, glossy, translucent, and inviting—"so good you want to lick it."

## Core Philosophy
1. **Physicality & Reflection:** Every surface behaves like polished glass, water, or brushed aluminum. Top surfaces catch bright specular highlights; bottom rims cast deep refracted shadows.
2. **Two Signature Flavors:**
   - **Aqua Blue (Default):** Vibrant cyan-blue jelly buttons (`#1b75d0` to `#54a6ff`), water droplets, vibrant blue selection.
   - **Graphite (Pro/Power):** Neutral gray glass (`#555555` to `#888888`), preferred by creative professionals for color accuracy.
3. **Materials:**
   - **Pinstripe (10.0–10.4):** Subtle alternating fine lines (`#ffffff` and `#ebebeb`).
   - **Brushed Metal (Panther/Tiger):** Textured horizontal aluminum striations with etched dark borders.
   - **Snow Leopard (10.6):** Refined matte translucent gray sheets with subtle inner bevels.

---

## Signature Components

### 1. Aqua Jelly Pill Button
- Outer shape: Pill / Capsule (`Capsule()`).
- Gradients:
  - Base: Deep saturated color gradient from light at the upper third to darker at the bottom.
  - Gloss Highlight: Top half oval overlay with white-to-transparent linear gradient (`Color.white.opacity(0.7)` to `.clear`).
  - Rim: Dual strokes—outer dark border + inner 1px white highlight line.
  - State: On press, gradient inverts with inner glow.

### 2. Candy-Stripe Progress Bar
- 45° diagonal barber pole stripes.
- Continuous smooth scrolling animation.
- Glossy cylinder overlay creating a 3D tubular glass pipe appearance.

### 3. Brushed Metal & Pinstripes
- Brushed metal: Linear gradients with micro-grain noise effect.
- Pinstripe: Alternating fine repeating pattern.
- Etched labels: White drop-shadow beneath dark text (`.shadow(color: .white.opacity(0.8), radius: 0, x: 0, y: 1)`).

### 4. Native Window Controls
Keep AppKit/SwiftUI close, minimize, zoom, dragging, and full-screen behavior. Apply retro styling inside the content area; decorative circles are not replacements for functional window chrome.


These notes describe a visual interpretation for modern macOS, not a compatibility implementation of the historical operating system.
