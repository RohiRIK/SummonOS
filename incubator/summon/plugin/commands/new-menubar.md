---
description: Build a new native menu bar app for this Mac
argument-hint: <what it should show or do>
---

Build a new menu bar app that does this: $ARGUMENTS

Agree a short kebab-case name with the user, then start it from Summon's template:
`summon project new <name> --kind menubar`. It lands in `~/Summon/Apps/<name>` (bundle id `local.summon.<name>`) and is
recorded in Summon's private project list; work in that folder. Use the `mac-app` skill (shape: menu bar app).
Follow the Summon theme, keep settings in the Settings window, write Core tests first, update
`PROJECT-CONTEXT.md`, and follow the skill's steps 1–8:
done when `scripts/check.sh` passes, the bundled app runs and the screenshots look right.
A private GitHub repo comes only with `summon default repos always` or when the user asks for one
(`summon project repo <name>`, approved in Summon's dialog). Never create or publish a repo yourself.
Then offer to add it to the Summon Menu and to Open at Login.
