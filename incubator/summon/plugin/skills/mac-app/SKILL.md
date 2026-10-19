---
name: mac-app
description: >
  Build a new native Mac app the Summon way: a menu bar app, a full window app, a command-line tool, a
  screensaver, or an app icon. Starts from Summon's template in ~/Summon/Apps/<name>; Swift 6 + SwiftUI, SwiftPM,
  follows the current Summon theme. Use when asked to make, build, or scaffold an app, menu bar widget, utility,
  CLI tool, screensaver, or icon. Triggers: new app, menu bar app, status bar item, widget, command-line tool,
  CLI, screensaver, .saver, app icon, icns, "make me an app".
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
| Something to run in a terminal or from scripts and agents | **CLI tool**: one executable, no UI |
| Something to look at when idle | **Screensaver**: `.saver` bundle, `ScreenSaverView` subclass |
| An icon for an app, file, or folder | **Icon**: see below |

Every app gets a separate **Settings window** (`Settings` scene, `.formStyle(.grouped)`), opened with ⌘,.
Settings never go inside the menu bar panel; the panel footer has `Settings…` and `Quit` only.

## Where new apps go: `~/Summon/Apps/<name>`

Every project starts from Summon's template for its kind and lives in its own folder under `~/Summon/Apps`
(Summon creates it on install and on every launch; agents start there). Agree a short kebab-case name with the
user, then:

```bash
summon project new <name> --kind menubar      # or app, cli, screensaver
cd "$(summon project path <name>)"
```

That copies the template, renames `Starter` to the PascalCase name, makes a git repo with a first commit, and
records the project in Summon's private list (`~/.config/summon/projects.json`, `summon project list`). The list
stays on this Mac: never add a Summon project to the workspace's `plugins.json` or anything public, and never use
the workspace's `mp new` / `mp promote` for it.

| Kind | Template gives you |
|---|---|
| `menubar` | `MenuBarExtra` panel with `Settings…`/`Quit` footer, Settings window, `LSUIElement` |
| `app` | `WindowGroup` + `NavigationSplitView`, menu commands with ⌘ shortcuts, Settings window |
| `cli` | One executable, argument parsing in a tested Core, `scripts/install.sh` into `~/.local/bin` |
| `screensaver` | `ScreenSaverView` subclass, tested animation Core, `scripts/bundle.sh` → `.saver`, `scripts/install.sh` |

Every template has `README.md`, `LICENSE` (MIT), `PROJECT-CONTEXT.md` (keep it current after each change) and
`scripts/check.sh` (the gate). No CI until the project has a repo.

**GitHub.** Never run `gh repo create` or push to a new remote yourself. When the user wants a repo, run
`summon project repo <name>`: Summon shows a native dialog, and only the user's click creates a **private** repo
(with CI that runs `scripts/check.sh`). Summon never makes a public repo; publishing later is the user's separate
choice, made only with the macos-plugins workspace's `tools/publish-public.sh` (noreply identity).

## Layout (SwiftPM, no .xcodeproj)

```
~/Summon/Apps/<name>/
├── Package.swift            swift-tools-version 6.0, platforms [.macOS(.v15)]
├── Sources/<App>/           @main only (main.swift for a CLI, the ScreenSaverView for a saver)
├── Sources/<App>UI/         views, @Observable model, #Previews (library product, so previews run)
├── Sources/<App>Core/       logic and tool wrappers, Foundation only, tested
├── Tests/<App>CoreTests/    swift-testing
├── Resources/Info.plist     bundle id local.summon.<name>
├── scripts/                 check.sh (the gate), bundle.sh (.app / .saver), install.sh (cli, saver)
├── README.md, LICENSE, PROJECT-CONTEXT.md
```

Rules: Swift 6 strict concurrency, `@MainActor` UI, no third-party dependencies, shell tools by
absolute path with argv arrays (never a shell string), Core logic test-first.

## Follow the Summon theme

Read `~/.config/summon/current/theme.json` at launch and when the file changes (a
`DispatchSource` file watcher), and apply `accent` as `.tint`, `appearance` as `preferredColorScheme`.
Colors: `background`, `foreground`, `accent`, `accent2`, `muted`, `selection`.

## Screensaver specifics

- A `.saver` is a bundle with `NSPrincipalClass` = your `ScreenSaverView` subclass (the template fixes its
  Objective-C name with `@objc(<Name>View)`). SwiftPM builds a dynamic library; `scripts/bundle.sh` assembles
  `<Name>.saver/Contents/{Info.plist,MacOS/<Name>}`.
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

## Screenshots

`summon project shots <name>` builds the app and puts light and dark pictures in `docs/screenshots/` plus a
Screenshots section in the README, and commits them; `summon project repo` runs it before the first push. Menu bar
apps from the template draw their own panel (`<App> --screenshot <folder>`): keep `Screenshots.swift` working when
you change the panel (show real-looking data in it). `summon showcase` collects every app into
`~/Summon/Showcase/index.html`.

## Verify before calling it done

`scripts/check.sh` passes, the app launches from the bundle, every screen and setting is reachable,
`PROJECT-CONTEXT.md` says what changed, and the user saw it run. Then add it to the Summon Menu (`~/.config/summon/menu.jsonc`) if it
has an action worth summoning.
