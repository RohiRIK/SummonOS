---
type: Research
title: Building native macOS apps with agents
description: "What makes agent-built Mac apps good, and how it became the workspace skills."
tags: [research, skills]
created: 2026-09-29
---

# Research: building native macOS apps with agents (2026-09-29)

Goal: find what makes agent-built Mac apps good (UI, design, functionality, backend calls, verification)
and turn it into a small set of skills. Result: 4 workspace skills + 2 installed MIT skills.

## Sources

| Source | What it is | Used how |
|---|---|---|
| Glaze by Raycast (installed, v0.14 SDK) | AI Mac-app builder; 29 agent skills, 1,422-line app guide, per-app memory | Studied the process and rules; not copied (proprietary) |
| Apple HIG JSON (menu bar, menus, materials, toggles) | Design rules | Quoted rules in `MacUX/MenuPanel.md` |
| Apple SwiftUI docs: *Applying Liquid Glass to custom views* | Glass API | Glass only on controls, never content |
| [fayazara/macos-app-skills](https://github.com/fayazara/macos-app-skills) (★674, **no license**) | macOS patterns, settings UI, Sparkle, release | Read only; ideas in `MacAppBuild/Release.md`, `MacAppArchitecture/AppShapes.md` |
| [AvdLee/SwiftUI-Agent-Skill](https://github.com/AvdLee/SwiftUI-Agent-Skill) (★3.6k, MIT) | Deep SwiftUI + macOS views + Liquid Glass | Installed as `swiftui-expert-skill` @ 204dba7 (v5.2.1, updated 2026-10-17) |
| [twostraws/Swift-Concurrency-Agent-Skill](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) (★547, MIT) | Swift 6 concurrency | Installed as `swift-concurrency-pro` @ bee3f69 |
| twostraws/SwiftUI-Agent-Skill (MIT) | Compact SwiftUI reviewer | Skipped: overlaps AvdLee, which has macOS coverage |
| dpearson2699/swift-ios-skills | iOS skills | Skipped: PolyForm Perimeter license, iOS focus |
| Our mac-network build | First real plugin | Every gotcha found is in the skills |

## How Glaze does it

**Architecture.** Glaze apps are not Swift: a React/Vite frontend in a WebView, a Node.js backend,
JSON-RPC IPC, and a Swift host exposing native APIs. For capabilities the SDK lacks, apps ship a
compiled Swift "sidecar". The SDK mirrors Electron's API surface.

**Agent setup.**
- A short `CLAUDE.md` holds only "can't infer from code" facts plus hard constraints (protected paths,
  forbidden imports, never install Xcode). Recipes live in a long guide read on demand, and in skills.
- 29 narrow skills, each with "non-negotiable rules", "read only the file(s) for the task" routing to
  reference files, and a verification section. Examples: component patterns, frontend rules, backend
  rules, IPC, data storage, external API, OAuth (generic + GitHub/Linear/Slack), native permissions,
  native sidecar, window sizing, live inspection, theming, app lifecycle, backend performance.
- A forked, read-only "context gather" sub-agent (haiku) extracts only the guide rules a task needs.
- Per-app memory: `.glaze_memory/PROJECT-CONTEXT.md` (Overview, Current State, Recent History with
  dated headings) is the canonical truth after context resets; history is auto-maintained.

**Rules worth keeping (all adapted into our skills):**
- Frontend-first; backend only for OS access, secrets, background work. Thin handlers, logic in services.
- Validate inputs at the boundary; errors are specific and include status codes.
- External APIs: curl first, transform at the boundary, nothing hardcoded, secrets encrypted.
- Storage ladder: small prefs → JSON in Application Support (atomic, only ENOENT means "default") →
  SQLite; secrets encrypted. Never in the source tree.
- Permissions: declare, check status, prompt only from a user action and only when not determined.
- Polling: 2-5 s, metadata only, clear on quit; bounded caches with TTL; `execFile` with timeout.
- Menu bar: native menu for command lists, custom window for rich UI; never both on left-click.
- Design: native-looking, flat, structure over cards, semantic colors, one accent action per screen,
  Settings in a Settings window, window-size table, design references are requirements.
- Implementation quality: end to end, no stubs, every path reachable, visible focus states.
- Verification: one required gate (`npm run verify`), then bounded live inspection (≤5 probes, ≤3
  fix cycles); a green build is not proof; state what the user must verify.

## Where we differ from Glaze, and why

| Glaze | Us | Why |
|---|---|---|
| React + Node + WebView | Swift 6 + SwiftUI | Truly native, no runtime, smaller, direct framework access |
| Design-system components (`@glaze/core`) | SwiftUI system controls + our menu-style components | Same idea: system first, semantic tokens |
| Live DOM inspection | Xcode `RenderPreview` via MCP + logs + manual checklist | Our equivalent of looking at the running UI |
| `npm run verify` | `scripts/check.sh` | Same single gate |
| `safeStorage` | Keychain | Native equivalent |
| Glaze Store publishing | GitHub releases, ad-hoc signed | No paid Apple account yet |

## Resulting skill set

| Skill | Scope |
|---|---|
| `MacAppArchitecture` (new) | Shapes, layers, state, concurrency, backend calls, persistence, secrets, system tools, admin, permissions, polling, lifecycle, logging |
| `MacAppBuild` (renamed from MacMenuBarApp) | Scaffold, build, previews, verification loop, PR report, release |
| `MacUX` (updated) | HIG, system-menu look, Glaze design rules, review checklist |
| `PortLinuxWidget` (kept) | Linux → macOS port recipe and API mapping |
| `swiftui-expert-skill` (installed) | SwiftUI API depth |
| `swift-concurrency-pro` (installed) | Concurrency correctness |

Snippets in `MacAppArchitecture` (APIClient, Keychain, JSONStore, Poller) were type-checked under
Swift 6; JSONStore's missing/round-trip/corrupt behavior was run and passed.

## Open follow-ups

- Settings window pattern for plugins that need tokens (write when the first such plugin appears).
- Sparkle updates only after a Developer ID account exists.
- A Glaze-style forked "context gather" agent is not needed yet: our skills are small enough to read directly.
