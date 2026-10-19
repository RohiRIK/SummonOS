# Changelog

All notable changes to Summon. Newest first. Summon is still incubating in `macos-plugins`, so there are no
version numbers yet; entries are grouped by day and point at the pull request.

## 2026-10-19

### Added
- **Tasks by conversation.** `summon task new "<what you want>"` (or Agent › Schedule a Task…, or "summon, every
  morning…" in a chat) opens the agent, which asks what is unclear, writes the run prompt and adds the task.
- Local CI: `tools/local-ci.sh <pr>` builds and tests every package on the Mac and posts the result on the commit.
- `summon doctor` checks recurring tasks: each needs its LaunchAgent and an agent that can run unattended (from #40).
- **Recurring agent tasks.** `summon task add "<prompt>" --at 09:00 [--weekdays]` or `--every 2h`, with
  `list`, `run` and `remove`, plus a Tasks tab in Settings. Each task is a LaunchAgent that runs the agent
  unattended after a checkpoint, logs every run, and reports in Activity and a notification. (#41)
- `summon://settings` opens the Settings window. (#35)

### Changed
- Settings uses toolbar tabs (General, Agents, Terminal, Notifications, Appearance, Tasks) instead of a
  sidebar. Short tabs fit their rows; the `summon` router skill cannot be switched off for an agent. (#35)
- Settings › Tasks is view only (schedule, agent, last result); tasks are made by describing them to the agent.

### Fixed
- `summon project repo`: the private-repo approval dialog closed itself after ~2 s; it now stays open until answered. (#43)
- `summon://activity` (and the new `summon://settings`) never opened anything: the opener sat on the menu
  bar icon, which macOS draws as an image. It now lives in an invisible window. (#35)

## 2026-10-18

### Added
- **`summon` router skill.** Say "summon, build a web app" to any agent: the skill picks the right one of
  `summon-mac`, `summon-art`, `mac-app`, `diagnose-crash-mac`, `mac-logs`, or the agent's own skills. (#32)
- **Per-agent model and skills.** `summon agents set <agent> --model … --skills …`, saved in
  `~/.config/summon/agents.json`, and editable in Settings › Agents. (#33)
- **Skills in every agent.** `summon skills link` links Summon's skills into each agent's own folder
  (Claude Code, Codex, OpenCode, Antigravity, Pi); it runs on install and on every app launch. Prompts
  also carry the skill file paths for agents without a skill mechanism. (#29)
- **`summon-art` skill:** themes, wallpapers and icons that are art-directed (mood, three concepts, a palette
  with a contrast check, Nano Banana images, review before you see them). (#30)
- **Pi** as an agent. (#31)
- **kitty** as a terminal (`summon default terminal`, Settings › Terminal, Install › kitty, `kitty.conf` from
  every theme); muted apps with Unmute in Settings. (#27)
- Activity window as a simple log: one line per event, oldest first; select lines and ask the agent about
  them; right-click to copy, diagnose or undo. (#28)
- `summon doctor`: checks the install, config, agents, skills, macctl and project templates. (#36, #39)
- Projects from templates in `~/Summon` (menu bar app, window app, CLI tool, screensaver). (#37)

### Changed
- Agents launch with permission prompts bypassed (Claude Code `--dangerously-skip-permissions`, Codex
  `--dangerously-bypass-approvals-and-sandbox`), always behind a checkpoint. (#26)
- Leaner menu bar panel (actions, and problems only when there are some) and a short Settings window. (#26)
- The previous `summon` skill (Mac customization) is now `summon-mac`. (#32)

### Fixed
- One agent launch opened a second Ghostty app; it now opens one new window in the running Ghostty. (#26)
- The crash prompt pointed agents at a skill file that did not exist. (#29)

## 2026-10-17 and earlier

- The `summon` CLI and the Summon Menu app (#13), the Activity event log, timeline and window (#22, #23),
  Claude Code plugin session hooks (#24), themes, wallpapers, the logo and desktop configs (#12), and theme
  wallpapers through `macctl` so undo restores them (#18).
