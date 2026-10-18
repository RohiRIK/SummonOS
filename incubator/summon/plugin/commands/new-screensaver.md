---
description: Build a new macOS screensaver (.saver) themed with Summon
argument-hint: <what it should show>
---

Build a screensaver that shows: $ARGUMENTS

Use the `mac-app` skill, screensaver section. Create it in `$MACPLUGINS_HOME/scratch/<name>` (default `~/Developer/macplugins/scratch/<name>`) with a
kebab-case name, using `mp new <name> --kind screensaver` when the `mp` tool is available (see the `mac-app` skill);
never promote it to GitHub repos yourself.
Replace the starter's app targets with a `ScreenSaverView` bundle assembled by `scripts/bundle.sh`,
theme colors from `~/.config/summon/current/theme.json`, timers stopped in `stopAnimation()`, a small
configure sheet if it has options. Install it to `~/Library/Screen Savers/` and have the user select it in
System Settings › Screen Saver (macctl has no screen saver setting yet). Check both the preview pane and the
real saver (Hot Corner) before calling it done.
