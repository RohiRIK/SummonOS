# Icons: art for apps, folders and files

The art side of an icon. Building and packaging (`.iconset`, `iconutil`, Icon Composer, placing icons with
`NSWorkspace.setIcon`) is in the `mac-app` skill (step 7 and "Icons on other things"); do that after the user picks a design.

## Direction

- One idea per icon, readable at 16 pt: a single object or symbol, no scenes, no text or letters.
- macOS shape: content inside the 824×824 rounded square of a 1024×1024 canvas (Apple's grid), a soft top-down
  light, a gentle shadow inside the shape. Folder icons: the subject as a small emblem on the folder, not a new folder.
- Palette from the current theme (`~/.config/summon/themes/$(summon theme current)/theme.json`): background tone
  for the base, the theme accent on the subject, nothing else loud.
- Family feel: Summon's own mark lives in `$(summon path)/assets` (mark, app icon); match its corner radius,
  depth and light when making icons for Summon-made apps.

## Prompt template

```
A macOS app icon, 1:1, centered on a transparent or plain <background #hex> canvas. <one object or symbol,
in one concrete sentence>. Style: <soft 3D / flat glyph / glass>, soft top light, subtle inner shadow, the
shape inside a rounded square with Apple's continuous corners and generous margin. Palette: base <#hex>,
subject in <accent name> <#hex>. No text, no letters, no watermark, no frame, no background scene.
```

Generate three concepts with the recipe in `wallpapers.md` § 5 (aspect ratio 1:1 instead of 16:9) into
`~/Summon/Art/icon-<name>/`. Review at small size too: `sips -Z 32 <file> --out /tmp/icon-32.png`
and look at it; an icon that only works at 1024 is not done.
