# Plugins

| Plugin | Ported from | Public repo | Dev repo (private) | Status |
|---|---|---|---|---|
| mac-network | [rohi.network](https://github.com/RohiRIK/rohi.network) (Omarchy) | [RohiRIK/mac-network](https://github.com/RohiRIK/mac-network) | [RohiRIK/mac-network-dev](https://github.com/RohiRIK/mac-network-dev) (PR #1 merged) | public snapshot 2026-09-29 |
| mac-calendar | new | [RohiRIK/mac-calendar](https://github.com/RohiRIK/mac-calendar) | [RohiRIK/mac-calendar-dev](https://github.com/RohiRIK/mac-calendar-dev) (PR #1 merged) | public snapshot 2026-09-30 |

## In progress (in this repo, not yet in their own repos)

| Plugin | What it is | Where | Status |
|---|---|---|---|
| macctl | CLI for AI agents to read, set, diff, apply and undo macOS settings | `macctl/`, plan `docs/plans/2026-10-16-macctl.md` | merged; 82 tests pass and smoke-tested on a Mac (macOS 26.6, 2026-10-18) |
| mac-assistant | Local Mac diagnostics assistant with a policy broker and typed tools | branch `feat/mac-assistant` only (not on main) | Phase 1 (read-only diagnostics); last commit 2026-10-03 |
| Summon | An agent you summon from anywhere on the Mac: crash and log handoff, checkpoints with undo, themes, app templates | `incubator/summon/`, plan `docs/plans/2026-10-17-summon.md` | CLI and menu app built, tested and installed on a Mac (2026-10-18) |
