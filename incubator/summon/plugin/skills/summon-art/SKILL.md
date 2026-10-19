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

`terminal` (16 colors, ANSI order): 0 = background lifted a step, 8 = muted; 1 red, 2 green, 3 yellow, 4 blue,
5 magenta, 6 cyan, 7 foreground dimmed; 9-15 the brighter twins. Keep each hue recognisable (red stays red)
but pull it toward the base hue a little so the set feels related. Every one of 1-7 and 9-15 ≥ 4.5:1 on background.

Check contrast before installing (WCAG ratio; prints anything below its target):

```bash
python3 - <<'PY' ~/.config/summon/themes/<slug>/theme.json
import json, sys
t = json.load(open(sys.argv[1])); c = t["colors"]
def lum(h):
    r, g, b = (int(h.lstrip("#")[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda v: v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)
def ratio(a, b):
    x, y = sorted((lum(a), lum(b)), reverse=True); return (x + 0.05) / (y + 0.05)
bg = c["background"]
checks = [("foreground", c["foreground"], 7), ("accent", c["accent"], 3), ("border_active", c["border_active"], 3)]
checks += [(f"terminal[{i}]", h, 4.5) for i, h in enumerate(t["terminal"]) if i not in (0, 8)]
for name, h, need in checks:
    r = ratio(h, bg)
    print(("ok  " if r >= need else "LOW ") + f"{name} {h} {r:.1f}:1 (need {need})")
PY
```

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
