# Project Context

## Overview
Starter is a command launcher (global shortcut, Spotlight-style panel) made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/Apps/launcher-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `launcher` template; layout in `README.md`. Gate: `scripts/check.sh`.
- No GitHub repo yet. `summon project repo launcher-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI (AppKit only where SwiftUI has no API), SwiftPM, macOS 15+, no third-party dependencies.
- Core logic is test-first (swift-testing); views and `main` stay thin.
- The launcher is the app's job; the menu bar menu has Open, `Settings…` (⌘,) and `Quit` (⌘Q). Every preference lives in the Settings window.
- The default shortcut is never ⌘Space (Spotlight's); people record their own in Settings.
- Never create a public repo. Publishing is a separate choice, made only through the SummonOS workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon launcher template
- Copied from Summon's `launcher` template into `~/Summon/Apps/launcher-starter`.
