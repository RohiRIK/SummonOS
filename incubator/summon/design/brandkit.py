#!/usr/bin/env python3
"""Shared brand helpers: palettes, the ring mark as SVG, and SVG wordmarks.

Used by incubator/summon/design/generate.py (Summon's art) and tools/readme-art.py (README art).
Pure Python, no third-party imports, so the SVG tools run anywhere. Every function is deterministic:
the same input always gives the same bytes, which is what `tools/readme-art.py --check` relies on.
"""
from __future__ import annotations

import math
from xml.sax.saxutils import escape

# ---------------------------------------------------------------- palettes

# Summon's own themes. Night is the default; Dawn is the light variant.
SUMMON = {
    "summon-night": dict(
        name="Summon Night", mode="dark",
        background="#0E0B1A", darker_background="#08060F", lighter_background="#1A1530",
        foreground="#E4DEF7", bright_foreground="#F6F3FF", muted="#5C567A", selection="#2B2347",
        accent="#9B7BFF", accent2="#3DE1FF",
        red="#FF6B8B", green="#7CF2B0", yellow="#FFD479", blue="#7AA8FF", magenta="#D18BFF", cyan="#3DE1FF",
        bright_red="#FF8FA6", bright_green="#A3F7C9", bright_yellow="#FFE2A3", bright_blue="#A2C2FF",
        bright_magenta="#E2B2FF", bright_cyan="#8AEDFF",
    ),
    "summon-dawn": dict(
        name="Summon Dawn", mode="light",
        background="#F7F4FF", darker_background="#ECE7FA", lighter_background="#FFFFFF",
        foreground="#2B2440", bright_foreground="#15111F", muted="#9A93B5", selection="#DDD3FF",
        accent="#6D4AFF", accent2="#0098C7",
        red="#D63A63", green="#178A5B", yellow="#B07A00", blue="#2F62D6", magenta="#9B3FD6", cyan="#0098C7",
        bright_red="#E8577D", bright_green="#22A06E", bright_yellow="#C98E0C", bright_blue="#4A7BEA",
        bright_magenta="#B05AE8", bright_cyan="#14B0DE",
    ),
}

# Ports of Omarchy's stock palettes (themes/<name>/colors.toml in omacom/omarchy, MIT).
# Each palette is itself the work of its original project; see THIRD_PARTY_NOTICES.md.
PORTS = {
    "tokyo-night": dict(name="Tokyo Night", mode="dark", accent="#7aa2f7", accent2="#bb9af7", selection="#292e42", muted="#414868",
        background="#1a1b26", darker_background="#0e0e14", lighter_background="#24283b", foreground="#a9b1d6", bright_foreground="#c0caf5",
        red="#f7768e", yellow="#e0af68", green="#9ece6a", cyan="#449dab", blue="#7aa2f7", magenta="#ad8ee6",
        bright_red="#ff7a93", bright_yellow="#ff9e64", bright_green="#b9f27c", bright_cyan="#0db9d7", bright_blue="#7da6ff", bright_magenta="#bb9af7"),
    "catppuccin": dict(name="Catppuccin", mode="dark", accent="#89b4fa", accent2="#f5c2e7", selection="#45475a", muted="#585b70",
        background="#1e1e2e", darker_background="#101019", lighter_background="#313244", foreground="#cdd6f4", bright_foreground="#cdd6f4",
        red="#f38ba8", yellow="#f9e2af", green="#a6e3a1", cyan="#94e2d5", blue="#89b4fa", magenta="#f5c2e7",
        bright_red="#f38ba8", bright_yellow="#f9e2af", bright_green="#a6e3a1", bright_cyan="#94e2d5", bright_blue="#89b4fa", bright_magenta="#f5c2e7"),
    "gruvbox": dict(name="Gruvbox", mode="dark", accent="#7daea3", accent2="#d8a657", selection="#504945", muted="#665c54",
        background="#282828", darker_background="#161616", lighter_background="#3c3836", foreground="#d4be98", bright_foreground="#d4be98",
        red="#ea6962", yellow="#d8a657", green="#a9b665", cyan="#89b482", blue="#7daea3", magenta="#d3869b",
        bright_red="#ea6962", bright_yellow="#d8a657", bright_green="#a9b665", bright_cyan="#89b482", bright_blue="#7daea3", bright_magenta="#d3869b"),
    "nord": dict(name="Nord", mode="dark", accent="#81a1c1", accent2="#88c0d0", selection="#434c5e", muted="#4c566a",
        background="#2e3440", darker_background="#191c23", lighter_background="#3b4252", foreground="#d8dee9", bright_foreground="#d8dee9",
        red="#bf616a", yellow="#ebcb8b", green="#a3be8c", cyan="#88c0d0", blue="#81a1c1", magenta="#b48ead",
        bright_red="#bf616a", bright_yellow="#ebcb8b", bright_green="#a3be8c", bright_cyan="#8fbcbb", bright_blue="#81a1c1", bright_magenta="#b48ead"),
    "rose-pine-dawn": dict(name="Rosé Pine Dawn", mode="light", accent="#56949f", accent2="#907aa9", selection="#dfdad9", muted="#cecacd",
        background="#faf4ed", darker_background="#e1dbd5", lighter_background="#f2e9e1", foreground="#575279", bright_foreground="#575279",
        red="#b4637a", yellow="#ea9d34", green="#286983", cyan="#d7827e", blue="#56949f", magenta="#907aa9",
        bright_red="#b4637a", bright_yellow="#ea9d34", bright_green="#286983", bright_cyan="#d7827e", bright_blue="#56949f", bright_magenta="#907aa9"),
    "kanagawa": dict(name="Kanagawa", mode="dark", accent="#7e9cd8", accent2="#e6c384", selection="#363646", muted="#54546D",
        background="#1f1f28", darker_background="#111116", lighter_background="#223249", foreground="#dcd7ba", bright_foreground="#dcd7ba",
        red="#c34043", yellow="#c0a36e", green="#76946a", cyan="#6a9589", blue="#7e9cd8", magenta="#957fb8",
        bright_red="#e82424", bright_yellow="#e6c384", bright_green="#98bb6c", bright_cyan="#7aa89f", bright_blue="#7fb4ca", bright_magenta="#938aa9"),
    "everforest": dict(name="Everforest", mode="dark", accent="#7fbbb3", accent2="#a7c080", selection="#3d484d", muted="#475258",
        background="#2d353b", darker_background="#181d20", lighter_background="#343f44", foreground="#d3c6aa", bright_foreground="#d3c6aa",
        red="#e67e80", yellow="#dbbc7f", green="#a7c080", cyan="#83c092", blue="#7fbbb3", magenta="#d699b6",
        bright_red="#e67e80", bright_yellow="#dbbc7f", bright_green="#a7c080", bright_cyan="#83c092", bright_blue="#7fbbb3", bright_magenta="#d699b6"),
}


# ---------------------------------------------------------------- color helpers

def rgb(hex_: str) -> tuple[int, int, int]:
    h = hex_.lstrip("#")
    return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)


def mix(a: str, b: str, t: float) -> tuple[int, int, int]:
    ra, rb = rgb(a), rgb(b)
    return tuple(round(ra[i] + (rb[i] - ra[i]) * t) for i in range(3))


# ---------------------------------------------------------------- the ring mark (SVG)

def ring_parts(cx: float, R: float, s: float) -> tuple[list[str], list[str], float, float]:
    """Runes (six diamonds on the outer ring) and three broken inner arcs, as SVG path strings.

    Geometry matches draw_mark in generate.py: R is the outer radius, s the canvas size it scales with.
    Returns (runes, arcs, r2, r3): r2 is the thin inner ring, r3 the radius of the arcs.
    """
    r2, r3 = R * 0.86, R * 0.70
    runes = []
    for i in range(6):
        ang = -math.pi / 2 + i * math.pi / 3
        px, py = cx + R * math.cos(ang), cx + R * math.sin(ang)
        k = s * (0.05 if i == 0 else 0.032)
        runes.append(f'<path d="M{px:.1f} {py - k:.1f}L{px + k:.1f} {py:.1f}L{px:.1f} {py + k:.1f}L{px - k:.1f} {py:.1f}Z"/>')
    arcs = []
    for start in (200, 320, 80):
        a0, a1 = math.radians(start), math.radians(start + 70)
        x0, y0 = cx + r3 * math.cos(a0), cx + r3 * math.sin(a0)
        x1, y1 = cx + r3 * math.cos(a1), cx + r3 * math.sin(a1)
        arcs.append(f'<path d="M{x0:.1f} {y0:.1f}A{r3:.1f} {r3:.1f} 0 0 1 {x1:.1f} {y1:.1f}" opacity=".8"/>')
    return runes, arcs, r2, r3


def gradient_def(gid: str, c1: str, c2: str) -> str:
    return (f'<linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c1}"/>'
            f'<stop offset="1" stop-color="{c2}"/></linearGradient>')


def ring_body(gid: str = "g") -> str:
    """Rings, arcs and runes on the 1024 grid, painted with gradient `gid` (defined by the caller)."""
    s, cx, R = 1024, 512, 1024 * 0.40
    runes, arcs, r2, _ = ring_parts(cx, R, s)
    return f'''<g fill="none" stroke="url(#{gid})" stroke-linecap="round">
    <circle cx="{cx}" cy="{cx}" r="{R - s * 0.013:.1f}" stroke-width="{s * 0.026:.1f}"/>
    <circle cx="{cx}" cy="{cx}" r="{r2 - s * 0.0045:.1f}" stroke-width="{s * 0.009:.1f}" opacity=".55"/>
    <g stroke-width="{s * 0.012:.1f}">{"".join(arcs)}</g>
  </g>
  <g fill="url(#{gid})">{"".join(runes)}</g>'''


def prompt_glyph(glyph: str) -> str:
    """Summon's center glyph on the 1024 grid: a terminal prompt `›_`."""
    s, cx = 1024, 512
    k, stroke = s * 0.13, s * 0.055
    gx, gy = cx - s * 0.075, cx - s * 0.005
    return f'''<g fill="none" stroke="{glyph}" stroke-width="{stroke:.1f}" stroke-linecap="round" stroke-linejoin="round">
    <path d="M{gx - k * 0.55:.1f} {gy - k:.1f}L{gx + k * 0.55:.1f} {gy:.1f}L{gx - k * 0.55:.1f} {gy + k:.1f}"/>
    <path d="M{gx + k * 0.95 + stroke / 2:.1f} {gy + k * 0.92:.1f}H{gx + k * 2.05 - stroke / 2:.1f}"/>
  </g>'''


def mark_svg(c1: str, c2: str, glyph: str, bg: str | None = None) -> str:
    """Vector version of draw_mark on a 1024 grid, same geometry."""
    bgrect = f'<rect width="1024" height="1024" rx="230" fill="{bg}"/>' if bg else ""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="{c1}"/><stop offset="1" stop-color="{c2}"/></linearGradient></defs>
  {bgrect}
  {ring_body("g")}
  {prompt_glyph(glyph)}
</svg>
'''


def ring_mark(x: float, y: float, size: float, gid: str, glyph_svg: str) -> str:
    """The ring mark at (x, y), `size` px square, for embedding in a larger SVG.

    `glyph_svg` is the center glyph drawn on the 1024 grid; `gid` must be defined in the outer <defs>.
    """
    return (f'<svg x="{x:g}" y="{y:g}" width="{size:g}" height="{size:g}" viewBox="0 0 1024 1024">'
            f'{ring_body(gid)}{glyph_svg}</svg>')


# ---------------------------------------------------------------- text metrics and wordmarks

# Advance widths of Inter Bold (700), SemiBold (600) and Regular (400) for ASCII 32..126, in 1/1000 em.
# Measured once from the Inter OTFs with Pillow and frozen here, so layout never depends on which
# fonts the machine running the script has installed.
_ADVANCE = {
    700: [237, 338, 552, 649, 655, 1016, 672, 339, 377, 377, 559, 679, 334, 468, 334, 388, 674, 431, 630, 646, 676, 639, 649, 582, 651, 649, 334, 343, 679, 679, 679, 560, 1016, 747, 662, 740, 722, 607, 587, 750, 747, 281, 584, 719, 565, 932, 762, 771, 648, 777, 657, 655, 667, 732, 747, 1038, 738, 731, 664, 377, 388, 377, 487, 476, 365, 581, 630, 588, 630, 596, 398, 632, 623, 271, 271, 580, 271, 913, 623, 613, 630, 630, 407, 560, 366, 623, 600, 850, 580, 602, 573, 469, 372, 469, 679],
    600: [252, 321, 523, 644, 650, 1004, 663, 326, 373, 373, 540, 673, 319, 465, 319, 379, 660, 423, 623, 636, 666, 629, 640, 576, 640, 640, 319, 329, 673, 673, 673, 543, 999, 728, 659, 737, 722, 605, 588, 749, 746, 277, 580, 703, 565, 922, 759, 769, 645, 773, 652, 650, 660, 736, 728, 1020, 720, 713, 652, 373, 379, 373, 481, 469, 351, 574, 624, 583, 624, 591, 389, 625, 612, 262, 262, 569, 262, 900, 612, 609, 624, 624, 397, 549, 353, 612, 587, 839, 569, 588, 566, 455, 359, 455, 673],
    400: [281, 288, 466, 633, 642, 982, 644, 300, 365, 365, 501, 662, 288, 460, 288, 360, 631, 407, 610, 618, 646, 608, 620, 566, 619, 620, 288, 302, 662, 662, 662, 511, 966, 690, 654, 730, 722, 601, 590, 746, 743, 269, 571, 672, 565, 903, 753, 765, 639, 765, 644, 642, 646, 744, 690, 985, 682, 679, 629, 365, 360, 365, 471, 456, 323, 562, 612, 571, 612, 583, 370, 613, 591, 242, 242, 549, 242, 876, 591, 600, 612, 612, 376, 528, 327, 591, 562, 818, 546, 562, 552, 426, 333, 426, 662],
}

SANS = "Inter, -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif"
MONO = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'DejaVu Sans Mono', monospace"
MONO_ADVANCE = 0.6  # em; every font in MONO is close to this


def text_width(text: str, size: float, weight: int = 400, letter_spacing: float = 0.0) -> float:
    """Width of `text` set in Inter at `size` px; characters outside ASCII count as an average letter."""
    table = _ADVANCE[weight]
    units = sum(table[ord(c) - 32] if 32 <= ord(c) <= 126 else 600 for c in text)
    return units / 1000 * size + letter_spacing * max(0, len(text) - 1)


def text_el(x: float, y: float, text: str, size: float, fill: str, weight: int = 400,
            anchor: str = "start", family: str = SANS, extra: str = "") -> str:
    """One <text> element; the text is XML-escaped."""
    a = "" if anchor == "start" else f' text-anchor="{anchor}"'
    return (f'<text x="{x:g}" y="{y:g}" font-family="{family}" font-size="{size:g}" font-weight="{weight}" '
            f'fill="{fill}"{a}{extra}>{escape(text)}</text>')


def wordmark_svg(text: str, p: dict, glyph_svg: str | None = None, height: int = 120,
                 gid: str = "wm") -> str:
    """A ring mark followed by a lowercase name (like Summon's PNG wordmark), as a standalone SVG.

    `p` is a palette: SUMMON["summon-night"] for dark backgrounds, SUMMON["summon-dawn"] for light ones.
    `glyph_svg` is the center glyph on the 1024 grid; it defaults to Summon's prompt.
    """
    glyph_svg = glyph_svg if glyph_svg is not None else prompt_glyph(p["bright_foreground"])
    size = round(height * 0.48, 1)
    gap = round(height * 0.18, 1)
    spacing = -0.01 * size
    width = math.ceil(height + gap + text_width(text, size, 700, spacing) + height * 0.1)
    baseline = round(height / 2 + size * 0.36, 1)
    label = escape(text)
    tracking = f' letter-spacing="{spacing:g}"'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {width} {height}" width="{width}" '
            f'height="{height}" role="img" aria-label="{label}">\n'
            f'  <title>{label}</title>\n'
            f'  <defs>{gradient_def(gid, p["accent"], p["accent2"])}</defs>\n'
            f'  {ring_mark(0, 0, height, gid, glyph_svg)}\n'
            f'  {text_el(height + gap, baseline, text, size, p["bright_foreground"], 700, extra=tracking)}\n'
            '</svg>\n')
