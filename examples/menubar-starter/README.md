# Starter

`menubar-starter`: the smallest menu bar app that follows the workspace rules. A click counter in a
`MenuBarExtra` panel, `Settings…` and `Quit` in the panel footer, one preference in a separate Settings
window, and a tested Core.

Start a new plugin from it with `tools/mp new <name> --kind menubar`. That copies this folder to
`$MACPLUGINS_HOME/scratch/<name>/`, renames `Starter` to the PascalCase name and `menubar-starter` to
the kebab-case name, and registers it in `plugins.json`.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | `@main` only: the `MenuBarExtra` and `Settings` scenes |
| `Sources/StarterUI/` | Views, the `@Observable` model, `#Preview`s (library product, so previews run) |
| `Sources/StarterCore/` | Logic, Foundation only, tested |
| `Tests/StarterCoreTests/` | swift-testing |
| `Resources/Info.plist` | Bundle id `local.macplugins.menubar-starter`, `LSUIElement` |

## Build

```bash
swift build --scratch-path ~/Library/Caches/macplugins/menubar-starter
swift test --scratch-path ~/Library/Caches/macplugins/menubar-starter
```

Requires macOS 15+ and Swift 6. Bundling, previews and the check gate: `MacAppBuild/Scaffold.md` and
`MacAppBuild/Verify.md` (copy `scripts/` from mac-network).
