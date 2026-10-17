---
description: Build a new native menu bar app for this Mac
argument-hint: <what it should show or do>
---

Build a new menu bar app that does this: $ARGUMENTS

Use the `mac-app` skill (shape: menu bar app). Create it in `~/Work/<name>` with a kebab-case name and bundle
id `local.macplugins.<name>`, follow the Summon theme, give it a Settings window, write Core tests first, and
finish only when `scripts/check.sh` passes and the bundled app launches. Then offer to add it to the Summon Menu
and to Open at Login.
