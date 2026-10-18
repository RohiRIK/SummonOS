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
| Building a native Mac app: menu bar app, window app, screensaver, packaging an icon | `mac-app` |
| An app crashed, hung, quit unexpectedly, the Mac restarted, a `.ips` report | `diagnose-crash-mac` |
| Logs, why something fails or keeps restarting, Wi-Fi/Bluetooth/sleep trouble | `mac-logs` |
| Anything else: a web app, a script, a document, a data job | The best match among your other installed skills (below); none fits → do it directly |

Skill files, for harnesses without a skill mechanism: `summon skills` prints every path. Read the file and follow it.

## Anything else

Look at the skills you have (your harness lists them; on disk: `~/.agents/skills`, `~/.claude/skills`,
`~/.codex/skills`, `~/.gemini/config/skills`, `~/.pi/agent/skills`). Use the one whose description matches best
(for a web app: a frontend or web skill). If none fits, say so in one line and do the task with the project's
own conventions. New projects go in `~/Work/<name>` unless the user names a place.

## Always

- Changes to this Mac follow `summon-mac`'s rules even when another skill is driving: settings through
  `macctl`, edit `~/.config` copies, stay inside the session checkpoint, ask before anything outside it.
- Unclear request: ask one question, then route. Never ask which skill to use; that is your job.
- End with what you did, where it is, and how to undo it (`summon checkpoint undo`).
- Discover the rest yourself: `summon commands --json` lists every Summon command.
