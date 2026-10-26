# Project Context

## Overview
Starter is a command-line tool made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/Apps/cli-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `cli` template; layout in `README.md`. Gate: `scripts/check.sh`.
- No GitHub repo yet. `summon project repo cli-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI (AppKit only where SwiftUI has no API), SwiftPM, macOS 15+, no third-party dependencies.
- Core logic is test-first (swift-testing); views and `main` stay thin.
- Output is plain text for people and `--json` for agents when the tool grows data worth parsing. Exit codes: 0 ok, 1 error, 2 usage.
- Never create a public repo. Publishing is a separate choice, made only through the SummonOS workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon cli template
- Copied from Summon's `cli` template into `~/Summon/Apps/cli-starter`.
