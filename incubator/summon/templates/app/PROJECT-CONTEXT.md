# Project Context

## Overview
Starter is a full window app made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/app-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `app` template; layout in `README.md`. Gate: `scripts/check.sh`.
- No GitHub repo yet. `summon project repo app-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI (AppKit only where SwiftUI has no API), SwiftPM, macOS 15+, no third-party dependencies.
- Core logic is test-first (swift-testing); views and `main` stay thin.
- Every action has a menu item and a ⌘ shortcut. Every preference lives in the Settings window (⌘,).
- Never create a public repo. Publishing is a separate choice, made only through the macos-plugins workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon app template
- Copied from Summon's `app` template into `~/Summon/app-starter`.
