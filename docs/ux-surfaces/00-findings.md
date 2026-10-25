---
type: Research
title: "Surface table: findings and rules for every surface"
description: "What checking the surface table against Apple's docs found: the corrections, the rules every surface shares, and answers to open questions from the skills."
tags: [design, ux, surfaces, hig]
created: 2026-10-25
---

# Surface table: findings and rules for every surface

The [surface table](surface-table.md) was checked cell by cell against Apple's Human Interface Guidelines
(the HIG pages' Markdown) and the AppKit, SwiftUI and WidgetKit reference (developer.apple.com documentation
JSON) on 2026-10-25. One page per surface has the details:
[menu bar](01-menu-bar.md), [desktop app](02-desktop-app.md), [Settings](03-settings-window.md),
[launcher](04-command-launcher.md), [HUD](05-floating-hud.md), [onboarding](06-onboarding.md),
[system extensions](07-system-extensions.md).

**Overall:** the table's philosophy, window anatomy, focus and Dock rows match Apple. Most pixel sizes,
timings and opacity numbers are good conventions with no Apple source, so treat them as starting values, not
rules. Ten cells contradict Apple or our own rules.

## Corrections to the table

| # | Surface | Table says | Correct rule | Source |
|---|---|---|---|---|
| 1 | Menu bar | Click opens a popover | Prefer a **menu**; use a panel only when a menu can't hold the job | HIG Menu bar extras |
| 2 | Settings | Minimize enabled, only full screen off | **Dim minimize and zoom**; close only | HIG Settings › macOS |
| 3 | Settings | Light/Dark/System override | **No app-only appearance setting** | HIG Dark Mode |
| 4 | Settings | 680 pt with a sidebar | **760–820 pt** with a sidebar (owner's preference, 2026-09-30); Apple gives no number and sizes the window to the pane | `MacUX/MenuPanel.md`, HIG Settings |
| 5 | Launcher | Summoned by ⌘Space | ⌘Space is **reserved for Spotlight**; default ⌥Space or none, user-recordable | HIG Keyboards |
| 6 | HUD | Floats without stealing focus | Also set `hidesOnDeactivate = false`: panels hide when their app deactivates by default | `NSWindow.hidesOnDeactivate` |
| 7 | Onboarding | "Skip for now" on permission cards | **One button (Continue/Next)** before a system permission alert; Skip only where no alert follows | HIG Privacy |
| 8 | Onboarding | Secure permissions during setup | Ask in setup only for what the app can't work without; the rest **when first used** | HIG Privacy, HIG Onboarding |
| 9 | Extensions | Notch is an OS-defined container | **No notch API**; it's your own window, sized from `auxiliaryTopLeftArea`/`RightArea`, with a fallback for screens without a housing | `NSScreen` docs |
| 10 | Extensions | ~30–50 MB RAM caps | **Not documented** for macOS; WidgetKit documents a **refresh budget** (40–70 reloads a day) instead | WidgetKit docs |

## Rules every surface shares (missing from the table)

- **Accessibility settings:** honor Reduce Motion (`NSWorkspace.accessibilityDisplayShouldReduceMotion`),
  Reduce Transparency and Increase Contrast; never use color alone for state; label icon-only buttons for
  VoiceOver. Contrast at least 4.5:1, 7:1 for small custom text (HIG Dark Mode, Accessibility).
- **Text styles, not point sizes:** macOS default text is 13 pt and the minimum is 10 pt (HIG Typography).
  macOS styles: Large Title 26, Title 1 22, Title 2 17, Title 3 15, Headline 13 bold, Body 13, Callout 12,
  Subheadline 11, Footnote/Caption 10. macOS has no Dynamic Type.
- **Liquid Glass (macOS 26) belongs to controls and navigation, not content** (HIG Materials). Regular glass
  for anything with text; clear glass only over rich media. Pre-26 fallbacks: `NSVisualEffectView` materials
  (`.popover`, `.sidebar`, `.hudWindow`, `.menu`).
- **Standard shortcuts first:** ⌘, Settings, ⌘W close, ⌘Q quit, ⌘F find, ⌃⌘F full screen. Custom global
  hotkeys are user-recordable and avoid the reserved list (HIG Keyboards).
- **Undo over confirmation:** HIG Alerts says not to alert for common undoable actions; make the action
  undoable instead.
- **Our own split stays:** live data and actions in the panel, every preference in the Settings window
  ([AGENTS.md](../../AGENTS.md#panel-vs-settings-window-user-preference)).

## Answers to open questions from the skills

| Question | Answer |
|---|---|
| Settings window width (skills say 580, 760–820, 600) | Apple: no number, sized per pane. Ours: sidebar Settings 760–820 × min 520 (owner's call); toolbar-tab Settings sized to each pane, about 500–600. The 580 in `MacUX/SKILL.md` is out of date for sidebar Settings. |
| Launcher hotkey | Not ⌘Space (Spotlight). ⌥Space or none by default, recordable, registered with `RegisterEventHotKey` (no permission prompt). |
| Notch true black and housing width | Black is convention. Width comes from `NSScreen.auxiliaryTopLeftArea` / `auxiliaryTopRightArea`; no Apple notch API. |
| Widget / Finder extension memory caps | Not documented for macOS. Plan for the documented WidgetKit refresh budget. |
| Should Settings disable full screen? | Yes, and minimize too (HIG: "Dim a settings window's minimize and maximize buttons"). |

## Method and limits

- Sources fetched 2026-10-25: HIG pages as Markdown (`developer.apple.com/design/human-interface-guidelines/<page>.md`)
  and API pages as documentation JSON. Every **Apple** verdict quotes or paraphrases one of them.
- **Convention** verdicts rest on widely used apps (Spotlight, Raycast, Alfred, Control Center, iOS PiP) and
  our [earlier GUI research](../research/2026-10-18-mac-gui-design/README.md); none of them were measured
  on a Mac for this pass.
- Not checked on a real Mac yet: the HUD focus combination, the launcher over full-screen apps, and the
  notch-area numbers. The Summon audit should confirm them in the running app.
