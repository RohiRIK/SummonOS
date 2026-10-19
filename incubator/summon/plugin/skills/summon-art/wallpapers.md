# Wallpapers: making one that is actually nice

Part of the `summon-art` skill. Read this before making or changing a wallpaper, alone or as part of a new theme. "Make it nice" means
art-directed, not a gradient: a real concept, a palette taken from the theme, a composition that works
behind a menu bar, a Dock and windows. Distilled from the Art skill's generation pipeline and color method.

## 1. Brief (ask, then decide)

- Ask for a **mood** in a few words if the user did not give one ("quiet winter morning", "neon rain").
  An image they like counts as a mood: use it as a reference.
- Read the theme: `~/.config/summon/themes/<slug>/theme.json` (`appearance`, `colors`, `terminal`).
- Turn the mood into **three different concepts**, one per direction, so the user picks between real options:
  1. **Place**: a landscape or interior seen from far away (fjord at dusk, desert observatory, greenhouse at night).
  2. **Material**: a close, tactile surface (folded paper, brushed metal, ink in water, frosted glass, moss).
  3. **Abstract**: shape and light (long-exposure light trails, layered paper cut, slow wave interference).
- Name the subject's world first, then its colors. A hue chosen from the subject is defensible; a hue chosen
  from habit is a default. **No default purple nebula, no blob gradient, no generic "abstract tech" swirl.**

## 2. Palette from the theme (a new theme: build it first with `SKILL.md` § 3)

- The theme `background` is the dominant color (about 60% of the image). Windows sit on top of it, and terminals
  run at partial opacity, so the wallpaper must not fight them.
- One theme accent (`accent` or a bright `terminal` color) as the signature: about 5% of the area, not more.
- Dark theme: keep the whole image dark and low contrast (deep shadows, highlights only on the focal point).
  Light theme: bright and soft, no near-black masses.
- Put the hex values in the prompt ("dominant deep navy #0B0D17, a single ember-orange accent #F59E0B").

## 3. Composition for a desktop (16:9, 5120×2880)

- **Top 4% (menu bar):** calm and even in brightness, so menu bar text stays readable. No horizon line or bright
  object right under it.
- **Bottom 10% (Dock)** and **right edge (desktop icons):** quiet, low detail.
- Focal point off-center (left third, or low center), with generous negative space around it.
- Never: text, letters, numbers, logos, watermarks, signatures, UI, frames or borders, people's faces (unless
  asked), hands. Image models invent fake text, so say "no text" explicitly.

## 4. Prompt template

```
A wide 16:9 desktop wallpaper. <concept: subject, place or material, in one concrete sentence>.
Mood: <mood words>. Style: <photographic / cinematic matte painting / paper-cut / macro photography>,
<light: soft volumetric dusk light / rim light / overcast>. Palette: dominant <background name> <#hex>,
secondary <#hex> <#hex>, a single small <accent name> <#hex> accent on the focal point.
Composition: focal point in the <left third / lower center>, large calm negative space, the top edge
even and uncluttered, the bottom and right edges quiet. No text, no letters, no logos, no watermark,
no frame, no people. High detail, clean, no artifacts.
```

## 5. Generate (Nano Banana over agy, no API key)

Generate every candidate into a preview folder first, never straight into the theme:

```bash
OUT=~/Summon/Art/wallpaper-<slug>; mkdir -p "$OUT"   # everything Summon makes lives in ~/Summon
FILE="$OUT/1-<concept>.jpg"; START=$(mktemp)
NANOBANANA_MODEL=gemini-3-pro-image-preview timeout 300 agy --add-dir "$OUT" -p \
  "Generate an image. <prompt> Aspect ratio 16:9. Save the result to the exact absolute path \"$FILE\" (overwrite if it exists). Reply with only the saved file path."
# agy often answers "saving shortly" and its image subagent writes into its own scratch folder instead.
# Wait up to 3 minutes, then take the newest image it wrote after START.
for _ in $(seq 36); do
  [ -s "$FILE" ] && break
  NEW=$(find ~/.gemini/antigravity-cli/brain -type f \( -name '*.jpg' -o -name '*.png' \) -newer "$START" 2>/dev/null | head -1)
  [ -n "$NEW" ] && cp "$NEW" "$FILE" && break
  sleep 5
done
```

- One file per concept (`1-place.jpg`, `2-material.jpg`, `3-abstract.jpg`). Nano Banana returns JPEG bytes, so
  name the files `.jpg`. Generate one at a time: the scratch-folder fallback cannot tell parallel runs apart.
- Nano Banana over agy returns about 1376×768. Scaled to 5120×2880 it is soft, which suits misty, painterly and
  photographic-bokeh concepts; avoid concepts that need crisp fine line work (circuitry, text-like patterns).
- Check `agy --version` first. If agy is missing or not signed in, say so and offer the procedural fallback
  (`design/generate.py` styles: portal, aurora, sigil) instead of shipping something weak.

## 6. Review before showing

Look at every image yourself (open or read it) and regenerate any that fail:

- Invented text or glyphs anywhere, a watermark, warped geometry, extra limbs, seams, banding.
- A frame: macro and "photograph" prompts often come back with a rounded black film-gate border or heavy
  vignette. Check all four edges and corners; regenerate rather than crop (cropping breaks 16:9).
- A bright or busy band under the menu bar, or clutter where the Dock and desktop icons sit.
- Colors drifted away from the theme (compare with the hex values), or more than one loud accent.

Then show the three with `open "$OUT"` (or Quick Look: `qlmanage -p "$OUT"/*.jpg`) and let the user pick.
Two rounds of "closer, but…" is normal: change one thing per round (light, palette, or subject), not everything.

## 7. Install the chosen one

```bash
THEME=~/.config/summon/themes/<slug>
sips -z 2880 5120 "$OUT/<chosen>.jpg" --out "$THEME/<n>-<concept>.jpg"   # 5120×2880; crop first if not 16:9
```

Add the file name to the theme's `wallpapers` list (first entry is the one `theme set` applies), then
`summon theme set <slug>`. The wallpaper change goes through `macctl`, so it is in the checkpoint and undoable.
Tell the user where the other candidates are (`~/Summon/Art/wallpaper-<slug>/`) in case they change their mind.
