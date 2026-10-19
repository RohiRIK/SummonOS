# Project Context

## Overview
Starter is a screensaver made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/screensaver-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `screensaver` template; layout in `README.md`. Gate: `scripts/check.sh`.
- No GitHub repo yet. `summon project repo screensaver-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI (AppKit only where SwiftUI has no API), SwiftPM, macOS 15+, no third-party dependencies.
- Core logic is test-first (swift-testing); views and `main` stay thin.
- `legacyScreenSaver` outlives the saver: stop timers in `stopAnimation()` and on `com.apple.screensaver.willstop`. Never block `animateOneFrame()`.
- Never create a public repo. Publishing is a separate choice, made only through the SummonOS workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon screensaver template
- Copied from Summon's `screensaver` template into `~/Summon/screensaver-starter`.
