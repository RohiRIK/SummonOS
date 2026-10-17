---
description: Build a new native Mac app with its own window
argument-hint: <what the app is for>
---

Build a new full Mac app (window app with a Dock icon) for: $ARGUMENTS

Use the `mac-app` skill (shape: full app): `WindowGroup` + `NavigationSplitView` where it fits, menus and ⌘
shortcuts for every action, a Settings window, the Summon theme. Core logic test-first. Done when
`scripts/check.sh` passes and the bundled app launches.
