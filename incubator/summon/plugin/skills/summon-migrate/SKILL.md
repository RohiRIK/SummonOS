---
name: summon-migrate
description: >
  Migrate existing macOS apps, legacy macos-plugins, or external SwiftPM/Xcode projects into Summon (~/Summon/Apps/<name>).
  Standardizes project structure, registers the app in Summon's private registry, verifies Swift 6 / SwiftUI compatibility,
  ensures AppIcon.icns and docs/screenshots art assets are present, captures showcase shots, and verifies health checks.
  Triggers: migrate app, import app into summon, port app to summon, summon-migrate, summon-migration, "migrate my apps".
---

# Migrating an App into Summon

Use this skill when importing, porting, or migrating existing standalone Mac apps or legacy `macos-plugins` into Summon (`~/Summon/Apps/<name>`).

A first-class Summon app lives in `~/Summon/Apps/<name>`, is registered in `~/.config/summon/projects.json`, builds cleanly, passes health checks, and is presented in Summon Menu and Settings › My Apps.

---

## The Migration Pipeline

Follow these steps in order when migrating any app:

### 1. Identify and Inspect the Source App

Inspect the source directory:
- **Type/Kind**: Is it a menu bar app (`MenuBarExtra` / `NSStatusItem`), window app (`WindowGroup`), CLI tool, or screensaver?
- **Git State**: Check if it's already a git repository (`git remote -v`) to preserve history and remote tracking (`origin`).
- **Dependencies & Tools**: Inspect `Package.swift` for platform targets (macOS 14/15/26), Swift tools version (6.0), and dependencies.

### 2. Move or Import into `~/Summon/Apps/<name>`

Import the app into Summon:
```bash
# If copying/importing from an external path:
summon project import "<source_path>" [--name <kebab-name>] [--kind menubar|app|cli|screensaver]

# Or if the folder is already in ~/Summon/Apps/<name>:
summon project register <name> [--kind menubar|app|cli|screensaver]
```

This ensures:
- The app resides at `~/Summon/Apps/<name>`.
- The app is registered in `~/.config/summon/projects.json`.
- The git remote is preserved in the project registry.

### 3. Normalize Project Structure

Every Summon app requires:
1. **`Package.swift`**:
   - Swift tools version: `// swift-tools-version: 6.0`
   - Platform: `.macOS(.v15)` (the minimum; Liquid Glass behind `if #available(macOS 26, *)`)
2. **`Resources/`**:
   - `Resources/AppIcon.icns` (custom icon)
   - `Resources/Info.plist` (with `LSUIElement = true` for menu bar apps)
3. **`docs/screenshots/`**:
   - At least one UI screenshot (`panel.png`, `panel-light.png`, `panel-dark.png`, or `window.png`).
   - If missing, generate shots using:
     ```bash
     summon project shots <name>
     ```
     Or copy relevant UI preview captures into `docs/screenshots/`.
4. **`scripts/`**:
   - Standard build, test, and bundle scripts (`scripts/bundle.sh`, `scripts/check.sh`).

### 4. Build & Verify Health

1. Compile the app:
   ```bash
   cd ~/Summon/Apps/<name>
   swift build
   ```
2. Check health in Summon:
   ```bash
   summon project list
   ```
   Open **Settings › My Apps** or click into the panel to ensure the app is listed and has a green **Healthy** badge.
3. If health reports a warning (e.g., `No AppIcon` or `No Screenshots`), resolve it:
   - For icons: use `summon-art` (icons.md) to generate candidate icons and compile `.icns`.
   - For shots: run `summon project shots <name>` or provide screenshots in `docs/screenshots/`.

---

## Batch Migration

When migrating multiple legacy plugins (e.g. from `macos-plugins/plugins/*`):
1. Copy each plugin directory into `~/Summon/Apps/<name>`.
2. Register each with `summon project register <name>`.
3. Verify `docs/screenshots/` has preview PNGs (copy from `docs/previews/` if needed).
4. Run `swift build` on each project to ensure clean compilation.
5. Re-check `summon project list` and test in the Summon menu bar panel.
