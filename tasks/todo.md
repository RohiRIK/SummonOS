# Current plan

The active plan goes here. When a plan is done, move it to `docs/plans/YYYY-MM-DD-<name>.md`
and leave this file with only what is still in progress.

# Plan: Summon — Kitty, muted apps, art-directed wallpapers (2026-10-18)

Branch `feat/summon-kitty-mute-wallpapers`. User OK'd items 1 and 3 plus the wallpaper skill; promote (4) needs a separate OK.

- [x] Kitty: `TerminalApp.kitty` (open -na kitty --single-instance: one window, one process), `defaults/terminal`
      + `summon default terminal <name>`, Settings "Terminal" picker (installed only), Install › Kitty menu entry. Tests first.
- [x] Muted apps: Settings › Notifications lists muted programs with Unmute, only when non-empty.
- [x] Wallpapers: `plugin/skills/summon/Wallpapers.md` with Art-skill direction (concept from mood, palette from theme,
      composition for a desktop, Nano Banana via agy, candidates → preview → pick → 5120×2880 into theme). Link from SKILL.md.
- [x] Verify: check.sh, real app screenshots, one real wallpaper generation through the documented path.
- [x] PR, merge on green CI.

## Review
- All gates green (55 tests). Settings, muted list, Unmute verified in the real app; two real wallpaper candidates generated
  in ~/Downloads/summon-wallpapers/catppuccin/ (the second has a film-frame border: the review step's job).
- Not verified: kitty launch (kitty not installed), Ghostty cold start.
