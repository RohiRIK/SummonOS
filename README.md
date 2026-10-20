<p align="center">
  <img alt="SummonOS: native Mac apps, summoned by agents, in Swift" src="docs/assets/hero-dark.svg" width="100%">
</p>

<p align="center">
  <a href="https://github.com/RohiRIK/SummonOS/actions/workflows/swift.yml"><img alt="CI" src="https://github.com/RohiRIK/SummonOS/actions/workflows/swift.yml/badge.svg"></a>
  <img alt="Swift 6 | macOS 15+" src="docs/assets/pill-swift-macos.svg">
</p>

# SummonOS

*Powered by caffeine and questionable life choices.*

SummonOS is an experiment in what a Mac feels like when an agent is part of the system, not a guest in a
browser tab. You summon one coding agent from anywhere. The Mac hands it crashes and hangs. It takes a
checkpoint before it touches anything, so one step undoes whatever it did. It changes system settings
through a CLI that snapshots every change, and when you need a small tool, it builds a real native app in
Swift that launches instantly and works offline.

It is an idea in progress, not a finished product. Parts of it work today; plenty does not.

## Install

On a Mac with macOS 15+ and Xcode (or the Command Line Tools) with Swift 6:

```sh
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
```

Or let your agent do it. Paste this into Claude Code, Codex or any coding agent on your Mac:

```text
Install SummonOS by following https://raw.githubusercontent.com/RohiRIK/SummonOS/main/docs/install-ai.md
```

The installer builds Summon and macctl from source, puts `Summon.app` in `~/Applications` and `summon` and
`macctl` in `~/.local/bin`, then runs `summon doctor`. Run it again to update. Then:

```sh
summon default agent claude                               # or codex, opencode, agy, pi, ...
summon agent prompt "summon, give my Mac a calm dark theme"
```

## What is inside

| | | |
|---|---|---|
| <img src="incubator/summon/design/brand/app-icon-128.png" width="56" alt=""> | **[Summon](incubator/summon/README.md)** | One coding agent you summon from anywhere (⌃⌥⌘A, or the Summon menu on ⌃⌥Space). Crashes and hangs are handed to it, every session starts with a checkpoint you can undo, recurring tasks run while you are away, and it builds apps, themes, wallpapers and icons from templates. |
| <img src="docs/assets/icon-macctl.svg" width="56" alt=""> | **[macctl](macctl/README.md)** | The CLI agents use to read, set, diff, apply and undo macOS settings (Dock, Finder, keyboard, appearance, wallpaper), with a snapshot before every change. |
| <img src="docs/assets/icon-skills.svg" width="56" alt=""> | **[Agent skills](.claude/skills)** | How agents here plan, design, build and verify native Mac apps: `MacAppArchitecture`, `MacUX`, `MacAppBuild`, `PortLinuxWidget` ([which one when](AGENTS.md#skills-which-one-when)). |

Every feature, command by command: [`docs/features.md`](docs/features.md).

## Built with SummonOS

Real apps, each in its own repo, built by agents with the SummonOS skills and Summon's templates.

| | App | What it does |
|---|---|---|
| <img src="https://raw.githubusercontent.com/RohiRIK/mac-breathe/main/docs/screenshots/window.png" width="220" alt="Mac Breathe: a breathing orb in a calm full window"> | **[mac-breathe](https://github.com/RohiRIK/mac-breathe)** | A breathing guide: a soft orb grows and shrinks with your breath, from the menu bar or as a full-screen focus window. |
| <img src="https://raw.githubusercontent.com/RohiRIK/mac-calendar/main/docs/screenshots/panel.png" width="220" alt="Mac Calendar: month grid in the menu bar panel"> | **[mac-calendar](https://github.com/RohiRIK/mac-calendar)** | Menu bar calendar with your events, reminders, natural-language Add Event and Hebrew dates. |
| <img src="https://raw.githubusercontent.com/RohiRIK/mac-network/main/docs/previews/PanelView-0-Overview.png" width="220" alt="mac-network: Wi-Fi, latency and IP overview in the menu bar panel"> | **[mac-network](https://github.com/RohiRIK/mac-network)** | Wi-Fi, latency, throughput and IP settings from the menu bar. |
| <img src="docs/assets/icon-end-of-day.svg" width="96" alt=""> | **[end-of-day](https://github.com/RohiRIK/end-of-day)** | Closes your work apps when the workday ends: a schedule, a 30-second countdown you can snooze, and a streak. Made with `summon project new`. |

## Why

I spent a while living in [Omarchy](https://omarchy.org) on Linux, where the whole desktop is one opinionated,
keyboard-first experience you can reshape in minutes. SummonOS asks what that feels like on a Mac when the
center of the experience is an agent: one you summon from anywhere, that gets your crashes, undoes what it
did, and builds the small tools you need. It is an idea in progress, not a finished product. More on how it
started: [rohi-lab.org/blog/omarchy](https://rohi-lab.org/blog/omarchy).

## Why

I spent a while living in [Omarchy](https://omarchy.org) on Linux, where the whole desktop is one opinionated,
keyboard-first experience you can reshape in minutes. SummonOS asks what that feels like on a Mac when the
center of the experience is an agent, and what happens to "apps" when making a small one takes minutes.
More on how it started: [rohi-lab.org/blog/omarchy](https://rohi-lab.org/blog/omarchy).

## How an app is made

<img alt="How a SummonOS app is made: plan, build, verify, publish" src="docs/assets/lifecycle-dark.svg" width="100%">

Each step names the skill or script that owns it: [`docs/workflow.md`](docs/workflow.md).

## Contributing

Issues, ideas and pull requests are welcome, from people and from agents. Start with
[`CONTRIBUTING.md`](CONTRIBUTING.md); the rules every agent follows are in [`AGENTS.md`](AGENTS.md).
Security problems go privately through [`SECURITY.md`](SECURITY.md).

```sh
git clone https://github.com/RohiRIK/SummonOS && cd SummonOS
./install.sh                     # builds and installs this checkout
tools/check-workspace.sh         # the checks a pull request must pass
```

## What is here

| Path | What it is |
|---|---|
| [`install.sh`](install.sh) | The one-line installer (Summon + macctl); agents use [`docs/install-ai.md`](docs/install-ai.md) |
| [`incubator/summon/`](incubator/summon) | Summon: the menu app, the `summon` CLI, themes, skills, app templates |
| [`macctl/`](macctl) | The settings CLI, its profiles and tests |
| [`.claude/skills/`](.claude/skills) | Agent skills for building Mac apps |
| [`docs/`](docs/index.md) | An [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) bundle: [features](docs/features.md), [app lifecycle](docs/workflow.md), [tools](docs/tools.md), [plans](docs/plans/index.md), [research](docs/research/index.md), [update log](docs/log.md) |
| [`tools/`](tools) | Workspace scripts: checks, plugin registry (`mp`), publish, release, previews, README art, docs index ([docs/tools.md](docs/tools.md)) |
| [`examples/`](examples) | `menubar-starter`, the skeleton new workspace apps start from |
| [`plugins.json`](plugins.json) | Registry of the workspace apps; [`plugins.md`](plugins.md) is generated from it |
| [`AGENTS.md`](AGENTS.md) | Rules for agents and people: stack, workflow, conventions, publishing. `CLAUDE.md` points to it. |
| [`tasks/`](tasks) | `todo.md` (current plan only) and `lessons.md` (rules learned from corrections) |

<details>
<summary><b>Maintainer setup</b> (publishing apps to their own repos)</summary>

Each workspace app lives in its own pair of repos (private `<name>-dev` + public `<name>`), cloned into
`plugins/<name>/`, which is gitignored here.

1. Xcode (with the Xcode MCP bridge, `.mcp.json`) selected via `xcode-select`, and `gh` signed in.
2. [Bun](https://bun.sh) and `jq`, for `tools/mp`, `tools/xcode-mcp.ts` and `tools/render-previews.sh`.
3. `tools/mp clone --all` clones each app's dev repo into `plugins/<name>/`.
4. Optional: `.claude/skills/MacPluginPlaybook` is a per-machine symlink to a private skills library (gitignored).
5. Create `tools/private-patterns.txt` (gitignored): one regex per line for private values (email,
   home subnet, MAC addresses, hostnames). `tools/publish-public.sh` refuses to run without it, and
   `tools/record-demos.sh` uses it to scrub demo transcripts.

Build caches go to `~/Library/Caches/macplugins/<name>`, never `.build/` inside a synced folder.

</details>

## README art

The art in `docs/assets/` is generated, so it stays consistent and renders on GitHub's web and mobile apps:

```sh
python3 tools/readme-art.py           # write docs/assets/*.svg (hero, wordmark, diagram, icons, pill, terminal cards)
python3 tools/readme-art.py --check   # exit 1 if a committed SVG is stale
tools/record-demos.sh                 # on a Mac: re-record macctl's demo transcripts, cards and GIF
```

SummonOS uses Summon's ring mark and colors, shared through `incubator/summon/design/brandkit.py`;
Summon's PNG icon, banner and wordmark are made by `incubator/summon/design/generate.py`. The app screenshots
under "Built with SummonOS" come from each app's own repo.

## License

[MIT](LICENSE). The vendored skills `swiftui-expert-skill` and `swift-concurrency-pro` are MIT and keep their
own `LICENSE` files; upstream notices are in each app's `THIRD_PARTY_NOTICES.md`.
