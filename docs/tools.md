# Tools

Scripts in [`tools/`](../tools). Run them from the workspace root. Per-plugin scripts
(`scripts/test.sh`, `bundle.sh`, `check.sh`, `pr-report.sh`) live in each plugin repo and are
described in `MacAppBuild/Scaffold.md`.

## install.sh (repo root)

The SummonOS installer. Piped from curl it clones into `~/.summonos` (`SUMMONOS_HOME`, branch `SUMMONOS_REF`);
run from a checkout it installs that checkout. It checks macOS 15+ and Swift 6, builds `macctl` into
`~/.local/bin`, runs Summon's `scripts/bundle.sh` and `scripts/install.sh`, then `summon doctor`.
Agents follow [`docs/install-ai.md`](install-ai.md) instead, which wraps the same script with checks and a report.

```bash
curl -fsSL https://raw.githubusercontent.com/RohiRIK/macos-plugins/main/install.sh | bash
```

## mp

Manages the plugin home: the registry `plugins.json` (source of truth), the generated `plugins.md`, and
the `plugins/` and `scratch/` folders. Needs `jq` and `git`; `gh` for `promote` and `clone`.

```bash
tools/mp new <name> [--kind menubar|app|screensaver]   # scratch/<name> from examples/<kind>-starter, registered
tools/mp promote <name> [--owner <login>] [--yes]      # private <name>-dev + public <name>, moves to plugins/
tools/mp clone (<name>... | --all)                     # clones registered dev repos into plugins/<name>
tools/mp list [--json]                                 # the registry
tools/mp status                                        # branch, dirty, version, registry vs disk, unregistered folders
tools/mp index [--check]                               # regenerates plugins.md; --check fails if it is stale
tools/mp adopt <path> [--name n] [--kind k] [--status s]   # registers an existing folder
```

- Home: `$MACPLUGINS_HOME`, else the repo that holds `mp`, else `~/Developer/macplugins`. Symlink `mp` into
  `~/.local/bin` to call it from anywhere.
- `new` copies the starter, renames `Starter` to the PascalCase name and `menubar-starter` to the kebab-case
  name, runs `git init`, registers it as `scratch`, and rewrites `plugins.md`. `app` and `screensaver` start
  from the menu bar starter until they have their own.
- `promote` prints the `gh repo create` commands and the move, and runs nothing without `--yes`. It creates
  GitHub repos, so it needs the owner's OK every time.
- Edit `plugins.json` by hand for notes (`statusNote`, `devRepoNote`, `summary`, `where`, `title`), then run
  `tools/mp index`. Never edit `plugins.md` directly.

Registry fields: `name`, `kind` (menubar / app / cli / claude-plugin / screensaver), `status` (scratch /
incubating / dev / shipped / archived), `devRepo`, `publicRepo` (`owner/repo` or null), `bundleId`,
`portedFrom` (`{name, url, platform}` or null), `version` (null when unknown), `example` (true when the app
is a reference to clone on demand), `path` (relative to the home).

## local-ci.sh

`tools/local-ci.sh [ref|pr-number] [--no-post]`: what `.github/workflows/swift.yml` does, run on this Mac. Checks out
exactly that commit in a temporary worktree, builds and tests every `Package.swift` outside `.build/` and `plugins/`
(build cache in `~/Library/Caches/macplugins/local-ci`, logs per package under `logs/<sha>/`), and posts the result
as the commit status `local / swift (macOS)` (pending, then success or failure). Commit statuses are free; GitHub
Actions runs need a paid plan the owner does not have. Merge a PR only when its head has the green status:

```bash
tools/local-ci.sh 42 && gh pr merge 42 --merge --delete-branch
```

## check-workspace.sh

Workspace hygiene gate, meant for CI. Not in CI yet: the job snippet is in `tools/ci/check-workspace.yml`,
and the owner has to paste it into `.github/workflows/swift.yml` (agents cannot edit workflows).

```bash
tools/check-workspace.sh
```

- Fails on a `Package.swift` outside the allowed roots (`macctl/`, `incubator/`, `examples/`, listed once
  at the top of the script).
- Fails on a tracked file over 2 MB, except the Summon wallpaper and brand allowlist, which it prints.
- Runs `tools/mp index --check` when `jq` is installed.

## publish-public.sh

Publishes a dev-repo branch to the public repo as one clean commit.

```bash
tools/publish-public.sh plugins/<name> [branch] "<commit message>"
```

- Exports the branch with `git archive` and drops `PROJECT-CONTEXT.md` (agent memory).
- Refuses to publish if any regex in `tools/private-patterns.txt` matches. That file is gitignored
  and must exist.
- Commits with your GitHub noreply address, so the author email never reaches the public history.
- Needs `gh` signed in and the public repo `<login>/<name>` to exist.

## release.sh

Builds a plugin and uploads the `.app` as a zip to the public repo's GitHub Releases.

```bash
tools/release.sh plugins/<name> ["extra release notes"]
```

- Runs only on `main`, and only if `scripts/check.sh` passes.
- Version and tag (`v<version>`) come from `Resources/Info.plist`.
- Zips with `ditto` to keep the signature, and writes install notes for an un-notarized app.

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
