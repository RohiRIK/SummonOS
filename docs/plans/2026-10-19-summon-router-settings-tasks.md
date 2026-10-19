# Plan: Summon — router skill, granular settings, recurring tasks (2026-10-18)

Order confirmed by the owner: A, B, C, D, then changelog + README, each merged on clean CI. Quick task desk: skipped for now.

- [x] A. `summon` skill = router ("summon, build a web app" → right skill); Mac-customization content moves to `summon-mac`.
- [x] B. Per-agent settings: enabled, model, which Summon skills it gets (`~/.config/summon/agents.json`); linker and
      launch honour them; model flags verified per CLI.
- [x] C. Settings window with a sidebar (General, Agents, Terminal, Notifications, Appearance, Tasks); few plain rows each.
- [x] D. Recurring agent tasks: `summon task add|list|remove|run`, launchd LaunchAgent, headless print mode, checkpoint,
      result in Activity + notification; managed in Settings › Tasks.
- [x] E. CHANGELOG + README refresh; PR; merge on clean CI.

# Plan: Summon projects (2026-10-18, Rohi's handoff; "fold all together")

- [x] Templates for menubar, app, cli, screensaver in `incubator/summon/templates/`, each with check.sh, LICENSE,
      PROJECT-CONTEXT.md; no CI until a repo exists.
- [x] `~/Summon` created on install and launch; agents start there; skills say `~/Summon`.
- [x] Private registry `~/.config/summon/projects.json`; `summon project new|list|path|forget`.
- [x] `summon project repo`: private only, after a native dialog enforced in code; adds CI.
- [x] Make Something + `/summon:new-*` use the templates.
- [ ] Run on the Mac: dialog, gh repo create, each template's check.sh; render #34's Settings previews.

## Review
- A–E built and verified on the Mac (router routing test with agy, per-agent links, Settings tabs captured,
  recurring task run directly and by launchd). #35 merged while CI was failing (GitHub Actions billing); lesson
  recorded. #41 (D + E) waits for CI.
