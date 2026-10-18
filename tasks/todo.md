# Current plan

The active plan goes here. When a plan is done, move it to `docs/plans/YYYY-MM-DD-<name>.md`
and leave this file with only what is still in progress.

# Plan: `macctl` — macOS setup CLI for AI agents (new tool)

Status: milestone 1 written (draft PR #6), not yet compiled. Full plan: `docs/plans/2026-10-16-macctl.md`.
Repos: `mac-ctl-dev` (private) / `mac-ctl` (public). Bundle id `local.macplugins.macctl`.

## Decisions
- Swift binary (Core / CLI / later MCP + helper app), JSON profiles, snapshot before every change, `--json` everywhere.
- `swift-argument-parser` approved by the user as the one dependency (exception to the no-deps rule).

## Milestone 1
- [ ] Scaffold `mac-ctl-dev`, PROJECT-CONTEXT.md
- [ ] Core test-first: registry, values, profile diff, snapshots, restart batching
- [ ] Backends: defaults, killall, AppleScript (argv only + injection test)
- [ ] ~15 settings verified on a real Mac (dock, finder, keyboard, screenshots, dark mode)
- [ ] Commands: doctor, list, describe, get, set, diff, apply, snapshot list, undo
- [ ] Sample profile + `MacSetup` skill; verify apply/undo on the Mac; PR + report
