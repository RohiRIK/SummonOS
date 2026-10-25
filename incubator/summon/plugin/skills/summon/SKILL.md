---
name: summon
description: >
  The entry point for Summon. REQUIRED whenever the user says "summon" ("summon, build a web app",
  "/summon fix my Dock", "summon a wallpaper") or you were started with `summon agent`. Routes the request to the
  right skill: Mac settings and configs, themes and art, building apps, crashes, logs, or any other installed skill.
  Triggers: summon, "summon <anything>", make my Mac, fix my Mac, what can Summon do.
---

# Summon: the router

You were summoned. Read the request, pick **one** route below, say it in one line ("Routing to mac-app: a
menu bar app"), then load that skill and follow it. A request with two jobs ("new theme and an icon for it")
gets one route per job, in order.

## Routes

| The request is about | Route to |
|---|---|
| Mac settings, Dock, Finder, keyboard, dark mode, menu bar, AeroSpace, Ghostty, kitty, borders, keybindings, hooks, login items, Brewfile, installing apps, "fix my Mac" | `summon-mac` |
| A theme, palette, colors, a wallpaper, icon art, any generated image, "make it nice" | `summon-art` (it hands installing back to `summon-mac`) |
| Building a native Mac app: menu bar app, window app, command-line tool, screensaver, packaging an icon | `mac-app` |
| Migrating or importing an existing app into Summon, porting legacy macos-plugins | `summon-migrate` |
| An app crashed, hung, quit unexpectedly, the Mac restarted, a `.ips` report | `diagnose-crash-mac` |
| Logs, why something fails or keeps restarting, Wi-Fi/Bluetooth/sleep trouble | `mac-logs` |
| Doing something on a schedule: "every morning…", "each Friday", "every 2 hours" | `summon-mac` (recurring tasks) |
| Anything else: a web app, a script, a document, a data job | The best match among your other installed skills (below); none fits → do it directly |

Skill files, for harnesses without a skill mechanism: `summon skills` prints every path. Read the file and follow it.

## Anything else

Look at the skills you have (your harness lists them; on disk: `~/.agents/skills`, `~/.claude/skills`,
`~/.codex/skills`, `~/.gemini/config/skills`, `~/.pi/agent/skills`). Use the one whose description matches best
(for a web app: a frontend or web skill). If none fits, say so in one line and do the task with the project's
own conventions. Everything you make goes in `~/Summon` unless the user names a place: projects in
`~/Summon/Apps/<name>`, art in `~/Summon/Art/<job>`. Native Mac apps, CLI tools and screensavers always start with
`summon project new <name> --kind <kind>` (see `mac-app`), which also registers them. Other projects (a web app, a
script) get their own folder in `~/Summon/Apps/<name>` with `git init`, and are not registered: `summon project`
only knows the native kinds, so tell the user the folder instead.

## Always

- Changes to this Mac follow `summon-mac`'s rules even when another skill is driving: settings through
  `macctl`, edit `~/.config` copies, stay inside the session checkpoint, ask before anything outside it.
- Unclear request: ask one question, then route. Never ask which skill to use; that is your job.
- End with what you did, where it is, and how to undo it: `summon checkpoint undo <id>` with the id from the
  `## Summon session` block at the end of your prompt (`summon undo-session` undoes the latest).
- That block also says whether your tool calls are approved for you and whether anyone is watching (a scheduled
  task: never ask, never wait). `summon-mac` explains each line.
- Discover the rest yourself: `summon commands --json` lists every Summon command.
