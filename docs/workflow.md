---
type: Playbook
title: App lifecycle
description: "How a SummonOS app goes from idea to public release, and which skill or script owns each step."
tags: [workflow, release]
---

# App lifecycle

How a workspace app goes from idea to a public release. Each step names the skill or script that owns the
details; this page only shows the order. Rules: [`AGENTS.md`](../AGENTS.md).

## Which path?

There are two ways to start an app, and they do not mix:

| | Workspace plugin | Summon project |
|---|---|---|
| For | Apps that belong to this workspace and get a `<name>-dev` / `<name>` repo pair | Anything a user asks Summon's agent to make on their Mac |
| Start | `tools/mp new <name> --kind <kind>` | `summon project new <name> --kind menubar\|menubar-panel\|launcher\|hud\|notch\|app\|widget\|cli\|screensaver` |
| Template | `incubator/summon/templates/<kind>` (bundle id `local.macplugins.<name>`) | `incubator/summon/templates/<kind>` (bundle id `local.summon.<name>`) |
| Folder | `scratch/<name>/`, then `plugins/<name>/` after `tools/mp promote` | `~/Summon/Apps/<name>` |
| Listed in | `plugins.json` / `plugins.md` | `~/.config/summon/projects.json` (private to the Mac) |
| GitHub | `tools/mp promote --yes`, owner's OK each time | Private only: `summon project repo <name>` asks in a native dialog; `summon default repos always` is explicit standing approval for newly created projects |

The rest of this page is the workspace-plugin path.

Both paths share nine starter kinds: `menubar`, `menubar-panel`, `launcher`, `hud`, `notch`, `app`, `widget`,
`cli`, `screensaver`. Launchers/HUDs/notch/panel starters record as menu bar apps; widget records as a window
app. The folders/registries remain separate: workspace plugins do not become My Apps projects merely by being
listed in `plugins.json`. Theme/art work is not an app-template kind.

## 1. Plan

- Write the plan in `tasks/todo.md`: explicit requirements, inferred decisions, phases.
- Pick the app shape (menu bar extra, panel, window): `MacAppArchitecture/AppShapes.md`.
- Porting a Linux widget or script: `PortLinuxWidget` (mappings in `Mapping.md`).

## 2. Scaffold

- `tools/mp new <name> --kind menubar`: copies `incubator/summon/templates/menubar` to `scratch/<name>/`, renames it,
  and registers it in `plugins.json` (kebab-case, bundle id `local.macplugins.<name>`). Commit
  `plugins.json` and `plugins.md`.
- Package layout, plist and scripts: `MacAppBuild/Scaffold.md`. App starters normally separate `<App>Core`
  (logic/tests), `<App>UI` (views/previews) and `<App>` (`@main`); CLI/screensaver targets follow their surface.
  **Widget exception:** logic/views remain a Swift package, but a small `Xcode/` project builds the carrier app
  and embedded WidgetKit extension. Core tests work with Command Line Tools; the full widget gate needs Xcode.
- When it is worth keeping, and only with the owner's OK: `tools/mp promote <name> --yes` creates the repo
  pair, private `<name>-dev` (all history, PRs) and public `<name>` (snapshots only), and moves it to
  `plugins/<name>/`. An existing plugin on another machine: `tools/mp clone <name>`.
- Add `PROJECT-CONTEXT.md` at the repo root (sections in [`AGENTS.md`](../AGENTS.md#project-memory-per-plugin)).

## 3. Build

- Core logic test-first with swift-testing.
- Views through `MacUX` › `DesignPass`. App settings go in a Settings window, never in the panel.
- Work on a branch, never `main`. Conventional commits; push after every commit.

## 4. Verify

From the plugin folder (`MacAppBuild/Verify.md`):

```bash
scripts/check.sh                                         # gate: tests + release bundle + plist lint
../../tools/render-previews.sh . <App>UI                 # any view change; read every PNG
scripts/bundle.sh && open build/<App>.app                # new flows, permissions, system calls
```

Write the manual checklist (permission prompts, admin prompts) unticked into the PR.

SummonOS's public workspace uses selective hosted CI: a PR tests changed packages, template changes also select
Summon, and `main`/manual runs test everything. Summon/macctl use macOS 15/26; raw templates use macOS 26.
The separate generated-project matrix currently covers menubar, menubar-panel, app, cli and screensaver; it
does not validate all nine starter bundles. See [tooling/CI reference](tools.md#ci-plansh) before choosing checks.

For changes to Summon itself, `incubator/summon/scripts/check.sh --runtime-smoke` adds packaged identity and
the real Core lifecycle fixture. `scripts/install.sh --verify-only` validates a supplied candidate without
replacing a personal installation. Do not equate either command with GUI/profiling/VoiceOver acceptance;
current unreleased hardening and remaining gates are separated in [status](status.md).

## 5. Pull request

```bash
gh pr create ...
scripts/pr-report.sh          # posts the gate report and preview images as a PR comment
```

## 6. Publish and release

After the PR merges into the dev repo's `main`, from this workspace:

```bash
tools/publish-public.sh plugins/<name> main "<message>"     # clean snapshot to the public repo
tools/release.sh plugins/<name> "what's new"                # zip on the public repo's Releases
```

For plugin releases, bump `CFBundleShortVersionString` and `CFBundleVersion` first (`MacAppBuild/Release.md`).
The publisher requires usable private-pattern rules and exports a clean snapshot without project memory;
release builds must come from clean dev `main` matching the exact public source commit. The release script
runs the exported candidate's gate and verifies signatures, then uploads its zip, checksums and source record.
Ad-hoc output is a preview, not notarization; the optional Developer ID pipeline requires both signing identity
and a stored notary profile and refuses partial configuration.

SummonOS itself has a different release path: root `VERSION` is currently **0.2.4**; matching `v*` tags drive
[`release.yml`](../.github/workflows/release.yml), while successful push CI on `main` triggers optional rolling
edge publication. A feature-branch build is neither a numbered release nor proof an edge asset exists.
See [release tooling](tools.md#releaseyml-github-actions) and [current status](status.md).

## 7. Record

- Update the plugin's `PROJECT-CONTEXT.md` (Recent History, newest first).
- Move the finished plan from `tasks/todo.md` to `docs/plans/YYYY-MM-DD-<name>.md`; `todo.md` keeps only the active plan.
- New plugin or new status: update `plugins.json`, then `tools/mp index` regenerates [`plugins.md`](../plugins.md).
- Lessons go in the skill that owns them ([`AGENTS.md`](../AGENTS.md#record-learnings-on-the-fly));
  user corrections go in `tasks/lessons.md`.
