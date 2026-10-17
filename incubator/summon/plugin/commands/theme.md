---
description: Switch, list, or create a Summon theme
argument-hint: [theme name | "new" <mood, colors, or image path>]
---

Theme request: $ARGUMENTS

- No argument: run `summon theme list` and show the themes with the current one marked.
- A theme name: `summon theme set <slug>`, then say what changed (appearance, accent, wallpaper, terminal, borders, agents).
- `new …`: follow the `summon` skill, "Making a new theme": derive a palette (from the description, or sample
  the image), check contrast, write `~/.config/summon/themes/<slug>/theme.json`, generate a 5120×2880 wallpaper
  in the same style as Summon's (`design/generate.py` in the Summon repo shows how), then `summon theme set <slug>`.
