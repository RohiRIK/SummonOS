# Current plan

The active plan goes here. When a plan is done, move it to `docs/plans/YYYY-MM-DD-<name>.md`
and leave this file with only what is still in progress.

# Plan: Summon — router skill, granular settings, recurring tasks (2026-10-18)

Order confirmed by the owner: A, B, C, D, then changelog + README, each merged on clean CI. Quick task desk: skipped for now.

- [x] A. `summon` skill = router ("summon, build a web app" → right skill); Mac-customization content moves to `summon-mac`.
- [ ] B. Per-agent settings: enabled, model, which Summon skills it gets (`~/.config/summon/agents.json`); linker and
      launch honour them; model flags verified per CLI.
- [ ] C. Settings window with a sidebar (General, Agents, Terminal, Notifications, Appearance, Tasks); few plain rows each.
- [ ] D. Recurring agent tasks: `summon task add|list|remove|run`, launchd LaunchAgent, headless print mode, checkpoint,
      result in Activity + notification; managed in Settings › Tasks.
- [ ] E. CHANGELOG + README refresh; PR; merge on clean CI.
