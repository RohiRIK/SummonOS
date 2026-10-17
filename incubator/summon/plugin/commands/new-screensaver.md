---
description: Build a new macOS screensaver (.saver) themed with Summon
argument-hint: <what it should show>
---

Build a screensaver that shows: $ARGUMENTS

Use the `mac-app` skill, screensaver section: a `ScreenSaverView` bundle assembled by `scripts/bundle.sh`,
theme colors from `~/.config/summon/current/theme.json`, timers stopped in `stopAnimation()`, a small
configure sheet if it has options. Install it to `~/Library/Screen Savers/` and select it with
`macctl set screensaver.module <Name>`. Check both the preview pane and the real saver (`macctl` or
Hot Corner) before calling it done.
