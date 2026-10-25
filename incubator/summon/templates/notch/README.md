# Starter

A notch app: a black panel over the MacBook's camera housing that grows down out of it when the pointer or a
dragged file comes near. `LSUIElement`, no Dock icon, a small menu bar menu that people can hide. Made with Summon
from its `notch` template. The starter's job is a shelf: drop files into the notch to keep them close, drag them
out again later. Replace it with your own glanceable thing and keep the panel.

Built to the SummonOS surface rules for system extensions (`docs/ux-surfaces/07-system-extensions.md` in the
SummonOS workspace). **Apple has no notch API:** this is an ordinary borderless window above the menu bar, placed
from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea`, with a fallback for screens without a housing.

## Behavior

| What | How |
|---|---|
| Where | The screen whose `auxiliaryTopLeftArea`/`RightArea` exist; the housing is the gap between them (`NotchGeometry`) |
| No notch | An external display or older Mac: a small pill under the menu bar of the main screen, or nothing (Settings) |
| Closed | A true-black shape exactly the housing's size, so it disappears into it |
| Opens | When the pointer enters (an `.activeAlways` tracking area, so it works while another app is active) or a file is dragged over it |
| Closes | 0.3 s after the pointer and the drag have left |
| Motion | Grows out of the housing with a slight overshoot; Reduce Motion: no animation |
| Shelf | Newest first, no duplicates, at most 24; holds locations only (never copies); missing files drop off at launch |
| Files | Drag out to use (it stays on the shelf), click to open, right-click: Open, Show in Finder, Remove from Shelf |
| Focus | Never key, never activates the app; on every Space; out of Mission Control and ⌘\` |
| Settings | Open at Login, Show in menu bar, Show on displays without a notch |
| Reopen | Opening the app again from the Finder shows Settings: the way back when the menu bar item is hidden |

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the invisible opener window and the `Settings` scene |
| `Sources/StarterUI/NotchPanel.swift` | `NotchPanel` (`NSPanel` allowed into the menu bar), the hover-tracking host, `NotchController` |
| `Sources/StarterUI/NotchView.swift` | The black shape, the shelf, file tiles |
| `Sources/StarterUI/StarterModel.swift` | The shelf (saved in UserDefaults), open state with the close grace period |
| `Sources/StarterUI/AppDelegate.swift` | Creates the panel and the menu bar menu, applies Settings |
| `Sources/StarterUI/StatusMenu.swift` | `ActionMenu` (an `NSMenu` built from closures) and the menu bar item |
| `Sources/StarterUI/SettingsOpener.swift` | Opens the Settings window from AppKit code |
| `Sources/StarterUI/SummonTheme.swift`, `Glass.swift` | `.themed()` (the Summon theme's accent) and `.glassControl()` |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: the open panel and Settings to PNGs, for `summon project shots` |
| `Sources/StarterCore/` | `NotchGeometry`, `Shelf`, `SummonThemeFile`; Foundation only, tested |
| `Resources/` | `Info.plist` (bundle id `local.summon.notch-starter`, `LSUIElement`), `AppIcon.icns` |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, works without Xcode), plist, bundle |

Check on a Mac with a notch and on one without: the housing's numbers come from the system, but nobody has
measured this panel against a real cutout yet.

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
