# Docs update log

## 2026-10-25
* **Update**: [Features](features.md): one SummonOS version (`VERSION`, 0.1.0): `summon version`/`--version`, `macctl --version`, shown by `summon doctor`. CI runs once per PR, adds `macos-15` and an informational Xcode 27 leg, and skips Swift jobs on docs-only changes.
* **Update**: [Features](features.md): `summon context` gives agents one snapshot of this Mac, with fields the user can hide in Settings › Agents; Settings lists all 7 tabs; Visual QA opens the panel (there is no launcher window).

## 2026-10-24
* **Update**: [Features](features.md): every agent prompt carries a Summon session brief; crash alerts are one style (Summon alert or banner) and never take the keyboard; task results come from Summon.app with Show Log and Ask Agent.
* **Update**: [Features](features.md): Summon's menu bar icon shows a running agent's elapsed time and tells VoiceOver; keyboard and URL panel opens are announced. New `examples/menubar-panel-starter` (`tools/mp new <name> --panel`).
* **Update**: [Menu bar and window mechanics](research/2026-10-18-mac-gui-design/03-menubar-and-window-mechanics.md): section 0, which requirement made SummonOS switch and what is still unverified.

## 2026-10-23
* **Update**: [Features](features.md): macctl declares a recovery contract per setting, previews undo (`undo --dry-run`), gates settings by `minimumOS`, adds `discover start|diff`, and grows to 38 settings (macOS 26 menu icons, macOS 27 menu bar keyboard navigation).
* **Update**: [ADR: macctl recovery](adr/ADR-macctl-recovery.md): addendum D4 (declared guarantees, undo preview, fault-schedule tests).

## 2026-10-22
* **Creation**: [Skill: summon-migrate](skills/summon-migrate.md): guides migrating external apps and legacy plugins into `~/Summon/Apps`, adds `summon project import` and `summon project register` CLI commands, and migrated `mac-network`, `mac-calendar`, and `mac-breathe`.
* **Update**: [Features](features.md): added automated real-time health checks and "Fix with AI" triggers for all app projects, themes, and art assets (AppIcon.icns, UI screenshots, wallpapers, art jobs).
* **Update**: [Features](features.md): added dedicated "My Apps" section in Settings with category drill-down navigation matching the menu bar panel.
* **Update**: [Features](features.md): added interactive panel back button with keyboard Escape pop and Delete key navigation.
* **Update**: [Features](features.md): Settings and Activity windows now open as dedicated, foreground NSWindows centered on the active display.
* **Update**: [Security and recovery model](security-model.md): user bin directories (~/.bun/bin, ~/.local/bin) take strict precedence over Homebrew paths; child process output buffer expanded to 16MB; checkpoint error records sanitized to 2,000 chars.

## 2026-10-21
* **Update**: [Features](features.md): added Appearance Theme Preview with 16:9 wallpaper thumbnail and Undo button; added one-click Homebrew installer for Ghostty and kitty terminals in Settings.
* **Update**: [Features](features.md): added ⌘↵ quick-launch for default agent in `~/Summon` and "My Apps" section in the menu bar panel for Summon-built projects.
* **Update**: [Features](features.md) CI section lists the new Visual QA (macOS) workflow: launcher and menu bar panel screenshots in light and dark on macOS 26 and 15, as run artifacts.

## 2026-10-20
* **Update**: [features](features.md): the Summon Menu now lives in the menu bar panel (⌃⌥Space, `summon panel`); the separate launcher window is gone (PR #61).
* **Creation**: [ADR: macctl prior state, journal and recovery](adr/ADR-macctl-recovery.md): per-key prior state, write-once header plus JSONL journal, `macctl recover`, the `recovery_pending` gate and test-only failpoints.
* **Update**: [Security and recovery model](security-model.md) covers the journal, its HMAC key, safe session ids and `undo --force`; [Features](features.md) describes crash recovery and `partial_restore`.
* **Update**: SummonOS made public under the owner’s approval; live GitHub CI verified after correcting non-relocatable Swift build caching.
* **Creation**: [Design skills and public preview](plans/2026-10-20-skills-public-preview.md): controlled skill tests, rendered samples, privacy review, and publication verification.
* **Update**: six design skills retested and repaired; CI now checks routing/references and typechecks Swift examples targeting macOS 15. Provider icon provenance is pinned in Summon’s third-party notices.
* **Creation**: [Security and recovery model](security-model.md): execution authority, exact checkpoint coverage, private diagnostics, tasks, and release boundaries.
* **Update**: feature, install, contribution and tooling docs follow the implemented hardening, ownership-aware uninstall, exact-source releases, and optional signing pipeline.
* **Creation**: [SummonOS production readiness](plans/2026-10-20-production-readiness.md): source audit, README URL review, verified test baseline, release blockers, and proposed implementation gates.

## 2026-10-19
* **Update**: docs/ became an Open Knowledge Format bundle: frontmatter on every concept, generated `index.md` per folder, this log. The plans table moved from `plans/README.md` to [plans/index.md](plans/index.md).
* **Creation**: [Install SummonOS (for an AI agent)](install-ai.md), the one-line install for coding agents.
* **Update**: the workspace was renamed SummonOS; [Features](features.md), [Workspace tools](tools.md) and [App lifecycle](workflow.md) follow the new name.
