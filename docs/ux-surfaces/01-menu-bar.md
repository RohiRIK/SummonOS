---
type: Research
title: "Surface 1: menu bar app"
description: "The menu bar extra and its panel, checked cell by cell against the HIG and AppKit/SwiftUI docs."
tags: [design, ux, surfaces, menubar]
created: 2026-10-25
---

# Surface 1: menu bar app (`MenuBarExtra` / popover)

Column 1 of the [surface table](surface-table.md), checked against Apple's HIG and developer documentation on
2026-10-25. Verdicts: **Apple** = an HIG rule or documented API behavior; **Convention** = what good apps do,
with no Apple rule behind it (fine to follow, fine to tune); **Fix** = the cell contradicts Apple or one of our
own rules, so follow the correction instead. Deeper mechanics: [Menu bar and window mechanics](../research/2026-10-18-mac-gui-design/03-menubar-and-window-mechanics.md)
and [Premium native menu bar apps](../research/2026-10-18-mac-gui-design/01-menubar-apps.md).

## The one thing Apple says first

The HIG's menu bar extras section says: **"Display a menu — not a popover — when people click your menu bar
extra. Unless the app functionality you want to expose is too complex for a menu, avoid presenting it in a
popover."** The table assumes a popover. So the first decision for any new menu bar app is: can this be an
`NSMenu` (`.menuBarExtraStyle(.menu)`)? Use a panel (`.window` style or a custom `NSPanel`) only when it shows
live data, a grid, or controls a menu cannot hold. SummonOS apps usually qualify (a calendar grid, live
network data, an activity list); a toggle-and-three-actions app does not.

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | Peek & pop, 3-second interactions | **Apple** | HIG Popovers: "limit the amount of functionality in the popover to a few related tasks." |
| Window anatomy | Frameless, no traffic lights, anchored to the icon | **Apple / Convention** | No title bar is right. The arrow is optional: macOS 26 system panels (Control Center) drop straight down without one. Use the system popover or `.window` style chrome; HIG Windows: "Avoid creating custom window UI." |
| Sizing | 260–360 wide, max ~500 tall, non-resizable | **Convention** | Apple gives no number; HIG: "Avoid making a popover too big", "animate the change" when its size changes. Our panels are 320 pt (Summon). Cap height to `screen.visibleFrame` and scroll inside. |
| Focus | Click outside or Esc closes; does not change the active app's menu bar | **Apple** (close) / **Convention** (menu bar) | `NSPopover.Behavior.transient` closes on outside interaction. A custom panel needs `.nonactivatingPanel` to leave the frontmost app's menus alone, plus `cancelOperation(_:)` for Esc. |
| Materials | Popover material; icon must be template / SF Symbol | **Apple** (with nuance) | `NSVisualEffectView.Material.popover` before 26; regular Liquid Glass on 26. HIG: "Consider using a symbol" and lets the system tint black-and-clear images. A colored icon for a real state (our orange "needs attention") is allowed; a colored logo is not. |
| Typography | Body 12–13, headers 13 semibold, captions 11 | **Apple** (close) | HIG macOS text styles: Body 13, Headline 13 bold, Callout 12, Subheadline 11, Footnote 10. Use the styles (`.body`, `.callout`, `.caption`), not raw sizes; the minimum on macOS is 10 pt. |
| Controls | Control Center style: sliders, pill buttons, icon grids, hover rows | **Convention** | HIG Panels: "Prefer simple adjustment controls", avoid typing. Hover rows are our `MacUX/MenuPanel.md` standard. |
| Keyboard | Global hotkey, arrows, Enter, Cmd+, | **Convention** + **Apple** (Cmd+,) | Cmd+, opens Settings (HIG Keyboards). A global hotkey is optional and must be user-recordable; arrow navigation needs focusable rows (`.focusable()`, `onKeyPress`). |
| Drag & drop | Drop onto the menu bar icon; auto-open after 0.4 s | **Convention** | `NSStatusBarButton` is a view and can `registerForDraggedTypes`; auto-open is spring loading (`NSSpringLoadingDestination`), whose delay is a user setting, so do not hard-code 0.4 s. |
| Audio/video | Device switcher, mini waveform, mute | **Convention** | Fine for a media utility; stop meters when the panel closes (see Performance). |
| Alerts | Never `NSAlert` from a popover; inline banners | **Convention** (HIG differs) | HIG Popovers allows an alert over a popover ("except for an alert") and says to use an alert, not a popover, for warnings. In practice a modal alert from a transient panel in an `LSUIElement` app closes the panel and can open behind other apps. Our rule: inline status in the panel; a real confirmation (destructive, not undoable) goes in its own activated window or alert after `NSApp.activate()`. |
| Context menu | Left click = panel, right click = `NSMenu` (Settings…, Quit) | **Convention** | Common and good. Keep Settings… (⌘,) and Quit (⌘Q) in the panel footer too ([AGENTS.md › Panel vs Settings](../../AGENTS.md#panel-vs-settings-window-user-preference)): HIG Context Menus says context menu items must also exist in the main interface. |
| Motion | < 150 ms fade + scale 0.96 → 1.0; 0 ms hover | **Convention** | HIG Motion: brief, cancelable, and optional. Check `accessibilityDisplayShouldReduceMotion` and drop the scale when it is on. |
| Performance | ~0% idle CPU; stop timers when hidden | **Apple** (spirit) / **Convention** (number) | WidgetKit and energy docs ask for minimal background work; 0.0% is a target, not a spec. Stop `TimelineView`, timers and meters on close; keep data polling only if the icon itself shows live data. |
| Dock | Hidden via `LSUIElement` | **Apple** | `LSUIElement` = "agent app … doesn't appear in the Dock"; `.accessory` activation policy is the runtime equivalent. `MenuBarExtra` docs: a menu-bar-only app is terminated if the user removes the extra. |

## What the table leaves out

- **People decide whether the icon is in the menu bar.** HIG: "Let people — not your app — decide whether to
  put your menu bar extra in the menu bar", and "Avoid relying on the presence of menu bar extras": the system
  hides extras when space is short (the notch). Offer "Show in menu bar" in Settings and a second way in
  (a Dock menu, a window, a hotkey).
- **Menu bar height:** 24 pt (HIG), taller on notched Macs, usable item area 22 pt (see the 01 research).
- **Increase Contrast and Reduce Transparency:** test the panel with both on (HIG Dark Mode).

## Sources

- HIG: [The menu bar › Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras), [Popovers](https://developer.apple.com/design/human-interface-guidelines/popovers), [Panels](https://developer.apple.com/design/human-interface-guidelines/panels), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Motion](https://developer.apple.com/design/human-interface-guidelines/motion), [Context menus](https://developer.apple.com/design/human-interface-guidelines/context-menus)
- API: [`MenuBarExtra`](https://developer.apple.com/documentation/swiftui/menubarextra), [`NSPopover.Behavior.transient`](https://developer.apple.com/documentation/appkit/nspopover/behavior-swift.enum/transient), [`LSUIElement`](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement), [`NSApplication.ActivationPolicy.accessory`](https://developer.apple.com/documentation/appkit/nsapplication/activationpolicy-swift.enum/accessory), [`NSSpringLoadingDestination`](https://developer.apple.com/documentation/appkit/nsspringloadingdestination), [`accessibilityDisplayShouldReduceMotion`](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion)
