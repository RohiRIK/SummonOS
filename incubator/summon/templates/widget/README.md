# Starter

A desktop and Notification Center widget: a countdown to a date the person picks with Edit Widget, plus the small
app that carries it. Made with Summon from its widget template, to the SummonOS surface rules for system
extensions (`docs/ux-surfaces/07-system-extensions.md` in the SummonOS workspace).

## Behavior

| What | How |
|---|---|
| Widget | Small and medium; one bold number (days left or since), a live timer on the day itself |
| Configure | Right-click the widget › Edit Widget: title and date (`AppIntentConfiguration`); no date shows "Choose a date" |
| Updates | A timeline entry at each midnight and at the target (at most 8, then `.atEnd`); no polling, well inside WidgetKit's daily budget |
| Look | System fonts, semantic colors, `.widgetAccentable()` on the number, so the desktop's tinted mode reads well |
| App | One window: previews and how to add the widget, Reload Widgets (⌘R); closing it quits the app |
| Settings | ⌘,; close only, 480 pt, changes apply at once |

## Layout

This template is the one SummonOS exception to "SwiftPM, no .xcodeproj": a widget is an `.appex` bundle inside
the app, which only Xcode builds. The Xcode project stays small and holds no logic; everything else is a Swift package.

| Path | What it is |
|---|---|
| `Sources/StarterCore/` | Logic, Foundation only, tested: `Countdown` (phase, timeline dates), the widget kind |
| `Sources/StarterUI/` | `CountdownView` (the widget's face, also drawn in the app), the app window, Settings, `#Preview`s |
| `Sources/StarterUI/Screenshots.swift` | `--screenshot <folder>`: light and dark PNGs of the window, used by `summon project shots` |
| `Tests/StarterCoreTests/` | swift-testing |
| `Xcode/Starter.xcodeproj` | Two targets, app `Starter` and extension `StarterWidget`, both linking this package (`StarterKit`) |
| `Xcode/App/` | `@main` app, `AppIcon.icns` (a placeholder: replace it with the summon-art skill) |
| `Xcode/Widget/` | The `WidgetBundle`, the Edit Widget intent, the timeline provider, widget previews |
| `Xcode/Config/` | Info.plist additions and the extension's sandbox entitlement (widgets must be sandboxed) |
| `scripts/check.sh` | The gate: package build and tests, plist lint, the Xcode build, the embedded and signed widget; writes `build/check-report.md` |

Bundle ids: `local.summon.widget-starter` for the app, `local.summon.widget-starter.widget` for the widget.
Files added to `Xcode/App/` or `Xcode/Widget/` join their target on their own (synchronized folders): no project edits.

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app (needs Xcode)
open build/Starter.app       # run it once so the widget appears in the gallery
```

Then right-click the desktop › Edit Widgets… and search for Starter. Or open `Xcode/Starter.xcodeproj` and run the
`Starter` scheme; widget previews are in `Xcode/Widget/StarterWidget.swift`.

Requires macOS 15+, Swift 6 and Xcode. No third-party dependencies.
