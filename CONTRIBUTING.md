# Contributing to SummonOS

Thanks for looking. SummonOS is an experiment in what a Mac feels like when an agent is part of the system:
[Summon](incubator/summon/README.md), [macctl](macctl/README.md), and small native apps built with them. It is
early, opinionated and moves fast. Issues, ideas and pull requests are all welcome, and so are agents doing
the work: [`AGENTS.md`](AGENTS.md) holds the rules every agent (and person) follows here.

## Before you start

- **Ideas and bigger changes:** open an issue first, so we can agree on the shape before you build it.
- **Bugs:** open an issue with your macOS version, `summon doctor` and `macctl doctor` output, and the steps.
- **Security problems:** never in a public issue. See [`SECURITY.md`](SECURITY.md).

## Set up

For Swift work, use macOS 15+ and Swift 6 with a recent macOS SDK (Xcode 26+ for the full app/WidgetKit/App
Intents gates). Command Line Tools can build/test supported package-only paths; they cannot build the widget
extension or generate Summon's optional Siri metadata. Also install `git`, `python3`, `jq` for registry tools,
and [`shellcheck`](https://www.shellcheck.net) for shell changes. Xcode MCP previews additionally need Xcode,
`bun` and its per-workspace approval. Docs-only contributors can use the Python website tooling without macOS.

```sh
git clone https://github.com/RohiRIK/SummonOS && cd SummonOS
# Installing is optional and replaces your account's live Summon/macctl:
./install.sh
```

Run without install options, a checkout builds **that checkout**, not the newest release or another branch.
The base `VERSION` is currently **0.2.4**; later branch hardening/About/inventory/accent work is unreleased.
For download channels and their exact selection/fallback behavior, see [installation](docs/install-ai.md) and
[release/branch status](docs/status.md). Do not use a normal install merely to audit a candidate:
`SUMMONOS_APP_SOURCE=/absolute/path/Summon.app incubator/summon/scripts/install.sh --verify-only`
validates its signature/packaged identity without replacing live files. It does not initialize user state
or prove GUI acceptance; supply `SUMMONOS_MACCTL_SOURCE` as well when validating a built macctl.

## Build and test

Every Swift package (`macctl/`, `incubator/summon/`, `incubator/summon/templates/*`) has its own build/tests.
Keep build caches outside cloud-synced source trees. For example, with Xcode selected:

```sh
swift test --package-path macctl --scratch-path ~/Library/Caches/macplugins/macctl/build
incubator/summon/scripts/test.sh
```

Use the provided `scripts/test.sh` in Summon/generated templates for their Command Line Tools Testing-framework
setup rather than assuming bare `swift test` works under CLT. The widget package's Core tests are separate from
its full `scripts/check.sh`/Xcode extension gate. For a Summon change, the packaged gate is:

```sh
incubator/summon/scripts/check.sh --runtime-smoke
```

It builds macctl and the signed app, validates App Intents, identity/CLI catalog, plist/themes, and runs an
actual Core lifecycle fixture. `--skip-tests` is only for a job that already ran the same suites. The guarded
runtime UI audit needs a disposable hosted runner or explicitly authorized test account, and does not replace
manual VoiceOver, Reduce Transparency, native notification or displayed-frame/retained-memory acceptance.

Before you open a pull request, run the workspace checks from the repo root:

```sh
tools/check-workspace.sh             # package roots, sizes, indexes, design skills, base version
python3 -m unittest discover -s tools/tests -p 'test_*.py'
python3 tools/readme-art.py --check   # when README artwork/generation changes
python3 tools/okf-index.py --check    # docs frontmatter and generated indexes
shellcheck install.sh tools/*.sh     # choose the shell files you actually touched, including app scripts
```

CI ([`swift.yml`](.github/workflows/swift.yml)) selects packages touched by a PR. Summon/macctl run on macOS
15 and 26 with Xcode 26; raw templates run on macOS 26, and template edits also select Summon. Docs/workspace
tool edits skip package builds, while pushes to `main`, manual dispatch, workflows and unclassified changes
select everything. Workspace hygiene, privacy, tooling regressions and selected shell lint run independently
on Linux. Structural checks cover six first-party design skills; their macOS Swift-example typecheck job is
selected for skill edits (and full runs). Selected Summon also runs packaged identity/Core lifecycle checking;
selected macctl runs the crash matrix. The Xcode 27 preview leg is informational. The separate
[`templates.yml`](.github/workflows/templates.yml) generated-project matrix covers five kinds, not all nine.
See [CI/tool reference](docs/tools.md#ci-plansh). `tools/local-ci.sh [ref|pr] [--no-post]` checks all packages and
the Core lifecycle gate in a temporary worktree on one Mac; it is not the full hosted OS/GUI/acceptance matrix.

## How we build

The short version of [`AGENTS.md`](AGENTS.md):

- **Swift 6 and SwiftUI**, AppKit only where SwiftUI has no API. Minimum macOS 15; Liquid Glass behind
  `if #available(macOS 26, *)`. SwiftPM by default; the **widget template is the one `.xcodeproj` exception**,
  needed to embed its WidgetKit extension while keeping logic/views in the package.
- **No third-party runtime Swift dependencies** unless a skill in `.claude/skills/` says so. Documentation-only
  Python dependencies are pinned separately. Tests use swift-testing, and
  core logic is written test-first.
- **Real apps, no stubs:** every screen, action and setting you add is reachable and works offline.
- **Menu bar apps:** the panel holds the app's job; every preference lives in a separate Settings window
  (`Settings…`, ⌘,). The panel footer is `Settings…` and `Quit` only.
- **Design:** view work goes through the `MacUX` skill. Look at the rendered result before you call it done.
- **Changing the Mac:** use `macctl` and document its recovery contract, not a blanket undo promise. Checkpoints
  cover supported settings, successfully captured config and explicitly recorded theme-created files, not
  arbitrary new files, overwritten external editor configs or external effects. See [security/recovery](docs/security-model.md).
- **Privacy:** fixtures use documentation values only (`192.0.2.x`, `00:00:5e:00:53:xx`). Never commit real
  IPs, MAC addresses, SSIDs, hostnames, tokens or personal paths.

## Docs

`docs/` is both an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
bundle and the source of the searchable wiki website. Pages carry YAML frontmatter (`type`, `title`,
`description`, `tags`; plans also `status` and `created`). Preserve historical plan/research provenance rather
than rewriting old findings into current product contracts. Do not edit generated `index.md` files: run
`python3 tools/okf-index.py`. Add a dated entry to [`docs/log.md`](docs/log.md) for notable changes; update
[`docs/features.md`](docs/features.md) for user-visible behavior.

The website uses `mkdocs.yml`, pinned `requirements-docs.txt` and `tools/docs-site.py`, with no permanent second
copy of the Markdown. Set up and preview/build it with:

```sh
python3 -m venv /tmp/summonos-docs-venv
/tmp/summonos-docs-venv/bin/python -m pip install -r requirements-docs.txt
/tmp/summonos-docs-venv/bin/python tools/docs-site.py serve
/tmp/summonos-docs-venv/bin/python tools/docs-site.py build
```

`build` runs MkDocs strict mode and writes outside the checkout by default. See
[`docs/documentation.md`](docs/documentation.md) for navigation, source-link rewriting, external output paths
and deployment. Source-relative links should remain useful both in repository Markdown and the generated site.

## Pull requests

- Branch from `main`; never push to `main`.
- [Conventional commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `chore:` and so on.
- Keep a pull request to one change. Say what a user sees before and after, and how you checked it
  (tests, previews, a run on a Mac). Screenshots help for any UI change.
- CI must be green before merge.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
