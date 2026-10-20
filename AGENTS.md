# AGENTS.md — SummonOS workspace

SummonOS: Summon (the agent you summon anywhere on the Mac), `macctl`, and small native macOS apps ("plugins"): menu bar extras, panels, utilities, and the
tools around them (`macctl`, Summon). The bar: real native apps that launch instantly, work offline, and look
like they belong on the Mac, written in Swift/SwiftUI. What every project does today: `docs/features.md`.

We design our own apps. Other projects (Omarchy, Glaze, ...) are research, not something to copy: borrow an
idea only when it fits, and credit it in `THIRD_PARTY_NOTICES.md` when code or assets come from it.

## Layout

```
.                            the SummonOS workspace: public repo `RohiRIK/SummonOS` (skills, tools, docs, plans)
├── AGENTS.md                this file; CLAUDE.md points here
├── README.md, CONTRIBUTING.md, SECURITY.md, LICENSE   the public face; keep them current
├── install.sh               one-line installer (Summon + macctl); docs/install-ai.md is the agent version
├── plugins.json             plugin registry (source of truth): repos, status, kind, bundle id, path
├── plugins.md               index of every plugin, generated from plugins.json by `tools/mp index`
├── docs/                    an OKF bundle (Open Knowledge Format v0.2): frontmatter on every page, generated index.md
│   ├── features.md          every feature of every project, in one place
│   ├── log.md               docs update log, newest first
│   ├── research/            research notes behind the skills
│   └── plans/               finished and long plans, one file each: YYYY-MM-DD-<name>.md
├── tools/                   workspace scripts: mp, check-workspace.sh, okf-index.py, readme-art.py, publish, release
├── examples/                menubar-starter/ (CI-built skeleton that `tools/mp new` copies)
├── .claude/skills/          shared skills, used by every plugin (see below)
├── plugins/<name>/          one folder per plugin, each its own git repo (gitignored here)
├── scratch/<name>/          agent-made apps with no repo yet, from `tools/mp new` (gitignored)
├── tasks/                   todo.md (current plan only), lessons.md (mistakes)
└── macctl/, incubator/      still here until they move to their own repos (owner's OK)
```

`.gitignore` is a root allowlist: anything new at the top level is ignored until it is added there.
New plugins start with `tools/mp new <name>` in `scratch/`; `tools/mp promote` (owner's OK each time)
creates the repo pair. Tool details: `docs/tools.md`. Apps made through Summon are separate: they live in
`~/Summon/<name>` (from `incubator/summon/templates/`), in Summon's private project list, never in `plugins.json`.

## Skills: which one when

| Task | Skill |
|---|---|
| Start or port a plugin; "what is next" (the whole process, phase by phase) | `MacPluginPlaybook` (lives in the skills library, symlinked here) |
| Plan an app or feature; state, concurrency, API calls, storage, secrets, system tools | `MacAppArchitecture` |
| Default for all modern macOS views, windows, settings, and glass design pass | `LiquidGlass` (sidebar settings, materials, Liquid Glass) |
| Mac OS X Aqua era (10.0–10.6): jelly pill buttons, brushed metal, pinstripes, candy progress | `MacAqua` |
| OS X Linen & Skeuomorphic era (10.7–10.9): woven linen, stitched leather, legal pad notes | `MacLinen` |
| OS X Flat Vibrancy era (10.10–10.15): frosted glass, SF typography, flat colorful pills | `MacYosemite` |
| NeXTSTEP & OPENSTEP (1989–1996): 3D sculpted chisel bevels, vertical dock, dark gray tiles | `MacNeXT` |
| System 7 & Mac OS 8/9 Platinum: pinstripe title bars, 3D bevels, Chicago/Charcoal, classic dialogs | `MacClassic` |
| Menu panel basics, typography, legacy design passes | `MacUX` › `DesignPass` workflow (+ `swiftui-expert-skill` for API depth) |
| Scaffold, build, previews, verify, PR, release | `MacAppBuild` |
| Port a Linux widget or script | `PortLinuxWidget` |
| Actors, `Sendable`, cancellation, Swift 6 errors | `swift-concurrency-pro` |

`tools/install-skills.sh` links these skills into `~/.claude/skills`, so Claude Code sessions anywhere on the
Mac can use them; `git pull` keeps them current.

`swiftui-expert-skill` (Antoine van der Lee) and `swift-concurrency-pro` (Paul Hudson) are MIT,
installed unmodified with their LICENSE files. Do not edit them; put our rules in our own skills.

## Stack

- Swift 6 + SwiftUI, AppKit only where SwiftUI has no API. Minimum macOS 15; Liquid Glass behind
  `if #available(macOS 26, *)`.
- SwiftPM, no `.xcodeproj`: `Core` / `UI` library / `@main` targets (`MacAppBuild/Scaffold.md`).
- Xcode 27 selected; Xcode MCP server `xcode` in `.mcp.json` for previews, builds, tests.
- No third-party dependencies unless a skill says so. Tests: swift-testing.

## How we work

1. **Read context:** the plugin's `PROJECT-CONTEXT.md` (if it exists), then only the files the task touches.
2. **Plan** in `tasks/todo.md` (move it to `docs/plans/` when done); separate explicit requirements from inferences; ask only when a choice
   changes the result. Confirm non-trivial plans with the user.
3. **Shape before code:** `MacAppArchitecture/AppShapes.md`.
4. **Build end to end:** no stubs, TODOs, or mock data standing in for required behavior; every new
   screen, action, and setting is reachable. Test-first for Core logic. Branch, never `main`.
5. **Verify:** `MacAppBuild/Verify.md`: gate, previews, run the app, logs, manual checklist.
6. **PR:** `gh pr create`, then `scripts/pr-report.sh` (report + previews as a comment). No GitHub Actions in private
   plugin repos (the owner does not pay for Actions). This workspace repo is public, so Actions are free here: the
   gate is the `Swift (macOS)` check from `.github/workflows/swift.yml` plus `tools/check-workspace.sh`; merge only
   when they are green. `tools/local-ci.sh <pr>` runs the same build on a Mac and posts `local / swift (macOS)`.
7. **Update memory:** the plugin's `PROJECT-CONTEXT.md`; `plugins.json` + `tools/mp index` if status changed;
   `docs/features.md` when a user-visible feature is added or removed; a line in `docs/log.md` for a notable docs
   change. New or edited docs pages carry OKF frontmatter (`type`, `title`, `description`, `tags`; plans also
   `status`, `created`); run `python3 tools/okf-index.py` to regenerate the indexes, never edit `index.md` by hand.

## Project memory (per plugin)

Each plugin keeps `PROJECT-CONTEXT.md` at its repo root: the short, current truth about the app.

```
# Project Context
## Overview          what it is, who it is for
## Current State     key files, targets, data & storage, permissions, design references
## Constraints       decisions that must survive a context reset
## Recent History    newest first: "### YYYY-MM-DD — Short title" then "- ..." bullets
```

Update it after every completed change. Keep it concise; it is not a log dump.

## Record learnings on the fly

Write the lesson in the same turn it is learned:

- macOS API quirk or Linux mapping → `PortLinuxWidget/Mapping.md`.
- Structure, data, backend, system-tool lesson → `MacAppArchitecture` Gotchas or its context file.
- Build, preview, signing, release → `MacAppBuild` Gotchas.
- UI/UX → `MacUX` Gotchas, `MenuPanel.md`, or `Principles.md`.
- User correction → `tasks/lessons.md`.

## Repos and publishing

- Each plugin: private `<name>-dev` repo (full history, PRs, `PROJECT-CONTEXT.md`) + public `<name>` repo (clean snapshots only).
- Publish: `tools/publish-public.sh plugins/<name> <branch> "<message>"`. It drops agent memory, refuses on any
  match in `tools/private-patterns.txt` (gitignored: email, home subnet, MAC, private hostnames), and commits with the
  GitHub noreply identity. Never flip a dev repo public: its history holds the author email.
- Test fixtures use documentation values only (`192.0.2.x`, `00:00:5e:00:53:xx`), never real network data.
- This workspace (SummonOS) is the public repo `RohiRIK/SummonOS` (skills, tools, docs); `plugins/` is gitignored.
  Its history keeps the owner's commit email (owner's choice, 2026-10-19). Never commit private values here.

## Panel vs Settings window (user preference)

The user does not want app settings inside the menu bar panel. Every plugin follows this split:

- **Panel** = the app's job: live data, the calendar grid, lists, and actions on them.
- **Panel footer** = `Settings…` (⌘,) and `Quit` (⌘Q). Settings rows never appear in the panel.
- **Settings window** = every app preference: Open at Login, theme, permissions, toggles. It is a separate
  window (SwiftUI `Settings` scene, `.formStyle(.grouped)`), opened from `Settings…` or ⌘, after `NSApp.activate()`.
- Even a plugin with a single setting gets a Settings window. Reference: `plugins/mac-calendar`.

## Conventions

- Plugin folder and repo name: kebab-case, no personal names (`mac-network`).
- Bundle id: `local.macplugins.<name>`.
- License: MIT. Keep `LICENSE` pure (GitHub shows NOASSERTION if notices are appended); upstream notices go in `THIRD_PARTY_NOTICES.md`.
- Commits: conventional (`feat:`, `fix:`, ...).
- Build caches live in `~/Library/Caches/macplugins/<name>` (never `.build/` inside Google Drive).
- Git repos live in Google Drive: push after every commit; if `.git` breaks, re-clone from GitHub.
  Planned, pending the owner's OK: move the workspace to `~/Developer/macplugins` (`$MACPLUGINS_HOME`),
  off Google Drive. Until then this rule stands.
