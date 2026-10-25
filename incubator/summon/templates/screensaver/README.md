# Starter

A screensaver: a `.saver` bundle whose `ScreenSaverView` subclass draws from a tested Core. Made with Summon from its screensaver template.

## Layout

| Path | What it is |
|---|---|
| `Sources/Starter/` | The `ScreenSaverView` subclass (`StarterView`): drawing and lifecycle only |
| `Sources/StarterCore/` | The animation, Foundation only, tested (`SummonThemeFile` reads the Summon theme) |
| `Resources/` | `Info.plist`: The `.saver` bundle's plist: `NSPrincipalClass` `StarterView`, bundle id `local.summon.screensaver-starter`; `AppIcon.icns` (a placeholder: replace it with the summon-art skill) |
| `Tests/StarterCoreTests/` | swift-testing |
| `scripts/check.sh` | The gate: build, tests (`scripts/test.sh`, which also works without Xcode), and the rest; writes `build/check-report.md` |

## Build and run

```bash
scripts/check.sh
scripts/bundle.sh            # build/Starter.saver
scripts/install.sh           # copies it to ~/Library/Screen Savers; pick it in System Settings › Screen Saver
```

Requires macOS 15+ and Swift 6. No third-party dependencies.
