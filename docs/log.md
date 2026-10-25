# Docs update log

## 2026-10-25
* **Update**: [Features](features.md): Visual QA screenshots every Settings page, Activity and the crash alert; `summon://settings/<section>` opens a Settings page. Phase 5 (UX/UI overhaul) plan approved.
* **Update**: SummonOS 0.1.1 (VERSION, summon, macctl, Summon.app): undo any agent session, hotkey with screen context, one-click Accessibility, `summon connect` hooks, whole-Mac themes with one undo, macOS 27 wallpaper fix, live Mac events.
* **Update**: [README](../README.md) rewritten around "the agentic layer for the Mac": what you get (context, MCP + connect, hotkey, undo, themes), install flags and what ad-hoc preview builds mean, a 60-second tour, demo placeholders, status and credits (Omarchy).
* **Update**: [Features](features.md): live Mac events (network, VPN, low disk, battery, thermal, displays) logged by Summon.app as `mac.*`, `summon events --follow`, MCP tool `mac_events`.
* **Update**: [Features](features.md): `summon checkpoint undo` also removes the files a theme created (recorded as the `created` ref), so undoing a theme leaves no generated files behind.
* **Update**: [MacAppArchitecture](../.claude/skills/MacAppArchitecture/SKILL.md) gotchas: macOS 27 `desktopImageURL` lags behind a wallpaper write; ad-hoc builds and stale Accessibility entries.
* **Update**: [Features](features.md): `summon theme set` also sets the macOS accent (new macctl setting `appearance.accent-color`, 39 settings), VS Code/Cursor and Neovim, and takes one checkpoint so the whole look undoes at once.
* **Update**: [Features](features.md): `summon connect` records Claude Code and Codex sessions in Activity (start and end hooks), so the plugin is optional and no longer declares the MCP server; doctor asks for `summon connect claude`; Fix with AI skips crashes already handed to an agent.
* **Update**: [Features](features.md): Settings › General › Permissions asks for Accessibility in one click; `summon skills link` links only into agents that are installed.
* **Update**: [Features](features.md): the agent hotkey and Ask Agent start the agent with what is on screen (app, window, selected text, browser page, Finder selection), each field can be turned off.
* **Update**: [Features](features.md): sessions through `summon mcp` take a checkpoint before the first change and are logged under the agent's name; the panel offers "Undo <Agent> Session (N changes)…" only when there is something to undo.
* **New**: [Agent MCP configs](research/2026-10-25-agent-mcp-configs.md): where the eight agents `summon connect` reaches keep their MCP servers, instructions and start hooks.
* **Update**: [Features](features.md): `summon connect` adds a session-start hook (`summon context --hook <agent>`) to Claude Code, Codex, Cursor and the Antigravity CLI, so sessions start with the Mac snapshot.
* **Update**: [Features](features.md): `summon connect` / `disconnect` register the MCP server and a This Mac note with every installed agent; Hermes and OpenClaw join the agent registry.
* **Update**: [Features](features.md), [Tools](tools.md), [Install for agents](install-ai.md): `release.yml` builds a universal, ad-hoc signed SummonOS release (zip, `SHA256SUMS`, attestation, prerelease on a `v*` tag); `install.sh` installs the newest release by default, verifies its checksum, falls back to source, and offers `summon connect`.
* **Update**: [Features](features.md): `summon mcp`, an MCP server with 10 tools (Mac context, macctl settings with undo, checkpoints, crashes) for every agent; the Claude Code plugin declares it.
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
