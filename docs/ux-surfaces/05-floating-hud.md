---
type: Research
title: "Surface 5: floating HUD"
description: "Always-on-top HUDs, PiP bubbles and drop shelves, checked against the HIG Panels page and AppKit window docs."
tags: [design, ux, surfaces, hud]
created: 2026-10-25
---

# Surface 5: floating HUD / PiP (`NSPanel`, always on top)

Column 5 of the [surface table](surface-table.md), checked 2026-10-25. Verdicts as in
[Surface 1](01-menu-bar.md#surface-1-menu-bar-app-menubarextra--popover).

## What Apple says about HUDs

HIG Panels has a HUD section, and it is cautious: **"Prefer standard panels."** Use a HUD-style panel only in
a media-oriented app, when a standard panel would hide essential content, and when you need few controls
("most system-provided controls don't match a HUD's appearance"). **"Keep HUDs small"**, **"Use color
sparingly"**, and keep one style across modes. So: a recording bar, a timer, a camera bubble, a now-playing
strip are good HUDs. A settings palette is not; make it a standard panel.

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | Ambient companion: recording, timers, drop shelf | **Apple** (with the limits above) | Only for content that must stay visible while people work elsewhere. |
| Window anatomy | Hover-only mini traffic lights or an X; pill, circle or card | **Convention** | HIG Panels: "avoid making a panel's minimize button available." A borderless panel with a close button on hover. |
| Sizing | 120–320 pt, drag from anywhere, snaps to corners | **Convention** | `isMovableByWindowBackground = true`; snapping is your code (iOS PiP model). HIG: keep it small. |
| Focus | `.floating` / `.statusBar` level, never steals keys | **Apple** (API) + **Fix** (two defaults) | `.floating` is "useful for floating palettes"; use `.statusBar` only to sit above other floating windows. `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded = true` so a click doesn't take keys from the app people are typing in. Panels hide when the app deactivates (`hidesOnDeactivate` defaults to `true` for `NSPanel`): set it to `false`, or the HUD vanishes the moment people click elsewhere. Add `[.canJoinAllSpaces, .fullScreenAuxiliary]` to follow people across Spaces and over full-screen apps. |
| Materials | Dark bias, high contrast, glass when idle | **Apple** | `NSWindow.StyleMask.hudWindow` / `NSVisualEffectView.Material.hudWindow`. HIG Dark Mode allows a permanently dark UI for immersive media, which is the HUD case. |
| Typography | Monospaced digits for timers and meters, 12–14 pt | **Apple** (API) / **Convention** (sizes) | `.monospacedDigit()`; it is the right call for any changing number. |
| Controls | 2–4 icon buttons, faded to 30% until hover | **Convention** | Fading is fine, but keep the primary control (Stop) always visible and give every button an accessibility label; hover-only discovery fails for keyboard and VoiceOver users. |
| Keyboard | Global action hotkeys (e.g. ⇧⌘R stop) | **Convention** | User-recordable; check the HIG standard list first (⇧⌘R is free in most apps but not all). |
| Drag & drop | Drop shelf appears at the screen edge when a drag starts | **Convention** | Detecting a drag in another app needs a global mouse monitor or polling `NSPasteboard(name: .drag)`; a global `NSEvent` monitor for drags needs Accessibility. Keep it opt-in. |
| Audio/video | Camera bubble, recording timer, voice ring | **Convention** | Camera/mic need permission and the system's own indicators remain on screen. |
| States | Red border while recording, amber when paused, check on done | **Convention** | Pair color with a shape or label (HIG Accessibility: not color alone). |
| Context menu | Right-click: opacity, size, corner | **Convention** | Good; HIG Context Menus: short, no shortcuts shown. |
| Motion | Flick to corner with momentum | **Convention** | iOS PiP model. Reduce Motion: snap without the throw. |
| Performance | Low frame rate when idle; < 3% CPU while live | **Convention** | Use Core Animation layers for meters, not SwiftUI redraws per sample; pause when occluded (`NSWindow.occlusionState`). |
| Dock | Hidden, no Mission Control entry | **Apple** (API) | `collectionBehavior` `.transient` (the default when the level isn't `.normal`: "floats in Spaces and hides in Mission Control") and `.ignoresCycle` keeps it out of ⌘\`. |

## Sources

- HIG: [Panels › HUD-style panels](https://developer.apple.com/design/human-interface-guidelines/panels#HUD-style-panels), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- API: [`NSPanel.isFloatingPanel`](https://developer.apple.com/documentation/appkit/nspanel/isfloatingpanel) (Apple's four conditions for a floating panel: small, mouse-oriented, needed while working in other windows, hides on deactivate), [`becomesKeyOnlyIfNeeded`](https://developer.apple.com/documentation/appkit/nspanel/becomeskeyonlyifneeded), [`hidesOnDeactivate`](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate), [`NSWindow.Level.floating`](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct/floating), [`hudWindow`](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/hudwindow), [`transient`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/transient), [`ignoresCycle`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/ignorescycle), SwiftUI [`windowLevel(_:)`](https://developer.apple.com/documentation/swiftui/scene/windowlevel(_:)) (macOS 15)
