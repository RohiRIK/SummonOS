# Starter

A command-line tool: one executable, argument parsing in a tested Core. Made with Summon from its command-line tool template.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `main.swift` only: runs the parsed command, prints, sets the exit code |
| `Sources/StarterCore/` | Argument parsing and the work itself, Foundation only, tested |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, which also works without Xcode), and the rest; writes `build/check-report.md` |

## Build and run

```bash
scripts/check.sh
swift run cli-starter --help
scripts/install.sh           # release build into ~/.local/bin/cli-starter
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
