# Lessons

Rules learned from corrections. One line each, newest last.

- Everything lives in this workspace: plugin repos under `plugins/<name>/`, skills in `.claude/skills/`. Never put repos elsewhere.
- No personal names in repo or plugin names.
- No GitHub Actions in private repos (no billing). All tests run locally; post results as a PR comment with `scripts/pr-report.sh`. Public repos (SummonOS since 2026-10-19) get Actions free.
- Plugins are MIT-licensed (changed from all-rights-reserved on 2026-09-29), with upstream MIT notices kept.
- UI must look like the system menus (Wi-Fi / Control Center), not a generic form. Check `MacUX/MenuPanel.md` before any panel UI.
- Looks matter as much as function: live data gets a polished Control Center-style module, not plain rows.
- Approved look (2026-09-29): system Wi-Fi menu structure + Control Center module for live data. Reuse it as the default for new panels.
- Reference app for menu bar UX: CodexBar (MIT) at /Applications/CodexBar.app, source github.com/steipete/CodexBar. Check it before inventing a pattern.
- Network features live in the menu bar panel (tabs). App settings (permissions, login item, theme) live in a Settings window (⌘,), plus a first-launch onboarding window. Panel footer = Settings… + Quit only.
- Public plugin repos get clean snapshots via tools/publish-public.sh; dev history (with author email) stays in private <name>-dev.
- Never commit real network data (IPs, MACs, SSIDs, VPN names) in fixtures; use documentation ranges.
- App settings (Open at Login, toggles, theme) never go in the menu bar panel, even when there is only one. Always a separate Settings window opened by `Settings…` (⌘,) in the panel footer. (mac-calendar, 2026-09-29)
- Shell `rm`/`mv` are aliased to interactive (`-i`) and hang a tool call waiting for input. Use `/bin/rm -f` and `/bin/mv -f` in scripts. (2026-09-30, hit twice)
- A full window needs its own DesignPass with rendered previews before it ships. The first Summon Activity window (tile grid of status cards, segmented filter, opened behind other apps) was judged "looks like shit" on the Mac. Read `MacUX/Windows.md` and `ActivityFeeds.md` first. (2026-10-18)

## 2026-10-18 — Summon GUI: user wants less, not more
- Menu bar panel shows only actions + problems when present. Lists of themes, recent activity, or repeated crash rows are
  "too much data". Collapse repeats (one row per program + count). Settings: one control per row, no explanatory text.

## 2026-10-19 — Merged a PR whose CI had failed
- I chained `gh pr checks --watch …; gh pr merge` with `;`, so the merge ran even though `discover` failed (GitHub
  Actions billing: "job was not started because recent account payments have failed"). The owner's rule is merge only
  on clean CI. Rule: merge only after `gh pr checks <n>` exits 0 (`gh pr checks <n> && gh pr merge <n> …`), never with
  `;`. When CI cannot run, stop and tell the owner; do not substitute the local gate silently.
- 2026-10-19 update from the owner: GitHub Actions will not be paid for. The gate is `tools/local-ci.sh <pr>`, which
  posts a `local / swift (macOS)` status on the commit; merge with `tools/local-ci.sh <pr> && gh pr merge <pr> …`.

## 2026-11-10 — Health totals must match real repair work
- A total that agrees across views can still be wrong: trace each counted item and the action behind the total.
  My Apps counted theme recommendations and looked for kebab-case bundles while templates build PascalCase apps;
  its Fix action also ran unrelated Mac diagnostics. Share the inventory summary and exact prompt scope.
- Keep numerical readability findings and palette advice visible without treating optional artwork as broken code.
  Do not rewrite established preset palettes merely to satisfy a hue heuristic.

## 2026-11-10 — Upgrade and verify the installed app
- Upgrade Summon in place on the owner's device and test that installed copy. Do not launch temporary app copies,
  use different accounts, or open Terminal windows for verification. Keep the work focused on the installed app.

## 2026-11-11 — Documentation needs a designed experience
- A functioning wiki with stock theme chrome and table-only landing pages is not the finished UX. Give SummonOS
  docs a recognizable identity, clear starting paths and polished reading surfaces; verify desktop/mobile visually.
