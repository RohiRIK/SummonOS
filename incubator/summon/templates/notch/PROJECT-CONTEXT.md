# Project Context

## Overview
Starter is a notch app (a panel that grows out of the camera housing) made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/notch-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `notch` template; layout in `README.md`. Gate: `scripts/check.sh`.
- No GitHub repo yet. `summon project repo notch-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI (AppKit only where SwiftUI has no API), SwiftPM, macOS 15+, no third-party dependencies.
- Core logic is test-first (swift-testing); views and `main` stay thin.
- The notch panel is the app's job. There is no Apple notch API: geometry comes from `NSScreen.auxiliaryTopLeftArea`/`RightArea`, with a fallback for screens without a housing. Every preference lives in the Settings window.
- Never create a public repo. Publishing is a separate choice, made only through the SummonOS workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon notch template
- Copied from Summon's `notch` template into `~/Summon/notch-starter`.
