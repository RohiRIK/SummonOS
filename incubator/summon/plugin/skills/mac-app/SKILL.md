---
name: mac-app
description: >
  Build a new native Mac app the Summon way: a menu bar app, a full window app, a screensaver,
  or an app icon. Swift 6 + SwiftUI, SwiftPM, follows the current Summon theme, ships as a signed .app.
  Use when asked to make, build, or scaffold an app, menu bar widget, utility, screensaver, or icon.
  Triggers: new app, menu bar app, status bar item, widget, screensaver, .saver, app icon, icns, "make me an app".
---

# Building a Mac app with Summon

Summon's apps are small on purpose: one job, keyboard first, themed by the current Summon theme,
and they launch instantly. Ask what the app should do if it is unclear and settle the one job.

## The full guides

This skill is the entry point. The detailed rules live in the `RohiRIK/macos-plugins` workspace skills;
use them when you are working inside that workspace (or have them installed):

- `MacAppArchitecture`: pick the shape (menu, panel, window, NSPanel), layers, state, system tools, storage.
- `MacAppBuild`: scaffold, build, bundle, previews, verify, release.
- `MacUX`: panel and window design, HIG, Liquid Glass, settings window.

If they are not installed, follow the summary below.

## Pick the shape

| Ask | Shape |
|---|---|
| "show X in the menu bar", a status, a few actions | **Menu bar app**: `MenuBarExtra` (`.window` style panel), `LSUIElement = true` |
| A tool with its own window, documents, sidebars | **Full app**: `WindowGroup` + `NavigationSplitView`, Dock icon, menus with ⌘ shortcuts |
| Something to look at when idle | **Screensaver**: `.saver` bundle, `ScreenSaverView` subclass |
| An icon for an app, file, or folder | **Icon**: see below |

Every app gets a separate **Settings window** (`Settings` scene, `.formStyle(.grouped)`), opened with ⌘,.
Settings never go inside the menu bar panel; the panel footer has `Settings…` and `Quit` only.

## Where new apps go

New apps start in the plugin home, `$MACPLUGINS_HOME` (default `~/Developer/macplugins`, the
`macos-plugins` workspace clone), under `scratch/<name>/`. When the workspace's `mp` tool is available,
create the app with it; it copies the menu bar starter, renames it, and registers it in `plugins.json`:

```bash
mp="${MACPLUGINS_HOME:-$HOME/Developer/macplugins}/tools/mp"
"$mp" new <name> --kind menubar        # or --kind app / --kind screensaver (starts from the menu bar starter)
```

Without `mp`, create `$MACPLUGINS_HOME/scratch/<name>/` by hand with the layout below. Never create GitHub
repos yourself: `mp promote <name>` needs the owner's OK every time.

## Layout (SwiftPM, no .xcodeproj)

```
$MACPLUGINS_HOME/scratch/<name>/
├── Package.swift            swift-tools-version 6.0, platforms [.macOS(.v15)]
├── Sources/<App>/           @main only
├── Sources/<App>UI/         views, @Observable model, #Previews (library product, so previews run)
├── Sources/<App>Core/       logic and tool wrappers, Foundation only, tested
├── Tests/<App>CoreTests/    swift-testing
├── Resources/Info.plist     bundle id local.macplugins.<name>
└── scripts/                 test.sh, bundle.sh (builds the .app), check.sh (the gate)
```

Rules: Swift 6 strict concurrency, `@MainActor` UI, no third-party dependencies, shell tools by
absolute path with argv arrays (never a shell string), Core logic test-first. Build caches in
`~/Library/Caches/macplugins/<name>`.

## Follow the Summon theme

Read `~/.config/summon/current/theme.json` at launch and when the file changes (a
`DispatchSource` file watcher), and apply `accent` as `.tint`, `appearance` as `preferredColorScheme`.
Colors: `background`, `foreground`, `accent`, `accent2`, `muted`, `selection`.

## Screensaver specifics

- A `.saver` is a bundle with `NSPrincipalClass` = your `ScreenSaverView` subclass. SwiftPM builds a
  dynamic library; `scripts/bundle.sh` assembles `<Name>.saver/Contents/{Info.plist,MacOS/<Name>}`.
- macOS 14+ hosts third-party savers in `legacyScreenSaver`. Known traps: the process outlives the saver,
  so stop timers and display links in `stopAnimation()` and on `NSNotification.Name("com.apple.screensaver.willstop")`;
  `isPreview` views are tiny; never block `animateOneFrame()`.
- Draw with Core Animation or Metal, or host SwiftUI with `NSHostingView`. Respect the theme colors.
- Install: copy to `~/Library/Screen Savers/`, then let the user pick it in System Settings › Screen Saver.
  macctl has no screen saver setting yet, so selecting it from the shell is a raw `defaults -currentHost`
  write (Summon rule 1: only with the user's yes, and report the command).

## Icons

- App icon: a 1024×1024 master on Apple's grid (content inside the 824×824 rounded square), then
  `iconutil -c icns <Name>.iconset` from a `.iconset` folder with 16, 32, 128, 256, 512 at @1x and @2x.
  On macOS 26 also export an Icon Composer `.icon` for light, dark, and tinted variants.
- Menu bar icon: a template image (black on transparent, 18 pt with @2x), `isTemplate = true`.
- Put an icon on any file, folder, or app: `NSWorkspace.shared.setIcon(image, forFile: path, options: [])`
  (apps in `/Applications` may need admin and lose it on update; `summon` re-applies after updates).
- Summon's own mark and generator are in `design/` of the Summon repo; reuse its look for a family feel.

## Verify before calling it done

`scripts/check.sh` passes (build + tests), the app launches from the bundle, every screen and setting
is reachable, and the user saw it run. Then add it to the Summon Menu (`~/.config/summon/menu.jsonc`) if it
has an action worth summoning.
