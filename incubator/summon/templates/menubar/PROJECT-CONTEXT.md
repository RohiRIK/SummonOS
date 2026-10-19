# Project Context

## Overview
Starter is a menu bar app made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/menubar-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `menubar` template; layout in `README.md`. Gate: `scripts/check.sh`.
- No GitHub repo yet. `summon project repo menubar-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI (AppKit only where SwiftUI has no API), SwiftPM, macOS 15+, no third-party dependencies.
- Core logic is test-first (swift-testing); views and `main` stay thin.
- Panel = the app's job; its footer has only `Settings…` (⌘,) and `Quit` (⌘Q). Every preference lives in the Settings window.
- Never create a public repo. Publishing is a separate choice, made only through the SummonOS workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon menubar template
- Copied from Summon's `menubar` template into `~/Summon/menubar-starter`.
