# Changelog

All notable changes to Summon. Newest first. Summon is still incubating in `macos-plugins`, so there are no
version numbers yet; entries are grouped by day and point at the pull request.

## 2026-10-19

### Added
- **Keeping ~/Summon tidy.** Once a day (and with Settings › General › Clean Now…, or `summon clean --apply`) old
  Summon files go to the macOS Trash: task logs beyond the newest 20 or older than 30 days, a removed task's folder
  after 7 days, art jobs untouched for 30 days, Antigravity originals after 14. Apps are never touched; unknown apps,
  themes without a wallpaper and broken theme files are reported. `summon clean` alone previews.
- `summon theme check <slug>` says why a theme does not appear in `theme list`.
- **Plugins in Settings › Agents.** Each agent's installed plugins (Codex: its MCP servers) and Add, which runs the
  agent's own installer (OpenCode: added to `opencode.json`, backup kept). **Shared plugins**: Summon's catalog,
  starting with OpenLTM, installs the right build into every agent (Install in All) and hands a broken one to your
  agent (Fix…). CLI: `summon agents plugins|plugin-add`, `summon plugins [install|fix]`.
- **Recent Problems archive themselves.** The panel shows a report for 24 hours; Diagnose… archives that app's
  reports; Clear archives the rest. Activity keeps the full history.
- **Settings › Agents knows each agent's account and models.** It asks the agent's own CLI: logged in or not (with
  Log In…, which opens that agent's login in a terminal), and the real model list as suggestions in the Model field
  (Antigravity 13, Pi ~470; Claude Code's aliases). Each skill shows its description. CLI: `summon agents status
  <agent> [--json]`, `summon agents login <agent>`, `summon skills list --json`.
- **Tasks by conversation.** `summon task new "<what you want>"` (or Agent › Schedule a Task…, or "summon, every
  morning…" in a chat) opens the agent, which asks what is unclear, writes the run prompt and adds the task.
- Local CI: `tools/local-ci.sh <pr>` builds and tests every package on the Mac and posts the result on the commit.
- `summon doctor` checks recurring tasks: each needs its LaunchAgent and an agent that can run unattended (from #40).
- **Recurring agent tasks.** `summon task add "<prompt>" --at 09:00 [--weekdays]` or `--every 2h`, with
  `list`, `run` and `remove`, plus a Tasks tab in Settings. Each task is a LaunchAgent that runs the agent
  unattended after a checkpoint, logs every run, and reports in Activity and a notification. (#41)
- `summon://settings` opens the Settings window. (#35)

### Changed
- **`~/Summon` is the one home for everything Summon and its agents make**: `Apps/` (apps from the templates),
  `Art/` (wallpaper and icon jobs, every candidate), `Tasks/` (recurring task results), and `Themes` (a link to
  `~/.config/summon/themes`). A `.gitignore` keeps the generated parts out of git. `summon home` (also run at
  install and on every launch) sets it up and moved older files in: art from `~/Downloads/summon-art` and
  `~/Downloads/summon-wallpapers`, task logs from `~/.local/state/summon/tasks`, apps from `~/Summon/<name>`.
  The art skill now generates into `~/Summon/Art/<job>/`.
- **Settings › Agents redesigned** (after Hermes's settings, lean): the agents on the left with a status dot and
  Default, **All Agents** on top (default agent, where agents open, the skills every agent gets, shared plugins),
  and the same sections for every agent: Account, Model (picked from that agent's list, or Custom…), Skills
  ("Same as All Agents" or Custom, with Use All Agents), Plugins (installed, OpenLTM as a recommended Install /
  Fix…, Add). The Terminal tab moved into All Agents. CLI: `summon agents defaults [--skills a,b | --all-skills]`.
- Settings uses toolbar tabs (General, Agents, Terminal, Notifications, Appearance, Tasks) instead of a
  sidebar. Short tabs fit their rows; the `summon` router skill cannot be switched off for an agent. (#35)
- Settings › Tasks is view only (schedule, agent, last result); tasks are made by describing them to the agent.

### Fixed
- Low-memory (Jetsam, bug_type 298) reports showed as a "Hang" named after the file (hangs are bug_type 288). They
  now name the process macOS stopped and why ("knowledgeconstructiond · Stopped · over its own memory limit"), not
  the biggest bystander; routine kills (over its own cap, idle) are listed but not announced.
- Clicking a Recent Problems row runs Diagnose, like its button.
- Summon found an old Homebrew OpenCode (1.15) before your bun one (2.0); your own folders now come first, as in
  your shell.
- Ask Agent with Pi (or any `#!/usr/bin/env node` agent) failed in Ghostty with `env: node: No such file or
  directory`: Ghostty starts commands with a bare PATH. Agents now run through your login shell
  (`zsh -lic 'exec "$@"' …`), so they get the PATH your terminal has; `~/.bun/bin` is searched too.
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

- Where it started: **mac-assistant** (2026-10-03), a diagnostics assistant with a policy broker and typed tools.
  Archived at the tag `archive/mac-assistant`.

- The `summon` CLI and the Summon Menu app (#13), the Activity event log, timeline and window (#22, #23),
  Claude Code plugin session hooks (#24), themes, wallpapers, the logo and desktop configs (#12), and theme
  wallpapers through `macctl` so undo restores them (#18).
