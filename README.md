# macos-plugins

Private workspace for building small native macOS apps ("plugins"): menu bar extras, panels and
utilities, written in Swift 6 and SwiftUI. Many start as ports of Linux/Omarchy bar widgets.

This repo holds the shared know-how, not the apps. Each plugin lives in its own pair of repos
(private `<name>-dev` + public `<name>`), cloned into `plugins/<name>/`, which is gitignored here.

## What is here

| Path | What it is |
|---|---|
| [`AGENTS.md`](AGENTS.md) | Rules for agents and people: stack, workflow, conventions, publishing. `CLAUDE.md` points to it. |
| [`plugins.json`](plugins.json) | Plugin registry, the source of truth; [`plugins.md`](plugins.md) (index of every plugin, its repos and status) is generated from it |
| [`examples/`](examples) | `menubar-starter`, the skeleton `tools/mp new` copies |
| [`.claude/skills/`](.claude/skills) | Agent skills used by every plugin ([which one when](AGENTS.md#skills-which-one-when)) |
| [`tools/`](tools) | Workspace scripts: `mp` (plugin home), workspace check, publish, release, previews, Xcode MCP client ([docs/tools.md](docs/tools.md)) |
| [`docs/`](docs) | [Plugin lifecycle](docs/workflow.md), [tools](docs/tools.md), [research notes](docs/research), [finished plans](docs/plans) |
| [`tasks/`](tasks) | `todo.md` (current plan only) and `lessons.md` (rules learned from corrections) |
| `.mcp.json` | Xcode MCP server (`xcrun mcpbridge`) for builds, tests and previews |

## Plugins

See [`plugins.md`](plugins.md). Shipped: **mac-network** (Wi-Fi and IP settings, port of
`rohi.network`) and **mac-calendar** (menu bar calendar with events, reminders and Hebrew dates).

## Set up a Mac

1. Xcode (with the Xcode MCP bridge) selected via `xcode-select`, and `gh` signed in.
2. [Bun](https://bun.sh) and `jq`, for `tools/mp`, `tools/xcode-mcp.ts` and `tools/render-previews.sh`.
3. Clone this repo, then `tools/mp clone --all` clones each plugin's dev repo into `plugins/<name>/`.
4. Link the skills library: `.claude/skills/MacPluginPlaybook` is a per-machine symlink (gitignored).
5. Create `tools/private-patterns.txt` (gitignored): one regex per line for private values (email,
   home subnet, MAC addresses, hostnames). `tools/publish-public.sh` refuses to run without it.

Build caches go to `~/Library/Caches/macplugins/<name>`, never `.build/` inside Google Drive.

## Stack in one line

Swift 6 + SwiftUI, SwiftPM only (no `.xcodeproj`), macOS 15+, swift-testing, no third-party
dependencies unless a skill says so. Details: [`AGENTS.md`](AGENTS.md#stack).

## License

Plugins are MIT. The vendored skills `swiftui-expert-skill` and `swift-concurrency-pro` are MIT and
keep their own `LICENSE` files.
