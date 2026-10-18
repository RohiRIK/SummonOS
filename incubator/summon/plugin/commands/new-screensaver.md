---
description: Build a new macOS screensaver (.saver) themed with Summon
argument-hint: <what it should show>
---

Build a screensaver that shows: $ARGUMENTS

Agree a short kebab-case name with the user, then start it from Summon's template:
`summon project new <name> --kind screensaver`. It lands in `~/Summon/<name>` with a `ScreenSaverView` subclass,
a tested Core for the animation and `scripts/bundle.sh` that assembles the `.saver`; work in that folder. Use the
`mac-app` skill, screensaver section: theme colors from `~/.config/summon/current/theme.json`, timers stopped in
`stopAnimation()`, a small configure sheet if it has options. `scripts/install.sh` copies it to
`~/Library/Screen Savers/`; have the user select it in System Settings › Screen Saver (macctl has no screen saver
setting yet). Check both the preview pane and the real saver (Hot Corner) before calling it done. Never create a
GitHub repo yourself: if the user wants one, run `summon project repo <name>` and they approve it in Summon's dialog.
