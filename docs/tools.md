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

The SummonOS installer. Piped from curl it downloads the newest GitHub release (prereleases included, or
`--version vX.Y.Z`), checks the zip against `SHA256SUMS` (a mismatch refuses), unpacks it and runs the bundled
Summon `scripts/install.sh`, which stages and rolls back like a source install. With no release published it
builds from source instead. `--from-source` clones into `~/.summonos` (`SUMMONOS_HOME`, branch `SUMMONOS_REF`);
run from a checkout it installs that checkout. A source build checks Swift 6, builds `macctl` into
`~/.local/bin` and runs Summon's `scripts/bundle.sh` and `scripts/install.sh`. Both end with `summon doctor`,
then offer `summon connect` on a terminal (default No); `--connect` runs it, `--yes` never prompts.
Agents follow [`docs/install-ai.md`](install-ai.md) instead, which wraps the same script with checks and a report.

```bash
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
```

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

`tools/local-ci.sh [ref|pr-number] [--no-post]`: the Swift package portion of `.github/workflows/swift.yml`, run on this Mac. Checks out
exactly that commit in a temporary worktree, builds and tests every `Package.swift` outside `.build/` and `plugins/`
(build cache in `~/Library/Caches/macplugins/local-ci`, logs per package under `logs/<sha>/`), and posts the result
as the commit status `local / swift (macOS)` (pending, then success or failure). Now that the repo is public,
GitHub Actions runs `swift.yml` for free and is the gate; use this when Actions cannot run, or to test on your own
Mac before pushing:

```bash
tools/local-ci.sh 42 && gh pr merge 42 --merge --delete-branch
```

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

`.github/workflows/release.yml` builds the SummonOS release on `macos-26`: universal (arm64 + x86_64) `summon`,
`macctl` and `Summon.app` (`bundle.sh --universal`), ad-hoc signed and verified (`codesign`, `lipo -archs`,
`--version`), in `summonos-<version>-macos-universal.zip` (`Summon.app`, `bin/`, `scripts/install.sh`) plus
`SHA256SUMS`. A `v*` tag that equals `v$(cat VERSION)` also attests the zip (`actions/attest-build-provenance`) and
publishes a GitHub prerelease with generated notes. `workflow_dispatch`, and a PR that touches the release or install
path, is a dry run: the files are a workflow artifact only. Developer ID signing and notarization
(`tools/notarize-app.sh`) run only when the signing secrets are set.

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
