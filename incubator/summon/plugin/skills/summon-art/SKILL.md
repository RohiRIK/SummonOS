---
name: summon-art
description: >
  REQUIRED for any visual work on this Mac with Summon: a new or changed theme (palette, terminal colors), a
  wallpaper, an app or folder icon, or any generated image. Art-directed, not default gradients: a concept from the
  user's mood, a palette built from the subject, images generated with Nano Banana over agy, reviewed before the
  user sees them. Triggers: new theme, make it nice, prettier, wallpaper, background, palette, colors, icon art,
  generate an image, "make my Mac look good".
---

# Summon art: themes, wallpapers, icons that look made on purpose

"Make it nice" means a decision, not a default. Every visual job follows the same five steps:
**brief → concepts → palette → generate → review**, then install with Summon's own tools.

Topic guides next to this file; read the matching one before starting:

- [`wallpapers.md`](wallpapers.md): desktop composition, prompt template, generate, review, install.
- [`icons.md`](icons.md): app, folder and file icons that sit well in the Dock and Finder.

A whole new theme = this file's palette method, then `wallpapers.md`, then the `summon-mac` skill's
"Making a new theme" steps (`summon theme set <slug>`).

## 1. Brief

Ask for a **mood** in a few words if the user gave none ("quiet winter morning", "neon rain"). An image they
like counts: use it as a reference. Then name the subject's **world** (a material, a place, a time of day)
before choosing any color. A hue chosen from the subject is defensible; a hue chosen from habit is a default.
Banned defaults: purple-blue nebula, blob gradients, generic "abstract tech" swirls, cream + terracotta.

## 2. Concepts

Offer **three different directions**, not three variations: a **place** (landscape or interior seen from far),
a **material** (a close tactile surface), an **abstract** (shape and light). The user picks; change one thing
per round after that (light, palette, or subject), never everything.

## 3. Palette (theme.json)

Work in OKLCH (`oklch(L C H)`): perceptually even, so a lightness ladder looks even. Base hue H from the subject
(clay ≈ 40°, wheat ≈ 90°, moss ≈ 140°, sea ≈ 200°, steel ≈ 240°).

| Field | Dark theme | Light theme |
|---|---|---|
| `background` | H at whisper chroma (C 0.01-0.03), L 0.16-0.22 | C 0.005-0.02, L 0.96-0.98 |
| `foreground` | L 0.85-0.92, ≥ 7:1 on background | L 0.24-0.30, ≥ 7:1 |
| `muted`, `selection`, `border_inactive` | visible, about 1.5-2:1; never body text | same |
| `accent` (+ `border_active`) | H at C 0.10-0.15, L 0.65-0.72, ≥ 3:1 on background | L 0.35-0.42, ≥ 3:1 |
| `accent2` | analogous (H ± 30-40°) for calm, near-complement (H + 150-180°) for tension | same |
| `cursor` | foreground or accent | same |

`terminal` (16 colors, ANSI order): 0 = background lifted a step, 8 = muted; then the real colors, each tinted a
little toward the base hue but still itself: 1/9 red (H ≈ 25°), 2/10 green (≈ 145°), 3/11 yellow (≈ 90°), 4/12 blue
(≈ 255°), 5/13 magenta (≈ 330°), 6/14 cyan (≈ 200°), 7/15 foreground dimmed / foreground. Every one of 1-7 and 9-15
≥ 4.5:1 on the background. **Sixteen shades of one hue is not a terminal palette.**

### The file

Write `~/.config/summon/themes/<slug>/theme.json` as **plain JSON (no comments, no trailing commas)**, with every
field. Colors may be `#RRGGBB` or `oklch(L C H)` (Summon converts OKLCH to hex for every app):

```json
{
  "name": "Hearts Valley", "slug": "hearts-valley", "appearance": "dark", "font": "JetBrainsMono Nerd Font",
  "colors": {
    "background": "oklch(0.18 0.02 240)", "foreground": "oklch(0.90 0.02 240)",
    "accent": "oklch(0.70 0.12 240)", "accent2": "oklch(0.72 0.12 10)",
    "muted": "oklch(0.45 0.03 240)", "selection": "oklch(0.30 0.04 240)", "cursor": "oklch(0.90 0.02 240)",
    "border_active": "oklch(0.70 0.12 240)", "border_inactive": "oklch(0.30 0.04 240)"
  },
  "terminal": ["oklch(0.24 0.02 240)", "oklch(0.70 0.14 25)", "…16 in all…"],
  "wallpapers": ["1-place.jpg"]
}
```

Then **`summon theme check <slug>`**: it reads the file the way Summon will, and checks contrast and that red is red.
Fix every `error:` line and as many `warning:` lines as the design allows, until it prints "valid". `summon theme
list` silently skips a theme that does not pass, so never stop before this check is clean.

## 4. Generate (Nano Banana over agy, no API key)

The generation recipe (agy prompt, waiting, and recovering the file from agy's scratch folder) is in
`wallpapers.md` § 5 and is the same for icons. Generate into `~/Summon/Art/<job>/` (Summon's one home), never straight
into a theme or an app. If agy is missing or signed out (`You are not logged into Antigravity` in
`~/.gemini/antigravity-cli/log/`), say so and ask the user to run `agy` once to sign in; do not ship a weak fallback
silently. The user's own `Art` skill, when installed, has more workflows (diagrams, editorial images); this skill
is the Summon subset and works without it.

## 5. Review before showing

Look at every image yourself and regenerate any with: invented text or glyphs, a watermark, a frame or
film-gate border, warped geometry, seams, banding, or colors drifted from the palette. Show the survivors side by
side (`open <folder>` or `qlmanage -p <files>`), let the user pick, then install with the guide's last step.
Report what you made, where the other candidates are, and how to undo (`summon checkpoint undo`).
