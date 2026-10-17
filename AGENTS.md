# AGENTS.md — macOS plugins workspace

Workspace for building small native macOS apps ("plugins"): menu bar extras, panels, utilities.
Many start as ports of existing Linux/Omarchy bar widgets. The bar is the one
[Glaze](https://www.glaze.app/) sets: real native apps that launch instantly, work offline, and look
like they belong on the Mac. Unlike Glaze (React in a WebView + Node backend), we write Swift/SwiftUI.

## Layout

```
.                            this workspace (docs, skills, tools, plans; not a git repo)
├── AGENTS.md                this file; CLAUDE.md points here
├── plugins.md               index of every plugin + its GitHub repo
├── docs/research/           research notes behind the skills
├── tools/                   xcode-mcp.ts (Xcode MCP client), render-previews.sh
├── .claude/skills/          shared skills, used by every plugin (see below)
├── plugins/<name>/          one folder per plugin, each its own git repo
└── tasks/                   todo.md (current plan), lessons.md (mistakes)
```

## Skills: which one when

| Task | Skill |
|---|---|
| Start or port a plugin; "what is next" (the whole process, phase by phase) | `MacPluginPlaybook` (lives in the skills library, symlinked here) |
| Plan an app or feature; state, concurrency, API calls, storage, secrets, system tools | `MacAppArchitecture` |
| Any view, panel, window, or settings UI; a redesign or UI complaint | `MacUX` › `DesignPass` workflow (+ `swiftui-expert-skill` for API depth) |
| Scaffold, build, previews, verify, PR, release | `MacAppBuild` |
| Port an Omarchy / Linux widget | `PortOmarchyPlugin` |
| Actors, `Sendable`, cancellation, Swift 6 errors | `swift-concurrency-pro` |

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
2. **Plan** in `tasks/todo.md`; separate explicit requirements from inferences; ask only when a choice
   changes the result. Confirm non-trivial plans with the user.
3. **Shape before code:** `MacAppArchitecture/AppShapes.md`.
4. **Build end to end:** no stubs, TODOs, or mock data standing in for required behavior; every new
   screen, action, and setting is reachable. Test-first for Core logic. Branch, never `main`.
5. **Verify:** `MacAppBuild/Verify.md`: gate, previews, run the app, logs, manual checklist.
6. **PR:** `gh pr create`, then `scripts/pr-report.sh` (report + previews as a comment). No GitHub Actions in plugin
   repos; this workspace repo runs `.github/workflows/swift.yml` (build + test every Swift package on macOS).
7. **Update memory:** the plugin's `PROJECT-CONTEXT.md` and, if new, `plugins.md`.

## Project memory (per plugin, from Glaze)

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

- macOS API quirk or Linux mapping → `PortOmarchyPlugin/Mapping.md`.
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
- This workspace is the private repo `macos-plugins` (skills, tools, docs); `plugins/` is gitignored.

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
