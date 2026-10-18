# Starter

A menu bar app: a status item with a panel (`MenuBarExtra`, `.window` style), `LSUIElement`, no Dock icon. Made with Summon from its menu bar app template.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the `MenuBarExtra` and `Settings` scenes |
| `Sources/StarterUI/` | Panel, Settings window, `@Observable` model, `#Preview`s |
| `Sources/StarterCore/` | Logic, Foundation only, tested |
| `Resources/Info.plist` | Bundle id `local.summon.menubar-starter`, `LSUIElement` |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests, and the rest; writes `build/check-report.md` |

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
