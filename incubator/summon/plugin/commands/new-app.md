---
description: Build a new native Mac app with its own window
argument-hint: <what the app is for>
---

Build a new full Mac app (window app with a Dock icon) for: $ARGUMENTS

Agree a short kebab-case name with the user, then start it from Summon's template:
`summon project new <name> --kind app`. It lands in `~/Summon/Apps/<name>` with a `WindowGroup` + `NavigationSplitView`,
menu commands and a Settings window already wired; work in that folder. Use the `mac-app` skill (shape: full app):
menus and ⌘ shortcuts for every action, the Summon theme, Core logic test-first, `PROJECT-CONTEXT.md` kept current.
Done when `scripts/check.sh` passes and the bundled app launches. Never create a GitHub repo yourself: if the user
wants one, run `summon project repo <name>` and they approve it in Summon's dialog.
