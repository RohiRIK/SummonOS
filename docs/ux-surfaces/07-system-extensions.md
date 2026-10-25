---
type: Research
title: "Surface 7: system extensions"
description: "Widgets, Finder extensions, Quick Actions and notch apps, checked against WidgetKit, Finder Sync and NSScreen docs; the notch has no Apple API."
tags: [design, ux, surfaces, widgets, notch, finder]
created: 2026-10-25
---

# Surface 7: system extensions (notch, widgets, Finder)

Column 7 of the [surface table](surface-table.md), checked 2026-10-25. Verdicts as in
[Surface 1](01-menu-bar.md#surface-1-menu-bar-app-menubarextra--popover). This column mixes three very different
things, so treat them separately:

| Kind | Apple API | Process | Who draws it |
|---|---|---|---|
| **Widgets** (desktop, Notification Center) | WidgetKit, macOS 11; desktop widgets macOS 14 | Extension, run by the system on a timeline | The system renders your SwiftUI views |
| **Finder integration** | Finder Sync extension (badges, toolbar item, context menu in watched folders); Action/Share extensions; Shortcuts Quick Actions; Services | Extension or Shortcut | Finder |
| **Notch UI** | **None.** `NSScreen.safeAreaInsets` and `auxiliaryTopLeftArea`/`auxiliaryTopRightArea` (macOS 12) only tell you where the camera housing is | Your app's own borderless window | You |

## Corrections

1. **The notch is not a system surface.** Apple has no notch API; notch apps (NotchNook, Boring Notch,
   Hand Mirror) are ordinary borderless windows placed over the menu bar. Apple's guidance is the opposite:
   content behind the camera housing is obscured, and the system full screen avoids it (HIG Going full
   screen). Notch width = screen width − `auxiliaryTopLeftArea.width` − `auxiliaryTopRightArea.width`;
   `nil` areas mean the screen has no housing (external displays, older Macs), so the feature must fall back.
   True black `#000000` is a **convention** that hides the seam, not an Apple rule.
2. **No published memory caps for macOS extensions.** The table's "~30–50 MB" is folklore from iOS widgets;
   Apple's WidgetKit docs instead document a **refresh budget**: typically **40–70 reloads a day** for a
   frequently viewed widget (about every 15–60 minutes), and "widgets … don't support continuous, real-time
   updates". Design for that budget and keep the extension small anyway.
3. **Widget sizes are not fixed numbers.** WidgetKit: "The sizes of widgets may vary across devices … avoid
   using fixed values." Mac families: `systemSmall`, `systemMedium`, `systemLarge`, `systemExtraLarge`
   (macOS 14). Use the 16 pt standard margin (HIG Widgets).

## Cell by cell

| Dimension | Table says | Verdict | What to build |
|---|---|---|---|
| Philosophy | In-context power without opening the app | **Apple** | HIG Widgets: glanceable, relevant; no app-like layouts. |
| Window anatomy | Notch box, widget squares, Finder menu rows | **Apple** (widgets, Finder) / **Fix** (notch, see 1) | |
| Sizing | Widgets S/M/L; notch matches the housing width | **Apple** / see 1 and 3 | |
| Lifecycle | Widgets on timelines; notch on hover; Finder actions run headless | **Apple** (widgets, extensions) / **Convention** (notch) | `TimelineProvider`; reload from the app with `WidgetCenter.reloadTimelines(ofKind:)`, sparingly. |
| Materials | True black notch; widgets adapt to the wallpaper | **Convention** (notch) / **Apple** (widgets) | On the Mac desktop, widgets render full-color or *vibrant* (desaturated, tinted by the wallpaper when another window is in front). Use `.containerBackground(for: .widget)` and semantic colors. |
| Typography | Bold metrics 16–24, micro labels 10–11, no wrapping | **Apple** (close) | Never below 10 pt on macOS; `.minimumScaleFactor` over truncation; system fonts. |
| Controls | Interactive widget buttons (Sonoma+), drop/play in the notch | **Apple** (widgets) | Buttons and toggles through App Intents (macOS 14). "An interaction with a button or toggle should do more than open the app" — for opening, use `widgetURL` / `Link`. |
| Keyboard | Zero navigation | **Apple** | |
| Drag & drop | Drop files into the notch; Finder Quick Actions | **Convention** (notch) / **Apple** (Quick Actions) | Quick Actions come from Shortcuts or an Action extension; they appear in Finder's context menu and Preview pane. |
| Audio/video | Notch now-playing with waveform | **Convention** | No public now-playing read API for other apps' audio is guaranteed; check before promising it. |
| States | "Click to configure in app" when data/permission is missing | **Apple** | Widgets: show a placeholder and a clear action; HIG Widgets: previews and placeholders. |
| Context menu | Widget "Edit Widget…"; Finder Services/Quick Actions | **Apple** | Widget editing comes from `AppIntentConfiguration`; the system adds the menu. |
| Motion | Notch springs out of the cutout | **Convention** | Respect Reduce Motion. |
| Performance | Tiny RAM caps | **Fix** (see 2) | Small assets, cached on disk, App Group container for shared data. |
| Dock | No Dock presence | **Apple** | Extensions have none; a notch app is an `LSUIElement` app. |

## Sources

- HIG: [Widgets](https://developer.apple.com/design/human-interface-guidelines/widgets), [Going full screen › macOS](https://developer.apple.com/design/human-interface-guidelines/going-full-screen)
- API: [`WidgetFamily`](https://developer.apple.com/documentation/widgetkit/widgetfamily), [`systemExtraLarge`](https://developer.apple.com/documentation/widgetkit/widgetfamily/systemextralarge), [Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date), [Adding interactivity to widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities), [Finder Sync](https://developer.apple.com/documentation/findersync), [`NSScreen.safeAreaInsets`](https://developer.apple.com/documentation/appkit/nsscreen/safeareainsets), [`auxiliaryTopLeftArea`](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea-uglc)
