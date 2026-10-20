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

You need macOS 15 or newer, Xcode (or the Command Line Tools) with Swift 6, `git`, `python3`, and
[`shellcheck`](https://www.shellcheck.net) for shell changes.

```sh
git clone https://github.com/RohiRIK/SummonOS && cd SummonOS
./install.sh            # builds and installs this checkout: Summon, the summon CLI, macctl
```

## Build and test

Every Swift package (`macctl/`, `incubator/summon/`, `examples/*`, `incubator/summon/templates/*`) builds and
tests on its own:

```sh
cd macctl && swift build && swift test
cd incubator/summon && scripts/test.sh
```

Before you open a pull request, run the workspace checks from the repo root:

```sh
tools/check-workspace.sh              # package locations, file sizes, plugins.md, docs bundle
python3 tools/readme-art.py --check   # README art matches tools/readme-art.py
python3 tools/okf-index.py --check    # docs/ frontmatter and indexes
shellcheck install.sh tools/*.sh      # any shell you touched
```

CI (`.github/workflows/swift.yml`) builds and tests every package on a macOS runner for each push.

## How we build

The short version of [`AGENTS.md`](AGENTS.md):

- **Swift 6 and SwiftUI**, AppKit only where SwiftUI has no API. Minimum macOS 15; Liquid Glass behind
  `if #available(macOS 26, *)`. SwiftPM only, no `.xcodeproj`.
- **No third-party dependencies** unless a skill in `.claude/skills/` says so. Tests use swift-testing, and
  core logic is written test-first.
- **Real apps, no stubs:** every screen, action and setting you add is reachable and works offline.
- **Menu bar apps:** the panel holds the app's job; every preference lives in a separate Settings window
  (`Settings…`, ⌘,). The panel footer is `Settings…` and `Quit` only.
- **Design:** view work goes through the `MacUX` skill. Look at the rendered result before you call it done.
- **Changing the Mac:** system settings change only through `macctl`, so every change can be undone.
- **Privacy:** fixtures use documentation values only (`192.0.2.x`, `00:00:5e:00:53:xx`). Never commit real
  IPs, MAC addresses, SSIDs, hostnames, tokens or personal paths.

## Docs

`docs/` is an [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
bundle. Each page starts with YAML frontmatter (`type`, `title`, `description`, `tags`; plans also `status`
and `created`). Do not edit `index.md` files by hand: run `python3 tools/okf-index.py`. Add a line to
[`docs/log.md`](docs/log.md) for a notable change. A user-visible feature also goes in
[`docs/features.md`](docs/features.md).

## Pull requests

- Branch from `main`; never push to `main`.
- [Conventional commits](https://www.conventionalcommits.org): `feat:`, `fix:`, `docs:`, `chore:` and so on.
- Keep a pull request to one change. Say what a user sees before and after, and how you checked it
  (tests, previews, a run on a Mac). Screenshots help for any UI change.
- CI must be green before merge.

## License

By contributing, you agree that your contribution is licensed under the [MIT License](LICENSE).
