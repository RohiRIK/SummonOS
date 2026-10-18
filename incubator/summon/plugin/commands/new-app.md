---
description: Build a new native Mac app with its own window
argument-hint: <what the app is for>
---

Build a new full Mac app (window app with a Dock icon) for: $ARGUMENTS

Use the `mac-app` skill (shape: full app). Create it in `$MACPLUGINS_HOME/scratch/<name>` (default `~/Developer/macplugins/scratch/<name>`) with a
kebab-case name, using `mp new <name> --kind app` when the `mp` tool is available (see the `mac-app` skill);
never promote it to GitHub repos yourself.
Replace the starter's `MenuBarExtra` with `WindowGroup` + `NavigationSplitView` where it fits, menus and ⌘
shortcuts for every action, a Settings window, the Summon theme. Core logic test-first. Done when
`scripts/check.sh` passes and the bundled app launches.
