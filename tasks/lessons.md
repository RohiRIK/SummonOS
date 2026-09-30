# Lessons

Rules learned from corrections. One line each, newest last.

- Everything lives in this workspace: plugin repos under `plugins/<name>/`, skills in `.claude/skills/`. Never put repos elsewhere.
- No personal names in repo or plugin names.
- No GitHub Actions (no billing). All tests run locally; post results as a PR comment with `scripts/pr-report.sh`.
- Plugins are MIT-licensed (changed from all-rights-reserved on 2026-09-29), with upstream MIT notices kept.
- UI must look like the system menus (Wi-Fi / Control Center), not a generic form. Check `MacUX/MenuPanel.md` before any panel UI.
- Looks matter as much as function: live data gets a polished Control Center-style module, not plain rows.
- Approved look (2026-09-29): system Wi-Fi menu structure + Control Center module for live data. Reuse it as the default for new panels.
- Reference app for menu bar UX: CodexBar (MIT) at /Applications/CodexBar.app, source github.com/steipete/CodexBar. Check it before inventing a pattern.
- Network features live in the menu bar panel (tabs). App settings (permissions, login item, theme) live in a Settings window (⌘,), plus a first-launch onboarding window. Panel footer = Settings… + Quit only.
- Public plugin repos get clean snapshots via tools/publish-public.sh; dev history (with author email) stays in private <name>-dev.
- Never commit real network data (IPs, MACs, SSIDs, VPN names) in fixtures; use documentation ranges.
- App settings (Open at Login, toggles, theme) never go in the menu bar panel, even when there is only one. Always a separate Settings window opened by `Settings…` (⌘,) in the panel footer. (mac-calendar, 2026-09-29)
