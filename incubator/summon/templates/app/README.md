# Starter

A full window app: `WindowGroup` + `NavigationSplitView`, a Dock icon, menus with ⌘ shortcuts. Made with Summon from its window app template.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the `WindowGroup`, menu commands and `Settings` scenes |
| `Sources/StarterUI/` | Sidebar + detail window, Settings window, `@Observable` model, `#Preview`s |
| `Sources/StarterCore/` | Logic, Foundation only, tested |
| `Resources/Info.plist` | Bundle id `local.summon.app-starter` |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests, and the rest; writes `build/check-report.md` |

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.app
open build/Starter.app
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
