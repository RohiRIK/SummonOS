# Project Context

## Overview
Starter is a desktop widget made with Summon. Write its one job and who it is for here once they are settled.

## Current State
- Lives in `~/Summon/Apps/widget-starter`, recorded in Summon's private list (`summon project list`).
- Started from Summon's `widget` template; layout in `README.md`. Gate: `scripts/check.sh` (needs Xcode).
- No GitHub repo yet. `summon project repo widget-starter` creates a private one after you approve it in a Summon
  dialog, and adds CI (`.github/workflows/check.yml`, which runs `scripts/check.sh`).

## Constraints
- Swift 6 + SwiftUI, macOS 15+, no third-party dependencies. Logic and views in the Swift package; the Xcode
  project (`Xcode/`) only exists to build the widget extension and stays free of logic.
- Core logic is test-first (swift-testing); the widget, the app and `main` stay thin.
- The widget is glanceable: no app-like layouts, buttons only through App Intents, a reload only when data changed
  (WidgetKit's budget is about 40-70 a day). The extension stays sandboxed.
- No App Group yet: without a provisioning profile (ad hoc signing), macOS 15 can ask the person before a group container is shared. Add one with a
  Developer ID team, and then put shared data there.
- Every app preference lives in the Settings window (⌘,); the widget's own options live in Edit Widget.
- Never create a public repo. Publishing is a separate choice, made only through the SummonOS workspace's
  `tools/publish-public.sh` (noreply identity, drops this file).

## Recent History
### {{DATE}} — Started from the Summon widget template
- Copied from Summon's `widget` template into `~/Summon/Apps/widget-starter`.
