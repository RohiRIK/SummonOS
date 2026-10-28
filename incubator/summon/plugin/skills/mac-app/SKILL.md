---
name: mac-app
description: >
  Build a new native Mac app the Summon way: a menu bar app, a full window app, a command launcher, a floating
  HUD, a notch app, a desktop widget, a command-line tool, a screensaver, or an app icon. Starts from Summon's template in ~/Summon/Apps/<name>; Swift 6 + SwiftUI, SwiftPM,
  follows the current Summon theme. Use when asked to make, build, or scaffold an app, menu bar widget, utility,
  CLI tool, screensaver, or icon. Triggers: new app, menu bar app, status bar item, widget, launcher, Spotlight-style,
  command bar, HUD, overlay, always on top, notch, command-line tool, CLI, screensaver, .saver, app icon, icns,
  "make me an app".
---

# Building a Mac app with Summon

Summon's apps are small on purpose: one job, keyboard first, themed by the current Summon theme, and they launch
instantly. Follow the steps in order. Do not skip one, and do not call the app done before step 8.

Every project lives in `~/Summon/Apps/<name>` and starts from Summon's template. Never hand-scaffold a project,
copy another app's folder, or start one anywhere else. If the `MacAppArchitecture`, `MacUX` or `LiquidGlass` skills
are installed, use them for depth; this skill is enough on its own.

## The steps

### 1. Agree the name, the kind and the repo

- Settle the app's one job with the user. Ask if it is unclear.
- Agree a short kebab-case name (`a-z`, `0-9`, `-`; for example `mac-battery`). It becomes the folder, the
  bundle id `local.summon.<name>`, and the PascalCase type name (`MacBattery`).
- Pick the kind. The kinds this Summon knows are the ones `summon project new` prints when run with no arguments
  (also `summon commands`). Today: `menubar`, `menubar-panel`, `launcher`, `hud`, `notch`, `app`, `widget`,
  `cli` and `screensaver`; use only the ones it lists.

  | Ask | Kind |
  |---|---|
  | Show something in the menu bar, a status, a few actions | `menubar` (or `menubar-panel` for a bigger panel, one opened from a hotkey, or typing) |
  | A shortcut that opens a search bar over any app: find, pick, run, vanish | `launcher` |
  | A small panel that stays on top while you work elsewhere (timer, recording bar, meter) | `hud` |
  | Something that grows out of the MacBook's camera housing on hover | `notch` |
  | A tool with its own window, documents, a sidebar | `app` |
  | Something to run in a terminal, from scripts or agents | `cli` |
  | Something to look at when the Mac is idle | `screensaver` |
  | Only an icon for an app, file or folder | no project: go to step 7 |
  | A glanceable view on the desktop or in Notification Center | `widget` (needs Xcode; see its README) |
  | A Finder extension | no template (Finder Sync needs its own extension); tell the user |

  Each kind follows the SummonOS surface rules (sizes, focus, keys, materials, Apple's corrections):
  https://github.com/RohiRIK/SummonOS/tree/main/docs/ux-surfaces. Read the page for the kind before changing
  its window or panel.

- Run `summon default repos` and tell the user what it prints:
  - `ask` (the default): no GitHub repo is made. A repo comes only from step 8, if the user wants one.
  - `always`: `summon project new` also creates a private GitHub repo and pushes to it right away.

### 2. Create the project

```bash
summon project new <name> --kind <kind>
cd "$(summon project path <name>)"
```

This copies the template to `~/Summon/Apps/<name>`, renames `Starter` to `<App>` (the PascalCase name), makes a
git repo with a first commit, and records the project in Summon's private list (`summon project list`). Read the
output. With `always`, if it says the app has no repo yet (gh missing or not logged in), tell the user. Never run
`gh repo create` or push to a new remote yourself.

Layout (SwiftPM, no `.xcodeproj`): `Sources/<App>/` holds `@main` only, `Sources/<App>UI/` the views, the
`@Observable` model and `#Preview`s, `Sources/<App>Core/` the logic (Foundation only, tested),
`Tests/<App>CoreTests/` swift-testing, `Resources/Info.plist`, and `scripts/`.

### 3. Write a Core test first, then the code

- New logic starts as a failing test in `Tests/<App>CoreTests/`, then the code in `Sources/<App>Core/` that makes
  it pass. The UI only calls Core.
- Rules: Swift 6 strict concurrency, `@MainActor` UI, no third-party dependencies, shell tools by absolute path
  with argv arrays (never a shell string), minimum macOS 15. A `Regex` literal can't be a stored `static let`
  (not `Sendable`): make it a computed `static var`.
- Onboarding: the template's welcome window is only for an app that needs a permission (Accessibility, Screen
  Recording, Automation…) or when the user asks for one. Otherwise delete it in this step: `Onboarding.swift`,
  `OnboardingFlow.swift` and its test, the `Window` scene, `.showsOnboardingOnFirstLaunch()` and
  `ShowWelcomeButton()` (owner, 2026-10-26).
- The panel (or main window) is the app's job: live data, lists, and actions on them. Its footer has `Settings…`
  (⌘,) and `Quit` (⌘Q) rows and nothing else.
- Every preference lives in `SettingsView` (the `Settings` scene, opened from `Settings…`), never in the panel.
  Fewer than 3 sections: one `Form` with `.formStyle(.grouped)`. 3 sections or more: a sidebar
  (`NavigationSplitView`) with one grouped `Form` per section.
- Glass only on controls, never on content, and only behind `if #available(macOS 26, *)`.
- Follow the Summon theme (see "The Summon theme" below).
- Log with `Logger(subsystem: "local.summon.<name>", category: "<area>")`, the app's bundle id as the subsystem.
- Idle costs nothing: follow "Efficiency" below for every timer, loop, animation and background job.

### 4. Run the gate

```bash
scripts/check.sh
```

It must be green. It builds, runs the tests, lints the plist, bundles, and writes `build/check-report.md`; a
failing step names its log in `build/`. When `scripts/test.sh` is present, `check.sh` uses it to run the tests,
so the gate also works with only the Command Line Tools (no Xcode). Fix the cause; never skip a step.

### 5. Run it and read its logs

For `menubar`, `menubar-panel`, `launcher`, `hud`, `notch`, `app` and `widget` (a widget: run the app once, then
right-click the desktop › Edit Widgets… and add it):

```bash
scripts/bundle.sh && open build/<App>.app
pgrep -fl <App>
log show --last 5m --predicate 'subsystem == "local.summon.<name>"'
log show --last 5m --predicate 'process == "<App>"'
```

`pgrep` must show the process. The first `log show` shows the app's own `Logger` lines, the second also system
messages about it. Then test it with the `mac-app-test` skill: model tests, every way in (launch, My Apps, the
icon, the hotkey, opening it again), windows, logs, idle CPU, and a click-through the user does when you can't click. The
app is not done until that skill's report is green.
For `cli`: run the built tool with real arguments and `--help`; `scripts/install.sh` puts it in `~/.local/bin`.
For `screensaver`: `scripts/install.sh` copies it to `~/Library/Screen Savers/`; check the preview pane in
System Settings › Screen Saver and the real saver (a Hot Corner).

### 6. Take the screenshots and look at them

```bash
summon project shots <name>
```

It builds the app and writes `docs/screenshots/` (menu bar apps: `panel-light.png` and `panel-dark.png`, drawn
by `<App> --screenshot <folder>`; window apps: `window.png`; a CLI: its `--help` in the README), adds them to the
README and commits. Screensavers are not captured: take the picture in System Settings. Open every PNG and check:

- The panel is 300–320 pt wide, and nothing is clipped.
- One control per row, labels aligned, real-looking data (keep `Screenshots.swift` working when the panel changes).
- The footer is the `Settings…` and `Quit` rows, and no setting appears in the panel.
- Glass only on controls, behind `if #available(macOS 26, *)`. Light and dark both read well.

Fix what fails, then run steps 4 and 6 again.

`--screenshot` draws views in an offscreen window: a `NavigationSplitView` or `List` comes out blank there. Capture
the panel (and other plain stacks) that way, and check such windows by running the app.

### 7. Make the icon

Use the `summon-art` skill (its `icons.md`) for the art: three concepts in the theme's colors, the user picks
one. Then turn the 1024×1024 PNG into `Resources/AppIcon.icns`:

```bash
mkdir -p build/AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon.png --out build/AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) icon.png --out build/AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
```

If `scripts/bundle.sh` does not copy it yet, add `cp Resources/AppIcon.icns "$APP/Contents/Resources/"` before
its `codesign` line, and `<key>CFBundleIconFile</key><string>AppIcon</string>` to `Resources/Info.plist`.
Run step 4 again. For light, dark and tinted variants on macOS 26, also export an Icon Composer `.icon` from the
same art. A menu bar icon is different: an SF Symbol, or a template image (black on transparent, 18 pt
with @2x, `isTemplate = true`).

### 8. Finish

- Update `PROJECT-CONTEXT.md`: what the app does, its key files, its constraints, and a dated Recent History entry.
  Commit the change.
- Repo: only if the user wants one (and `summon default repos` is `ask`), run `summon project repo <name>`. The user
  approves it in Summon's dialog; the repo is private, with CI that runs `scripts/check.sh`. Never make a repo
  public; a public copy is the user's separate choice.
- Show the user the running app. Then offer two things:
  - The Summon Menu: registered menu bar and window apps already appear under My Apps
    (`summon project open <name>`). For a custom entry, add an item with an `action` to
    `~/.config/summon/menu.jsonc` (see the `summon-mac` skill).
  - Open at Login: a toggle in the Settings window with `SMAppService.mainApp.register()` /
    `.unregister()`, or System Settings › General › Login Items.

## Efficiency

A Summon app runs all day next to everything else. When nobody looks at it, it should use no CPU and wake the Mac
as little as possible (`mac-app-test` measures it). `MacAppArchitecture`'s `System.md` has the longer version.

- Events, not polling: `NSWorkspace` notifications (app switches, `didWakeNotification`, `willSleepNotification`),
  `SCDynamicStore` for network changes, FSEvents or a `DispatchSource` file watcher for files, `IOPSNotificationCreateRunLoopSource`
  for power, `ProcessInfo.thermalStateDidChangeNotification` and `.NSProcessInfoPowerStateDidChange`.
- Poll only when no event exists: 1–2 s while the panel or window is open, 10–60 s otherwise, and stop on sleep
  (resume on wake).
- Give every timer slack: `Task.sleep(for:tolerance:)` or `Timer.tolerance`, at least 10% of the interval, so macOS
  can batch wakeups. Periodic background work (a sync, a cleanup) goes to `NSBackgroundActivityScheduler`.
- Background work runs at `.utility` or `.background` QoS; `.userInitiated` only while the user waits for it.
- Hidden means stopped: no `TimelineView`, animation or display link ticks while its window or panel is closed or
  occluded (`NSWindow.occlusionState`). Build the ticking view only while it is visible.
- The status item changes only when its value changes. No per-second text in the menu bar unless the user asks.
- No `repeatForever` animation while idle, and none at all with Reduce Motion on.
- Hotkeys: Carbon `RegisterEventHotKey` (as the templates do) or a local `NSEvent` monitor, never a global monitor
  that sees every keystroke.
- Launch light: draw the first frame, then scan, index or call the network. Cache results and refresh them when
  their source changes, not on every open.

## The Summon theme

The current theme's slug is in `~/.config/summon/current-theme` (`summon theme current` prints it). Its colors are
in `~/.config/summon/themes/<slug>/theme.json`: `appearance` (`dark` or `light`) and `colors.background`,
`foreground`, `accent`, `accent2`, `muted`, `selection` (`#RRGGBB`). Read them at launch and when
`current-theme` changes (a `DispatchSource` file watcher). Apply `colors.accent` as `.tint` and `appearance` as
`preferredColorScheme`. With no current theme, use the system look.

## Screensaver specifics

- A `.saver` is a bundle with `NSPrincipalClass` = your `ScreenSaverView` subclass (the template fixes its
  Objective-C name with `@objc(<App>View)`). `scripts/bundle.sh` assembles `<App>.saver/Contents/{Info.plist,MacOS/<App>}`.
- macOS hosts third-party savers in `legacyScreenSaver`, and that process outlives the saver: stop timers and
  display links in `stopAnimation()` and on `NSNotification.Name("com.apple.screensaver.willstop")`. `isPreview`
  views are tiny. Never block `animateOneFrame()`.
- Draw with Core Animation or Metal, or host SwiftUI with `NSHostingView`, in the theme's colors.
- macctl has no screen saver setting yet: the user picks it in System Settings › Screen Saver. Selecting it from
  the shell is a raw `defaults -currentHost` write: only with the user's yes, and report the command.

## Icons on other things

Put an icon on any file, folder or app with `NSWorkspace.shared.setIcon(image, forFile: path, options: [])`.
Undo: Get Info, select the icon, Delete. Apps in `/Applications` may need admin and lose the icon on update.
