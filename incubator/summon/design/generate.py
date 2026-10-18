#!/usr/bin/env python3
"""Generate Summon's brand and theme assets: logo, app icon, menu bar icon, themes, wallpapers.

Run from anywhere:  python3 incubator/summon/design/generate.py [--quick]
Needs Python 3.11+, Pillow and numpy. Outputs are committed, so this only reruns after a design change.
--quick renders wallpapers at 1/4 size for fast iteration.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from brandkit import PORTS, SUMMON, mark_svg, mix, rgb  # shared with tools/readme-art.py

ROOT = Path(__file__).resolve().parent.parent  # incubator/summon
QUICK = "--quick" in sys.argv
# --quick renders into design/.quick/ (gitignored) so it never replaces the committed full-size files.
OUT = ROOT / "design" / ".quick" if QUICK else ROOT
BRAND = OUT / "design" / "brand" if QUICK else ROOT / "design" / "brand"
THEMES = OUT / "themes"
WALL_W, WALL_H = (1280, 720) if QUICK else (5120, 2880)
FONT_BOLD = "/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf"
FONT_MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


# Wallpaper styles per theme: Summon's own themes get all three, ports get one.
STYLES = {"summon-night": ["portal", "aurora", "sigil"], "summon-dawn": ["portal", "aurora"]}
DEFAULT_STYLES = ["portal"]


# ---------------------------------------------------------------- helpers

def vertical_gradient(w: int, h: int, top, bottom) -> Image.Image:
    t = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t
    arr = np.repeat(arr, w, axis=1)
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def radial_glow(w: int, h: int, cx: float, cy: float, radius: float, color, strength: float) -> Image.Image:
    """RGBA layer: color fading out smoothly from (cx, cy)."""
    ys = (np.arange(h, dtype=np.float32) + 0.5 - cy)[:, None]
    xs = (np.arange(w, dtype=np.float32) + 0.5 - cx)[None, :]
    d = np.sqrt(xs * xs + ys * ys) / radius
    a = np.clip(1 - d, 0, 1)
    a = a * a * (3 - 2 * a) * strength  # smoothstep: no visible edge where the glow ends
    arr = np.empty((h, w, 4), np.uint8)
    arr[..., :3] = color
    arr[..., 3] = (a * 255).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def dither(img: Image.Image, amount: float = 2.2, seed: int = 7) -> Image.Image:
    """Fine noise so big gradients do not band on wide-gamut displays."""
    arr = np.asarray(img.convert("RGB")).astype(np.float32)
    noise = np.random.default_rng(seed).normal(0, amount, arr.shape[:2])[..., None]
    return Image.fromarray(np.clip(arr + noise, 0, 255).astype(np.uint8), "RGB")


def soft(img: Image.Image, radius: float) -> Image.Image:
    return img.filter(ImageFilter.GaussianBlur(radius))


# ---------------------------------------------------------------- the mark

def draw_mark(size: int, c1: str, c2: str, glyph: str, ring_alpha: int = 255) -> Image.Image:
    """The Summon mark: a summoning circle (two rings, six runes) around a terminal prompt `›_`.

    Drawn at 4x and downsampled, since PIL does not antialias shapes.
    """
    s = size * 4
    layer = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx = cy = s / 2
    R = s * 0.40

    # Gradient fill used for the rings and runes: c1 top-left → c2 bottom-right.
    ys, xs = np.mgrid[0:s, 0:s]
    t = np.clip((xs + ys) / (2 * s), 0, 1)[..., None]
    grad = (np.array(rgb(c1)) * (1 - t) + np.array(rgb(c2)) * t).astype(np.uint8)

    mask = Image.new("L", (s, s), 0)
    m = ImageDraw.Draw(mask)
    w_outer = max(4, int(s * 0.026))
    m.ellipse([cx - R, cy - R, cx + R, cy + R], outline=ring_alpha, width=w_outer)
    r2 = R * 0.86
    m.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=int(ring_alpha * 0.55), width=max(2, int(s * 0.009)))
    # Six runes sit on the outer ring: small diamonds, the top one larger (the "north" of the circle).
    for i in range(6):
        ang = -math.pi / 2 + i * math.pi / 3
        px, py = cx + R * math.cos(ang), cy + R * math.sin(ang)
        k = s * (0.05 if i == 0 else 0.032)
        m.polygon([(px, py - k), (px + k, py), (px, py + k), (px - k, py)], fill=ring_alpha)
    # Three arcs of an inner orbit, broken like a sigil.
    r3 = R * 0.70
    for start in (200, 320, 80):
        m.arc([cx - r3, cy - r3, cx + r3, cy + r3], start, start + 70, fill=int(ring_alpha * 0.8), width=max(2, int(s * 0.012)))

    ring = Image.fromarray(np.dstack([grad, np.asarray(mask)]), "RGBA")
    layer.alpha_composite(ring)

    # The prompt: a heavy chevron and an underscore, centered, in the glyph color.
    k = s * 0.13
    stroke = int(s * 0.055)
    gx, gy = cx - s * 0.075, cy - s * 0.005
    chev = [(gx - k * 0.55, gy - k), (gx + k * 0.55, gy), (gx - k * 0.55, gy + k)]
    d.line(chev, fill=glyph, width=stroke, joint="curve")
    for p in (chev[0], chev[2]):
        d.ellipse([p[0] - stroke / 2, p[1] - stroke / 2, p[0] + stroke / 2, p[1] + stroke / 2], fill=glyph)
    ux0, ux1, uy = gx + k * 0.95, gx + k * 2.05, gy + k * 0.92
    d.rounded_rectangle([ux0, uy - stroke / 2, ux1, uy + stroke / 2], radius=stroke / 2, fill=glyph)

    return layer.resize((size, size), Image.LANCZOS)


def with_glow(mark: Image.Image, color: str, radius: float, strength: float = 1.0) -> Image.Image:
    glow = Image.new("RGBA", mark.size, rgb(color) + (0,))
    alpha = soft(mark.getchannel("A"), radius).point(lambda v: min(255, int(v * strength)))
    glow.putalpha(alpha)
    out = Image.new("RGBA", mark.size, (0, 0, 0, 0))
    out.alpha_composite(glow)
    out.alpha_composite(mark)
    return out


def squircle_mask(size: int) -> Image.Image:
    """macOS app icon shape: a superellipse (n≈5) inset to the 824/1024 icon grid."""
    s = size * 4
    inset = s * (100 / 1024)
    half = (s - 2 * inset) / 2
    ys, xs = np.mgrid[0:s, 0:s]
    nx = np.abs((xs + 0.5 - s / 2) / half)
    ny = np.abs((ys + 0.5 - s / 2) / half)
    inside = (nx ** 5 + ny ** 5) <= 1
    return Image.fromarray((inside * 255).astype(np.uint8), "L").resize((size, size), Image.LANCZOS)


def app_icon(size: int = 1024) -> Image.Image:
    p = SUMMON["summon-night"]
    bg = vertical_gradient(size, size, mix(p["lighter_background"], p["accent"], 0.18), rgb(p["darker_background"])).convert("RGBA")
    bg.alpha_composite(radial_glow(size, size, size / 2, size * 0.48, size * 0.45, rgb(p["accent"]), 0.55))
    mark = with_glow(draw_mark(int(size * 0.74), p["accent"], p["accent2"], p["bright_foreground"]), p["accent"], size * 0.025, 1.4)
    off = (size - mark.width) // 2
    bg.alpha_composite(mark, (off, off))
    # Thin top highlight on the edge, like system icons.
    t = np.clip(1 - np.linspace(0, 1, size) / 0.55, 0, 1)[:, None] ** 1.5
    hl = np.zeros((size, size, 4), np.uint8)
    hl[..., :3] = 255
    hl[..., 3] = (np.repeat(t, size, axis=1) * 22).astype(np.uint8)
    bg.alpha_composite(Image.fromarray(hl, "RGBA"))
    out = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    out.paste(bg, (0, 0), squircle_mask(size))
    # Drop shadow inside the canvas, as Apple's template does.
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sh = squircle_mask(size).point(lambda v: int(v * 0.35))
    shadow.putalpha(soft(sh, size * 0.012))
    final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    final.alpha_composite(shadow, (0, int(size * 0.01)))
    final.alpha_composite(out)
    return final


def menubar_icon(px: int) -> Image.Image:
    """Template image for NSStatusItem: black on transparent; macOS tints it."""
    mark = draw_mark(px * 4, "#000000", "#000000", "#000000")
    return mark.resize((px, px), Image.LANCZOS)


def wordmark(height: int, p: dict) -> Image.Image:
    mark = with_glow(draw_mark(height, p["accent"], p["accent2"], p["bright_foreground"]), p["accent"], height * 0.03)
    font = ImageFont.truetype(FONT_BOLD, int(height * 0.48))
    text = "summon"
    tw = int(font.getlength(text))
    w = height + int(height * 0.18) + tw + int(height * 0.1)
    img = Image.new("RGBA", (w, height), (0, 0, 0, 0))
    img.alpha_composite(mark)
    d = ImageDraw.Draw(img)
    asc, desc = font.getmetrics()
    d.text((height + int(height * 0.18), (height - asc - desc) // 2 + int(height * 0.02)), text, font=font, fill=p["bright_foreground"])
    return img


# ---------------------------------------------------------------- wallpapers

def wallpaper(p: dict, style: str) -> Image.Image:
    w, h = WALL_W, WALL_H
    dark = p["mode"] == "dark"
    top = rgb(p["darker_background"]) if dark else rgb(p["lighter_background"])
    bottom = rgb(p["background"]) if dark else rgb(p["darker_background"])
    img = vertical_gradient(w, h, top, bottom).convert("RGBA")
    a1, a2 = rgb(p["accent"]), rgb(p["accent2"])
    k = 1.0 if dark else 0.55

    if style == "portal":
        cx, cy = w * 0.66, h * 0.52
        img.alpha_composite(radial_glow(w, h, cx, cy, h * 0.75, a1, 0.38 * k))
        img.alpha_composite(radial_glow(w, h, cx + h * 0.12, cy + h * 0.1, h * 0.45, a2, 0.22 * k))
        rings = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(rings)
        unit = h / 2880
        for i, r in enumerate(np.geomspace(h * 0.10, h * 1.25, 14)):
            alpha = int((110 if i % 3 == 0 else 55) * (1.0 if dark else 0.8))
            col = a1 if i % 2 == 0 else a2
            d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col + (alpha,), width=max(1, int((5 if i % 3 == 0 else 3) * unit)))
        # Runes on the main ring.
        R = float(np.geomspace(h * 0.10, h * 1.25, 14)[6])
        for i in range(6):
            ang = -math.pi / 2 + i * math.pi / 3
            px, py = cx + R * math.cos(ang), cy + R * math.sin(ang)
            q = h * (0.012 if i == 0 else 0.008)
            d.polygon([(px, py - q), (px + q, py), (px, py + q), (px - q, py)], fill=a1 + (150,))
        img.alpha_composite(soft(rings, 1.2 * unit + 0.4))
        mark = draw_mark(int(h * 0.22), p["accent"], p["accent2"], p["bright_foreground"] if dark else p["foreground"])
        mark = with_glow(mark, p["accent"], h * 0.006, 1.2)
        img.alpha_composite(mark, (int(cx - mark.width / 2), int(cy - mark.height / 2)))

    elif style == "aurora":
        blobs = [(0.18, 0.30, 0.55, a1, 0.55), (0.55, 0.12, 0.50, a2, 0.40), (0.85, 0.55, 0.60, rgb(p["magenta"]), 0.35), (0.40, 0.85, 0.45, a1, 0.30)]
        for bx, by, br, col, st in blobs:
            img.alpha_composite(radial_glow(w, h, w * bx, h * by, h * br, col, st * k))
        # Contour lines, like a topographic map of the glow.
        lines = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(lines)
        unit = h / 2880
        for j in range(18):
            pts = []
            for xi in range(0, 101):
                x = w * xi / 100
                y = h * (0.15 + j * 0.045) + h * 0.05 * math.sin(xi / 100 * math.pi * 2 + j * 0.12) + h * 0.02 * math.sin(xi / 100 * math.pi * 5 + j * 0.2)
                pts.append((x, y))
            col = (a2 if j % 2 else a1) + (26 if dark else 34,)
            for p0, p1 in zip(pts, pts[1:]):  # segment by segment: one long polyline draws stray chords
                d.line([p0, p1], fill=col, width=max(1, int(3 * unit)))
        img.alpha_composite(soft(lines, 1.0 * unit + 0.4))

    elif style == "sigil":
        img.alpha_composite(radial_glow(w, h, w / 2, h / 2, h * 0.8, a1, 0.25 * k))
        # A field of faint stars, then the mark large and centered.
        rng = np.random.default_rng(42)
        stars = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        d = ImageDraw.Draw(stars)
        for _ in range(int(900 * (w / 5120))):
            x, y = rng.uniform(0, w), rng.uniform(0, h)
            r = rng.choice([1, 1, 1.5, 2.5]) * h / 2880 * 2
            d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, int(rng.uniform(30, 140))))
        img.alpha_composite(stars)
        mark = draw_mark(int(h * 0.42), p["accent"], p["accent2"], p["bright_foreground"])
        img.alpha_composite(with_glow(mark, p["accent"], h * 0.012, 1.3), (int(w / 2 - h * 0.21), int(h / 2 - h * 0.21)))

    return dither(img)


# ---------------------------------------------------------------- themes

def theme_json(slug: str, p: dict, wallpapers: list[str], source: str) -> dict:
    # ANSI 0 ("black") must stand out from the background: dark themes use a lifted background,
    # light themes use the text color, as light terminal palettes do.
    black = p["lighter_background"] if p["mode"] == "dark" else p["foreground"]
    terminal = [
        black, p["red"], p["green"], p["yellow"], p["blue"], p["magenta"], p["cyan"], p["foreground"],
        p["muted"], p["bright_red"], p["bright_green"], p["bright_yellow"], p["bright_blue"], p["bright_magenta"], p["bright_cyan"], p["bright_foreground"],
    ]
    return {
        "name": p["name"],
        "slug": slug,
        "appearance": p["mode"],
        "source": source,
        "colors": {
            "background": p["background"], "foreground": p["foreground"],
            "accent": p["accent"], "accent2": p["accent2"],
            "muted": p["muted"], "selection": p["selection"],
            "cursor": p["bright_foreground"],
            "border_active": p["accent"], "border_inactive": p["selection"],
        },
        "terminal": [c.upper() if c.startswith("#") else c for c in terminal],
        "font": "JetBrainsMono Nerd Font",
        "wallpapers": wallpapers,
    }


def main() -> None:
    BRAND.mkdir(parents=True, exist_ok=True)
    night = SUMMON["summon-night"]

    icon = app_icon(1024)
    icon.save(BRAND / "app-icon-1024.png")
    for px in (512, 256, 128):
        icon.resize((px, px), Image.LANCZOS).save(BRAND / f"app-icon-{px}.png")
    menubar_icon(18).save(BRAND / "menubar-icon.png")
    menubar_icon(36).save(BRAND / "menubar-icon@2x.png")
    with_glow(draw_mark(1024, night["accent"], night["accent2"], night["bright_foreground"]), night["accent"], 26).save(BRAND / "mark-1024.png")
    (BRAND / "mark.svg").write_text(mark_svg(night["accent"], night["accent2"], night["bright_foreground"]))
    (BRAND / "mark-on-dark.svg").write_text(mark_svg(night["accent"], night["accent2"], night["bright_foreground"], bg=night["background"]))
    (BRAND / "mark-template.svg").write_text(mark_svg("#000000", "#000000", "#000000"))
    wordmark(240, night).save(BRAND / "wordmark-dark.png")
    wordmark(240, SUMMON["summon-dawn"]).save(BRAND / "wordmark-light.png")

    # Social / README banner.
    banner = wallpaper(night, "portal").resize((1600, 900), Image.LANCZOS).convert("RGBA") if not QUICK else wallpaper(night, "portal").resize((1600, 900)).convert("RGBA")
    wm = wordmark(150, night)
    banner.alpha_composite(wm, (110, 900 // 2 - 75))
    banner.convert("RGB").save(BRAND / "banner.png")

    sheet_items = []
    for slug, p in {**SUMMON, **PORTS}.items():
        styles = STYLES.get(slug, DEFAULT_STYLES)
        tdir = THEMES / slug
        tdir.mkdir(parents=True, exist_ok=True)
        names = []
        for i, style in enumerate(styles, 1):
            name = f"{i}-{style}.jpg"
            img = wallpaper(p, style)
            img.save(tdir / name, quality=90, optimize=True, progressive=True)
            sheet_items.append((p["name"], style, img.resize((480, 270), Image.LANCZOS)))
            names.append(name)
        source = "summon" if slug in SUMMON else f"omarchy:themes/{slug.replace('-dawn', '')}"
        (tdir / "theme.json").write_text(json.dumps(theme_json(slug, p, names, source), indent=2) + "\n")

    # Contact sheet of every wallpaper, for review.
    cols = 4
    rows = math.ceil(len(sheet_items) / cols)
    sheet = Image.new("RGB", (cols * 500 + 20, rows * 320 + 20), rgb(night["darker_background"]))
    d = ImageDraw.Draw(sheet)
    font = ImageFont.truetype(FONT_BOLD, 18)
    for i, (name, style, thumb) in enumerate(sheet_items):
        x, y = 20 + (i % cols) * 500, 20 + (i // cols) * 320
        sheet.paste(thumb, (x, y))
        d.text((x, y + 278), f"{name} · {style}", font=font, fill=night["foreground"])
    sheet.save(OUT / "wallpapers-preview.png" if QUICK else ROOT / "design" / "wallpapers-preview.png")
    print("done", "quick" if QUICK else "full")


if __name__ == "__main__":
    main()
