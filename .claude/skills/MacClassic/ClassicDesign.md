# MacClassic — System 7 & Platinum Design System (1991–2000)

MacClassic captures the legendary pre-OS X era of Apple computing: System 7, Mac OS 8, and Mac OS 9 (Platinum). It is characterized by pixel-precision, crisp 3D beveled borders, horizontal title bar stripes, and iconic typography.

## Core Philosophy
1. **Pixel-Exact Bevels:** Light originates from top-left.
   - Top and Left edges: Pure White (`#ffffff`) or Light Gray (`#f0f0f0`).
   - Bottom and Right edges: Dark Gray (`#808080`) or Solid Black (`#000000`).
   - Recessed areas invert these highlights and shadows.
2. **Title Bar Pinstripes:** 6 dark horizontal pinstripes across the title bar with a centered title badge.
3. **Control Elements:**
   - Square close-box motif inside a content header; keep native window controls functional.
   - Zoom Box and WindowShade Collapse Box on the far right.
   - Heavy rounded-corner Platinum buttons with double-stroke default borders.
   - Classic square checkboxes with 2px bevel and bold checkmark.
   - Circular radio buttons with beveled ring and solid center dot.
4. **Typography:**
   - System 7: **Chicago** (12pt system bitmap).
   - Mac OS 8/9: **Charcoal** (12pt antialiased system font).
   - In SwiftUI, simulate with `.font(.system(size: 12, weight: .bold, design: .monospaced))` or a separately licensed bitmap font; do not redistribute historical Apple fonts.

These notes describe a visual interpretation for modern macOS, not a compatibility implementation of the historical operating system.
