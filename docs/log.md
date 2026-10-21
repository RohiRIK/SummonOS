# Docs update log

## 2026-10-21
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
