---
name: mac-app-test
description: >
  Test a Mac app made with Summon before calling it done: Core and model tests, the gate, every way to open it
  (launch, My Apps / summon project open, the menu bar icon, its hotkey, opening it again in the Finder), its
  windows, its logs, its screenshots, and a click-through for what an agent can't click. Nothing ships untested.
  Use after building or changing an app in ~/Summon/Apps, and whenever asked to test, verify, QA or check an app.
  Triggers: test the app, verify, QA, does it work, check it, before done, ship it.
---

# Testing a Summon app

An app is done only when every step below is green or the user has confirmed the part an agent can't do. Run
them in order, in the project folder (`cd "$(summon project path <name>)"`). The `mac-app` skill calls this one
at its step 5; it also stands alone for any later change.

## 1. Tests for the logic

- Every function in `Sources/<App>Core/` has a swift-testing test in `Tests/<App>CoreTests/`: the normal case, an
  empty input, a bad input, and the edge that would lose data (a line that isn't a task, a missing folder, an id
  that would escape the folder).
- Decisions in the `@Observable` model (what is selected after a delete, when an edit is saved, what typing into
  nothing does) are logic too. Move them to Core, or add a `<App>UITests` test target for the model
  (`.testTarget(name: "<App>UITests", dependencies: ["<App>UI"])`, `@MainActor` tests) with its store in a
  temporary folder.
- A panel or window that sizes itself from SwiftUI gets a size test: host the view exactly as the app does (same
  `NSHostingView`, same `sizingOptions`, same background) and expect a real `fittingSize`, with data and empty.
  `.preferredContentSize` alone reports 0 × 0, and the icon click then shows nothing.
- Storage is tested against a temporary folder, never the user's real data, and through a second model or store
  instance, so a test proves the data comes back after a relaunch.
- A test fails first: break the code on purpose once, see the test fail, then put it back.

## 2. The gate

`scripts/check.sh` must be green (build, tests, plist, bundle). Read the test count in `build/tests.log`; a count
that didn't grow with the new code means the new code has no tests.

## 3. Every way in

Quit any running copy first (`pkill -f build/<App>.app`), so each check proves its own path. For each, confirm the
process with `pgrep -fl <App>` and the window with `swift windows.swift <pid>` (the helper next to this
`SKILL.md`, also in `$(summon path)/skills/mac-app-test/`; it needs no Screen Recording).

| Path | How to run it | What must happen |
|---|---|---|
| Launch | `open build/<App>.app` | Process starts. A menu bar app shows no window and no Dock icon. |
| My Apps | `summon project open <name>` (what My Apps in Summon's panel runs) | The same app starts. |
| Menu bar icon | Click it (needs Accessibility for an agent; else step 7) | The panel opens under it; a second click, Esc and a click elsewhere close it. |
| Hotkey / URL | Press it, or `open <scheme>://…` | Opens the same panel or window. |
| Open again | `open build/<App>.app` while it runs | Shows the main or editor window (the way in when the icon is hidden). |
| Settings | ⌘, from the panel, or the right-click menu | The Settings window opens in front. |
| Every window | Each button that opens one | A window with a sane size appears; closing it brings the menu bar app back to no Dock icon. |

## 4. Logs

```bash
log show --last 5m --predicate 'subsystem == "local.summon.<name>"'
log show --last 5m --predicate 'process == "<App>"' | grep -iE "error|fault"
```

No error or fault lines that the app caused. A failure the app logged must also show in its UI.

## 5. Screenshots

`summon project shots <name>`, then open every PNG (light and dark). Check the panel width, clipping, real-looking
data, and the footer. `--screenshot` draws offscreen, where a `NavigationSplitView` or `List` comes out blank:
check those windows by running the app, never from a blank shot.

## 6. Permissions and first run

- Only an app that needs a permission has a welcome window (the `mac-app` skill). Test it from a fresh state:
  `defaults delete local.summon.<name>`, then launch.
- Each permission: denied, then granted while the app runs; the app notices without a relaunch.

## 7. What the user clicks

An agent without Accessibility can't click the menu bar or type into the app. Then give the user a short numbered
list (open the panel, do the app's job once, switch, quit and reopen, check the data came back) and do not call
the app done until they answer. Fix what they report, then run steps 2–5 again.

## 8. Report

Say what passed and how (counts, commands), what the user confirmed, and what was not tested and why. Never say
"works" for a path nobody ran.
