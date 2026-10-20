# MacYosemite — OS X Flat Vibrancy Era (10.10–10.15)

MacYosemite captures Jony Ive's profound 2014 visual reboot: OS X 10.10 Yosemite through 10.15 Catalina. Gone were the leather stitches and brushed metal, replaced by bright frosted glass, translucent vibrancy sidebars, ultra-flat controls, system sans-serif typography, and vibrant primary accents.

## Core Philosophy
1. **Vibrancy & Frosted Layers:**
   - Window sidebars and title bars let desktop colors bleed through with intense frosted blur (`.ultraThinMaterial` / `NSVisualEffectView`).
   - Active selections glow with bright System Blue (`#007aff`).
2. **Flat Geometric Controls:**
   - Segmented buttons are flat pills with 1px border (`Color.gray.opacity(0.3)`).
   - Switches are smooth iOS-style toggles.
   - Text fields have subtle 1px gray borders with no inner bevels.
3. **Typography & Icons:**
   - Yosemite used Helvetica Neue; later releases adopted **San Francisco**. Prefer the installed system font (`.system(size:..., weight:..., design: .default)`).
   - Crisp, razor-thin vector icons (1pt stroke weight) without drop shadows or embossing.
4. **Dark Mode Debut (Mojave 10.14):**
   - Deep charcoal `/ #1e1e1e` dark vibrancy surfaces with white typography.

These notes describe a visual interpretation for modern macOS, not a compatibility implementation of the historical operating system.
