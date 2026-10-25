---
type: Research
title: "Surface 6: onboarding"
description: "First-run setup and permission steps, checked against the HIG Onboarding and Privacy pages; Apple prefers short, optional, interactive onboarding."
tags: [design, ux, surfaces, onboarding, permissions]
created: 2026-10-25
---

# Surface 6: onboarding wizard (first-run flow)

Column 6 of the [surface table](surface-table.md), checked 2026-10-25. Verdicts as in
[Surface 1](01-menu-bar.md#surface-1-menu-bar-app-menubarextra--popover).

## What Apple says first

HIG Onboarding: "Ideally, people can understand your app … simply by experiencing it, but if onboarding is
necessary, design a flow that's **fast, fun, and optional**." It prefers **context-specific tips** (TipKit,
macOS 14) over one big flow, **teaching through interaction**, and **postponing nonessential setup**. A wizard
is right only when the app can't work without setup: for SummonOS that is permissions (Accessibility, Screen
Recording, Automation) and showing where a menu bar app lives.

## Two corrections

1. **Permission steps that open a system alert get one button.** HIG Privacy, for a custom screen shown before
   a system permission alert (camera, microphone, contacts, notifications…): "**Include only one button** and
   make it clear that it opens the system alert" (title it *Continue* or *Next*, not *Allow*), and "**don't
   provide a way … to leave the screen … without viewing the system alert** — like … close or cancel." So no
   "Skip for now" on those steps. "Skip" is fine on steps that only send people to System Settings
   (Accessibility, Screen Recording), where no alert exists, and on whole optional steps.
2. **Ask when the feature needs it, not all at launch.** HIG Privacy: "Avoid requesting permission at launch
   unless the data or resource is required for your app to function." Put only the permissions the core job
   needs in the wizard; ask for the rest the first time the feature is used.

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | 60-second setup: value, permissions, where the app lives | **Apple** (brief) | Keep it brief and optional; make it reachable later (HIG: offer a skipped tutorial again from help or settings). |
| Window anatomy | Centered, fixed, no minimize/zoom, step indicator at the bottom | **Apple** (auxiliary window) / **Convention** | HIG Windows: an *auxiliary* window is dedicated to one task. Close stays available: closing = skip, and the app must still work. |
| Sizing | 640 × 440 or 720 × 480, centered, fixed | **Convention** | `.windowResizability(.contentSize)`, `.defaultWindowPlacement` centered, `.restorationBehavior(.disabled)`. |
| Focus | Opens on first launch, then gives way to the menu bar or main app | **Convention** | Show it from a `Window` scene with `.defaultLaunchBehavior(.suppressed)` and open it yourself when a "completed" flag is unset. |
| Materials | Brand-forward with illustrations, gradients, short video | **Convention** | HIG allows a brief splash at the start of onboarding. Keep text on system backgrounds; no large downloads before people can use the app. |
| Typography | Hero 24–28 bold, subtitle 14–15 secondary, step labels 13 medium | **Apple** (close) | Large Title 26, Title 3 15, Body/Headline 13. WWDC25: onboarding text is bolder and leading-aligned. |
| Controls | Big Continue, permission cards with live checkmarks, "Skip for now" | **Apple** / **Fix** (skip, see correction 1) | Live status: poll `AXIsProcessTrusted()` / `CGPreflightScreenCaptureAccess()` when the app becomes active. |
| Keyboard | Enter/Space advances | **Apple** (default button) | Make Continue the default button (`.keyboardShortcut(.defaultAction)`); Space activates the focused control, it isn't "next". |
| Drag & drop | Optional "try dragging a file here" | **Apple** | HIG: "Teach through interactivity." |
| Audio/video | Live camera mirror and mic test in the permission step | **Apple** (spirit) | Shows the benefit right after the grant; only if the app records. |
| Permissions | Explain why before the system prompt; detect the toggle | **Apple** | HIG Privacy: purpose strings that say how the data is used; never a misleading pre-screen. |
| Context menu | None | **Apple** (spirit) | Keep the path single. |
| Motion | Slide between steps; bounce pointing at the menu bar icon at the end | **Convention** | The pointer to the icon is valuable for `LSUIElement` apps (HIG Menu bar extras: offer to add the extra during setup). Respect Reduce Motion. |
| Performance | Unload assets after finishing | **Convention** | Free by default if the window's views own them. |
| Dock | Temporarily in the Dock during setup, then hide | **Convention** | `setActivationPolicy(.regular)` while the window is open so people can find it after visiting System Settings, `.accessory` after. |

## Sources

- HIG: [Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [Privacy › Requesting permission](https://developer.apple.com/design/human-interface-guidelines/privacy#Requesting-permission), [Launching](https://developer.apple.com/design/human-interface-guidelines/launching), [The menu bar › Menu bar extras](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar#Menu-bar-extras)
- API: [TipKit](https://developer.apple.com/documentation/tipkit) (macOS 14), [`defaultLaunchBehavior(_:)`](https://developer.apple.com/documentation/swiftui/scene/defaultlaunchbehavior(_:)) (macOS 15), [`CGPreflightScreenCaptureAccess()`](https://developer.apple.com/documentation/coregraphics/cgpreflightscreencaptureaccess())
