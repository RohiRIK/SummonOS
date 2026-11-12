---
type: Reference
title: Workspace tools
description: "What each script in tools/ does and how to run it: installer, mp, local CI, checks, publishing, previews, README art."
tags: [tools, workflow]
---

# Tools

Scripts in [`tools/`](../tools). Run them from the workspace root. Per-plugin scripts
(`scripts/test.sh`, `bundle.sh`, `check.sh`, `pr-report.sh`) live in each plugin repo and are
described in `MacAppBuild/Scaffold.md`.

## install.sh (repo root)

The SummonOS installer. Outside a checkout, the default `stable` selection is the **first non-`edge` tag** in
GitHub's returned release list (including prereleases), not `/releases/latest` and not necessarily the highest
semantic version. `--version vX.Y.Z` pins a tag; `--channel edge` opts into the rolling asset. Edge publication
is triggered after successful `main` push CI, but the currently published asset can lag source. The installer
checks the universal zip against `SHA256SUMS`, unpacks it and runs that release's bundled staged installer.
If the release list is empty **or cannot be fetched**, it falls back to source; explicit tag/edge download
failures stop instead of falling back. See [release and branch status](status.md).

Run from a checkout, the default installs that checkout. Outside one, `--from-source` clones/updates
`~/.summonos` (`SUMMONOS_HOME`), selecting `SUMMONOS_REF` (default `main`). An explicit `--version` or
`--channel edge` selects a release even when run inside a checkout; `--channel edge` cannot be combined with
`--version` or `--from-source`, and `--version` cannot be combined with `--from-source`.
Source installs need git and Swift 6, build macctl, then run Summon's `bundle.sh` and `install.sh`.
The current staged build/install scripts also require Python 3; full App Intents metadata requires Xcode.
The app goes in `~/Applications`, `summon` is linked into `~/.local/bin`, and macctl is copied there.
Both paths run `summon doctor` after installation; a failed check reports incomplete setup (the installed
files are not rolled back merely because that later doctor check fails). The installer offers `summon connect`
on a terminal, default No. `--connect` runs it; `--yes` suppresses prompts and does not imply connect approval.
Agents follow [the AI installation playbook](install-ai.md), including its permission and reporting rules.

```bash
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
```

## Summon build identity and isolated validation

These are current-checkout commands added after the tagged 0.2.4 baseline; their implementation does not prove
release or performance acceptance. See [status](status.md) and the
[historical runtime audit](plans/2026-11-08-runtime-audit.md#implementation-evidence-and-unverified-acceptance-2026-11-08).

`incubator/summon/scripts/bundle.sh` copies the Swift package into a private staging tree, generates the compiled
`SummonVersion`, `BuildInfo.json` and bundle Info.plist from one manifest, builds and signs `build/Summon.app`, and
verifies packaged CLI identity. It does **not** rewrite the tracked development `Version.swift`. The full edge
display version has a revision suffix; the marketing version remains the base `VERSION` and the bundle build is
numeric. `tools/build-metadata.py generate` requires a clean identified checkout for stable/edge; a dirty
development build identifies its source as dirty. `verify --manifest ... --app ... --summon ... [--macctl ...]`
checks compiled CLI output and the signed candidate's manifest/plist against one another.

`incubator/summon/scripts/install.sh --verify-only` checks a supplied signed candidate and its packaged command
without replacing a live app or CLI. Source installs with Command Line Tools may omit optional Siri/App Intents
metadata; release gates require it. A normal install stages the app and restores prior files if promotion fails;
do not run it against a personal installation for an audit. `incubator/summon/scripts/check.sh --runtime-smoke`
records separate gate stages, validates the packaged signature and identity, and runs an actual Core lifecycle
fixture. `--skip-tests` is only for a job that already ran the same Swift suites.

`incubator/summon/scripts/runtime-audit.py --mode core --iterations 100 --out DIR` runs real optimized Core source
against temporary event/log/snapshot/checkpoint fixtures; `--mode ui --app APP` is guarded to a disposable hosted
runner or an explicitly authorized test account and refuses an existing SummonMenu. A blocked GUI prerequisite is
exit 2, not a passed result. PanelWindowUpdate measures AppKit's first window-update pass **before** display;
it is not proof of a first drawn or composited frame. Only owned fixture/process resources may be removed.
Profiler interactions wait on xctrace's recording-start notification; actual status-item mouse input is restricted
to the hit-tested owned extra-menu item. Recorder finalization failures retain bounded, private-path-redacted
`*.recorder*.log` sidecars (tool diagnostics and an owned-recorder stack sample, never target stdout). Hosted
artifacts include those sidecars; JSON keeps structured statuses/counts. Timeouts remain failures.
UI `--iterations` applies to the unprofiled interaction loop and separately to each Instruments recording
(default 100 each). Every recorded cycle must complete; panel timing acceptance requires one successful
`PanelOpen` and `PanelWindowUpdate` sample per requested cycle, not merely a nonempty trace.

## mp

Manages the plugin home: the registry `plugins.json` (source of truth), the generated `plugins.md`, and
the `plugins/` and `scratch/` folders. Needs `jq` and `git`; `gh` for `promote` and `clone`.

```bash
tools/mp new <name> [--kind menubar|menubar-panel|launcher|hud|notch|app|widget|cli|screensaver]   # scratch/<name> from Summon's template, registered
tools/mp promote <name> [--owner <login>] [--yes]      # private <name>-dev + public <name>, moves to plugins/
tools/mp clone (<name>... | --all)                     # clones registered dev repos into plugins/<name>
tools/mp list [--json]                                 # the registry
tools/mp status                                        # branch, dirty, version, registry vs disk, unregistered folders
tools/mp index [--check]                               # regenerates plugins.md; --check fails if it is stale
tools/mp adopt <path> [--name n] [--kind k] [--status s]   # registers an existing folder
```

- Home: `$MACPLUGINS_HOME`, else the repo that holds `mp`, else `~/Developer/macplugins`. Symlink `mp` into
  `~/.local/bin` to call it from anywhere.
- `new` copies `incubator/summon/templates/<kind>` (the templates `summon project new` uses; `menubar` is the
  default), renames `Starter` to the PascalCase name and `<kind>-starter` to the kebab-case name, switches the
  bundle prefix to `local.macplugins.`, runs `git init`, registers it as `scratch` (`menubar-panel`, `launcher`,
  `hud` and `notch` apps are kind `menubar`, a `widget` is kind `app`), and rewrites `plugins.md`. A `claude-plugin` has no template: make the folder, then `adopt`.
- `promote` prints the `gh repo create` commands and the move, and runs nothing without `--yes`. It creates
  GitHub repos, so it needs the owner's OK every time.
- Edit `plugins.json` by hand for notes (`statusNote`, `devRepoNote`, `summary`, `where`, `title`), then run
  `tools/mp index`. Never edit `plugins.md` directly.

Registry fields: `name`, `kind` (menubar / app / cli / claude-plugin / screensaver), `status` (scratch /
incubating / dev / shipped / archived), `devRepo`, `publicRepo` (`owner/repo` or null), `bundleId`,
`portedFrom` (`{name, url, platform}` or null), `version` (null when unknown), `example` (true when the app
is a reference to clone on demand), `path` (relative to the home).

## local-ci.sh

`tools/local-ci.sh [ref|pr-number] [--no-post]` builds/tests **all** Swift packages outside `.build/` and `plugins/`
from a temporary detached worktree at the exact requested commit; it does not use PR package selection.
It also runs Summon's packaged `check.sh --skip-tests --runtime-smoke` lifecycle gate after the suites.
Caches/logs are under `~/Library/Caches/macplugins/local-ci/<toolchain>/release/`, with logs separated by commit
and run identity. It posts `local / swift (macOS)` (pending, then success/failure/error), unless `--no-post`.
Owned build scratch/worktree cleanup errors remain failures. This is not a substitute for the full hosted OS
matrix, release/GUI audit, workspace/privacy checks or manual acceptance. Use it for local pre-push checking
or when hosted Actions cannot run; the public workspace's GitHub Actions checks remain its merge gate:

```bash
tools/local-ci.sh 42 && gh pr merge 42 --merge --delete-branch
```

## ci-plan.sh

`tools/ci-plan.sh <event> <changed-files> <packages-json>` selects `swift.yml` jobs. A PR builds only the longest
matching package path: Summon/macctl on macOS 15 and 26, templates on macOS 26 only. A template change also
selects Summon; selected Summon enables packaged identity/Core lifecycle checking and the informational Xcode 27
leg, while selected macctl enables that leg and the crash matrix. `.claude/` and `tools/check-skills.py` select
design example typechecking. `docs/`, other `tools/`, `install.sh` and root/workspace Markdown skip package
builds (the workspace job still runs). Pushes, manual runs, empty/unknown diffs, workflows and otherwise
unclassified files select everything. Regression coverage lives in `tools/tests/test_ci_plan.py`.

[`templates.yml`](../.github/workflows/templates.yml) is separate: on template/copier path changes, it runs real
`project new` plus the generated project's check for menubar, menubar-panel, app, cli and screensaver. The local
`incubator/summon/scripts/check-templates.sh [kind...]` defaults to all nine starter kinds; its widget gate needs
Xcode. Do not equate the hosted five-kind matrix or raw SwiftPM tests with complete widget-extension validation.

## check-workspace.sh

Workspace hygiene gate, active in `.github/workflows/swift.yml` on every push and pull request.
The reusable job snippet for other workspaces is in `tools/ci/check-workspace.yml`.

```bash
tools/check-workspace.sh
```

- Fails on a `Package.swift` outside the allowed roots (`macctl/`, `incubator/`, listed once
  at the top of the script).
- Fails on a tracked file over 2 MB, except the Summon wallpaper and brand allowlist, which it prints.
- Runs `tools/mp index --check` when `jq` is installed.
- Runs `tools/okf-index.py --check`: every page in `docs/` has OKF frontmatter and every `index.md` is current.
- Runs `tools/check-skills.py` for the six first-party design skills.
- Checks the shared base `VERSION` against tracked development Summon version constants, its source plist and macctl.

## check-skills.py

Checks the six modern and historical design skills for required metadata, concise entrypoints,
routing tables, examples, gotchas, and contained local reference paths. Vendored skills are excluded.
On macOS, `--compile-swift` typechecks every Swift example as an independent Swift 6 unit with a
macOS 15 deployment target; it does not execute snippets or prove visual/accessibility behavior.

```bash
python3 tools/check-skills.py
python3 tools/check-skills.py --compile-swift
python3 -m unittest discover -s tools/tests -p 'test_*.py'
```

GitHub CI runs structural and regression checks on Linux and example typechecking on macOS.

## okf-index.py

Keeps `docs/` a conformant [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
(v0.2) bundle. Every page other than `index.md` and `log.md` starts with YAML frontmatter carrying `type`, `title`
and `description` (plus `tags`; plans also `status` and `created`). The script checks that and writes one
`index.md` per folder: subfolders first, then pages grouped by type, plans newest first.

```bash
python3 tools/okf-index.py           # regenerate docs/**/index.md
python3 tools/okf-index.py --check   # exit 1 on missing frontmatter or a stale index
```

- A new folder under `docs/` needs a title and description in `DIRS` at the top of the script.
- Never edit an `index.md` by hand. Notable changes get a dated line in `docs/log.md`.

## docs-site.py and the wiki site

[`documentation.md`](documentation.md) is the authoritative maintenance guide for the wiki-style website.
`mkdocs.yml` configures navigation/search, `requirements-docs.txt` pins the documentation-only dependencies,
and `tools/docs-site.py` stages the existing Markdown rather than maintaining a second content copy.

```bash
python3 -m venv /tmp/summonos-docs-venv
/tmp/summonos-docs-venv/bin/python -m pip install -r requirements-docs.txt
/tmp/summonos-docs-venv/bin/python tools/docs-site.py serve
/tmp/summonos-docs-venv/bin/python tools/docs-site.py build
```

`build` always uses MkDocs strict mode and defaults to external-cache output. Optional `--site-dir` takes an
absolute path outside the source checkout; `--ref main` chooses the source-link ref. See the maintenance guide
for deployment and local-preview details. Docs tooling does not add runtime Swift package dependencies.

## publish-public.sh

Publishes a dev-repo branch to the public repo as one clean commit.

```bash
tools/publish-public.sh plugins/<name> [branch] "<commit message>"
```

- Exports the branch with `git archive` and drops `PROJECT-CONTEXT.md` (agent memory).
- Refuses to publish if any regex in `tools/private-patterns.txt` matches. That file is gitignored
  and must contain usable patterns. Invalid patterns, read errors, binary matches and private symlink targets block publishing.
- CI (`swift.yml`, workspace job) runs the same scanner over every tracked file of this repo with
  `tools/public-patterns.txt`: generic checks only (private IPv4 ranges, MACs outside `00:00:5e:00:53:xx`, personal
  mail domains), since the private file never leaves your Mac.
- Commits with your GitHub noreply address, so the author email never reaches the public history.
- Needs `gh` signed in and the public repo `<login>/<name>` to exist.

## release.yml (GitHub Actions)

[`release.yml`](../.github/workflows/release.yml) builds universal arm64/x86_64 `summon`, macctl and Summon.app
on `macos-26`. It validates signatures, both architectures, compiled versions and the staged manifest/plist,
then runs the candidate installer with `--verify-only`. The archive contains the app, `bin/`, bundled installer
and its Python validators, plus `SHA256SUMS`. A matching `v$(cat VERSION)` tag publishes an attested GitHub
**prerelease**, not a qualified production release. Successful `Swift (macOS)` push CI on `main` triggers a build
of that exact successful SHA for the rolling `edge` prerelease. It never publishes an arbitrary latest `main`.
An edge trigger can fail or remain stale; inspect the asset revision rather than assuming it is current.
Manual dispatch and matching release/install-path PRs are artifact-only dry runs, without release publication
or attestation. Builds default to ad-hoc previews; optional Developer ID signing/notarization runs only when
the required secrets are set. [Release status](status.md) separates source implementation from publication.

[`release-smoke.yml`](../.github/workflows/release-smoke.yml) installs published/manual releases with the public
installer; a matching PR instead builds, verify-only checks and installs its candidate on a disposable hosted
runner. It checks both CLIs, doctor and context. Published/PR runs additionally invoke the guarded runtime UI
audit; manual dispatch skips that GUI step. A failed profiler or missing prerequisite is not acceptance.

## release.sh

Builds a plugin and uploads the `.app` as a zip to the public repo's GitHub Releases.

```bash
tools/release.sh plugins/<name> ["extra release notes"]
```

- Runs only from clean `main`, checks that its exported source matches the public commit, and builds that exact
  public SHA in isolation. `scripts/check.sh` and signature verification must pass.
- Version and tag (`v<version>`) come from `Resources/Info.plist`.
- Zips with `ditto` and uploads `SHA256SUMS` and `release-source.txt` alongside the artifact; the release tag targets
  the source SHA. Without signing inputs the notes explicitly identify an ad-hoc preview.
- Set both `SUMMON_SIGN_IDENTITY` and `SUMMON_NOTARY_PROFILE` to use the production pipeline below. Partial
  configuration or failed notarization/assessment blocks publication.

## notarize-app.sh

```bash
SUMMON_SIGN_IDENTITY='Developer ID Application: Name (TEAMID1234)' \
SUMMON_NOTARY_PROFILE='stored-profile-name' \
tools/notarize-app.sh build/App.app build/distribution
```

Signs a copy of an existing app (including nested Mach-O executables) with hardened runtime/timestamps,
submits it to Apple, verifies acceptance, staples and validates the ticket, assesses Gatekeeper, then creates
an archive and checksum. The original build stays intact. Optional `SUMMON_SIGN_ENTITLEMENTS` names a reviewed
plist. Credentials remain in the maintainer's keychain. Real signing and clean-Mac verification remain release gates.

## uninstall.sh

```bash
tools/uninstall.sh           # preview
tools/uninstall.sh --apply   # remove unchanged receipt-owned files
```

Quit Summon first. A successful install records a private ownership receipt. Uninstall verifies fixed paths and
fingerprints before removing the app, commands or owned skill links. Modified/unowned files remain and are reported.
Projects, configuration, themes, checkpoints, logs and scheduled tasks remain. Remove recurring tasks before
uninstalling if you want them unscheduled. Old installations need a fresh successful install to create a receipt.


## render-previews.sh

Renders every `#Preview` in a plugin's UI target through Xcode MCP and saves PNGs to
`plugins/<name>/docs/previews/`.

```bash
tools/render-previews.sh plugins/<name> <App>UI [File.swift ...]
```

- Open the package in Xcode first (`xed plugins/<name>`); the first use per folder needs Allow in Xcode.
- With no files, it clears old PNGs and renders all previews. With files, it renders only those.
- Retries a failed render once. Needs `bun` and `jq`.

## xcode-mcp.ts

Calls one Xcode MCP tool without an MCP client, for sessions where the `xcode` server is not loaded.

```bash
bun tools/xcode-mcp.ts list
bun tools/xcode-mcp.ts <ToolName> '<json args>' [--out dir]
```

Text results print to stdout. Image results are saved as PNGs in `--out` (default `./build/previews`).

## readme-art.py

Renders the README art in `docs/assets/` as plain SVG: SummonOS wordmark and hero banner (with the tagline), macctl logo,
lifecycle diagram (each light and dark), project icons, the "Swift 6 / macOS 15+" pill, and terminal
cards from `macctl/docs/demo/*.txt`.

```bash
python3 tools/readme-art.py           # write the SVGs
python3 tools/readme-art.py --check   # exit 1 if a committed SVG is stale
```

- Pure Python, deterministic (frozen Inter metrics, no dates). Palettes and the ring mark come from
  `incubator/summon/design/brandkit.py`.
- Text that would overflow its box stops the script with the offending string.

## record-demos.sh

On a Mac with `macctl` installed: re-records the demo transcripts in `macctl/docs/demo/`, re-renders
the cards, and records `demo.gif` with [vhs](https://github.com/charmbracelet/vhs) when installed.

```bash
tools/record-demos.sh [--no-gif]
```

- Runs only read-only commands (`doctor`, `list`, `describe`, `get`, `diff`, `snapshot`, `--dry-run`);
  anything else is refused.
- Replaces `$HOME` with a placeholder home (user `you`) and every regex in `tools/private-patterns.txt` with `<private>`,
  in the transcripts and in the GIF.

## install-skills.sh

Links every skill in `.claude/skills/` into `~/.claude/skills/` (or `$CLAUDE_SKILLS_DIR`), so Claude Code
sessions anywhere on the Mac can use them, not only sessions started inside this workspace.

```bash
tools/install-skills.sh              # add symlinks (idempotent; repoints links to an older checkout)
tools/install-skills.sh --check      # linked / missing / blocked, changes nothing
tools/install-skills.sh --uninstall  # removes only links that point into this workspace
```

Symlinks mean `git pull` updates the skills with no reinstall. A real folder with the same name is never
replaced (reported as `blocked`, exit 1). Start a new Claude Code session to pick up added skills.
