---
description: Build a new macOS screensaver (.saver) themed with Summon
argument-hint: <what it should show>
---

Build a screensaver that shows: $ARGUMENTS

Agree a short kebab-case name with the user, then start it from Summon's template:
`summon project new <name> --kind screensaver`. It lands in `~/Summon/Apps/<name>` with a `ScreenSaverView` subclass,
a tested Core for the animation and `scripts/bundle.sh` that assembles the `.saver`; work in that folder. Use the
`mac-app` skill, screensaver section: theme colors from `~/.config/summon/themes/$(summon theme current)/theme.json`, timers stopped in
`stopAnimation()`, a small configure sheet if it has options. `scripts/install.sh` copies it to
`~/Library/Screen Savers/`; have the user select it in System Settings › Screen Saver (macctl has no screen saver
setting yet). Check both the preview pane and the real saver (Hot Corner) before calling it done. Follow the
`mac-app` skill's steps 1–8. A private GitHub repo comes only with `summon default repos always` or when the user asks for one
(`summon project repo <name>`, approved in Summon's dialog). Never create or publish a repo yourself.
