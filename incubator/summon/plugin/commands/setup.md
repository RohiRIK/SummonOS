---
description: Set this Mac up the Summon way (settings, apps, tiling, theme)
argument-hint: [profile.json]
---

Set up this Mac with Summon. Profile: ${ARGUMENTS:-the default Summon profile}

1. `macctl doctor` and `summon commands --json` to see what is available; report missing permissions with their links.
2. `macctl diff <profile>` and show the user the changes; then `macctl apply <profile>`.
3. Apps: `brew bundle --file "$(summon path)/config/Brewfile"` (AeroSpace, Ghostty, JankyBorders, the font).
4. Configs: copy `config/aerospace`, `config/ghostty`, `config/borders`, `config/shell` from the Summon install into
   `~/.config` where the user has none yet (back up any existing file to `<file>.before-summon`).
5. `summon theme set summon-night`, then `summon default agent claude` if no agent is set.
6. Report what changed and how to undo each part.
