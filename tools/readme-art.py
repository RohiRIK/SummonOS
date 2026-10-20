#!/usr/bin/env python3
"""Render the README art in docs/assets/ as plain SVG: logos, hero banner, diagram, pill, terminal cards.

    python3 tools/readme-art.py           # write every SVG
    python3 tools/readme-art.py --check   # exit 1 if a committed SVG differs from what this would write

Pure Python 3.10+, no packages. Output is deterministic (no dates, frozen font metrics), so --check is
stable on any machine. Colors and the ring mark come from incubator/summon/design/brandkit.py.
Terminal cards are rendered from macctl/docs/demo/*.txt; tools/record-demos.sh refreshes those on a Mac.

Transcript format: optional leading `# ...` comment lines (a comment starting with `# illustrative`
puts an "illustrative" tag on the card), then one or more `$ command` lines, each followed by its output.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "incubator" / "summon" / "design"))
sys.dont_write_bytecode = True

from brandkit import (  # noqa: E402
    MONO, MONO_ADVANCE, SUMMON, gradient_def, mix, prompt_glyph, ring_mark, text_el, text_width, wordmark_svg,
)

ASSETS = ROOT / "docs" / "assets"
DEMO_SRC = ROOT / "macctl" / "docs" / "demo"
DARK, LIGHT = SUMMON["summon-night"], SUMMON["summon-dawn"]
THEMES = {"dark": DARK, "light": LIGHT}


# ---------------------------------------------------------------- glyphs (1024 grid, centered on 512)

def _stroke(color: str, width: float = 56) -> str:
    return f'fill="none" stroke="{color}" stroke-width="{width:g}" stroke-linecap="round" stroke-linejoin="round"'


def glyph_macctl(c: str) -> str:
    """Two settings sliders."""
    return (f'<g {_stroke(c, 48)}><path d="M336 432H688"/><path d="M336 600H688"/></g>'
            f'<circle cx="602" cy="432" r="52" fill="{c}"/><circle cx="422" cy="600" r="52" fill="{c}"/>')


def glyph_network(c: str) -> str:
    """Wi-Fi arcs."""
    arcs = "".join(f'<path d="M{512 - r * 0.7071:.1f} {632 - r * 0.7071:.1f}A{r} {r} 0 0 1 {512 + r * 0.7071:.1f} {632 - r * 0.7071:.1f}"/>'
                   for r in (110, 200, 290))
    return f'<g {_stroke(c, 48)}>{arcs}</g><circle cx="512" cy="636" r="38" fill="{c}"/>'


def glyph_calendar(c: str) -> str:
    """A calendar page with two binder tabs and a grid of days."""
    dots = "".join(f'<circle cx="{x}" cy="{y}" r="22" fill="{c}"/>' for y in (548, 616) for x in (436, 512, 588))
    return (f'<g {_stroke(c, 44)}><path d="M392 392H632A40 40 0 0 1 672 432V632A40 40 0 0 1 632 672H392A40 40 0 0 1 352 632V432A40 40 0 0 1 392 392Z"/>'
            f'<path d="M352 480H672"/><path d="M440 352V420"/><path d="M584 352V420"/></g>{dots}')


def glyph_end_of_day(c: str) -> str:
    """A sun setting on the horizon."""
    return (f'<g {_stroke(c, 48)}><path d="M372 600A140 140 0 0 1 652 600"/><path d="M312 600H712"/>'
            f'<path d="M412 680H612"/><path d="M512 380V420"/><path d="M372 438L398 464"/><path d="M652 438L626 464"/></g>')


def glyph_skills(c: str) -> str:
    """An open book: the skills agents read."""
    return (f'<g {_stroke(c, 44)}><path d="M512 404C460 372 400 360 340 364V636C400 632 460 644 512 676'
            f'C564 644 624 632 684 636V364C624 360 564 372 512 404Z"/><path d="M512 404V676"/></g>')


def glyph_summon(c: str) -> str:
    return prompt_glyph(c)


PROJECTS = [  # name, glyph, gradient color keys, two description lines
    ("mac-network", glyph_network, ("blue", "cyan"), ("Wi-Fi and IP settings", "from the menu bar")),
    ("mac-calendar", glyph_calendar, ("green", "cyan"), ("Calendar, events, reminders", "and Hebrew dates")),
    ("macctl", glyph_macctl, ("accent", "accent2"), ("Mac settings for agents,", "with snapshots and undo")),
    ("Summon", glyph_summon, ("magenta", "accent"), ("An agent you summon", "from anywhere on the Mac")),
]


# ---------------------------------------------------------------- shared pieces

TAGLINE = "Powered by caffeine and questionable life choices."
TIGHT = ' letter-spacing="-1.2"'
SOFT = ' opacity=".8"'
SOFTER = ' opacity=".72"'
DIM = ' opacity=".6"'

def svg_open(w: int, h: int, label: str) -> str:
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {w} {h}" width="{w}" height="{h}" '
            f'role="img" aria-label="{escape(label)}">\n  <title>{escape(label)}</title>\n')


def fits(text: str, size: float, weight: int, room: float) -> str:
    """Fail loudly instead of drawing text that overflows its box."""
    width = text_width(text, size, weight)
    if width > room:
        raise SystemExit(f"readme-art: '{text}' is {width:.0f}px wide, room is {room:.0f}px")
    return text


def background(w: int, h: int, p: dict, dark: bool, rx: int) -> str:
    top, bottom = (p["darker_background"], p["background"]) if dark else (p["lighter_background"], p["darker_background"])
    return (f'<defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="{top}"/>'
            f'<stop offset="1" stop-color="{bottom}"/></linearGradient>'
            f'<radialGradient id="glow" cx=".5" cy=".5" r=".5"><stop offset="0" stop-color="{p["accent"]}" stop-opacity="{0.35 if dark else 0.22}"/>'
            f'<stop offset="1" stop-color="{p["accent"]}" stop-opacity="0"/></radialGradient></defs>\n'
            f'  <rect width="{w}" height="{h}" rx="{rx}" fill="url(#bg)"/>\n')


# ---------------------------------------------------------------- assets

def wordmark(p: dict) -> str:
    return wordmark_svg("SummonOS", p, glyph_summon(p["bright_foreground"]), height=120)


def macctl_logo(p: dict) -> str:
    return wordmark_svg("macctl", p, glyph_macctl(p["bright_foreground"]), height=120)


APPS = [  # apps shown only in the README's "Built with SummonOS" table: name, glyph, gradient color keys
    ("end-of-day", glyph_end_of_day, ("yellow", "red")),
    ("skills", glyph_skills, ("green", "accent")),
]


def project_icon(name: str, glyph, colors: tuple[str, str]) -> str:
    """A 128 px app-icon tile (dark, so it reads on light and dark pages) for the README tables."""
    a, b = colors
    p, s = DARK, 128
    return (svg_open(s, s, name) +
            f'  <defs>{gradient_def("gi", p[a], p[b])}<linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">'
            f'<stop offset="0" stop-color="{p["lighter_background"]}"/><stop offset="1" stop-color="{p["darker_background"]}"/></linearGradient></defs>\n'
            f'  <rect width="{s}" height="{s}" rx="29" fill="url(#bg)"/>\n'
            f'  <rect x=".75" y=".75" width="{s - 1.5}" height="{s - 1.5}" rx="28.25" fill="none" stroke="{p["selection"]}" stroke-width="1.5"/>\n'
            f'  {ring_mark(8, 8, s - 16, "gi", glyph(p["bright_foreground"]))}\n'
            '</svg>\n')


def hero(p: dict, dark: bool) -> str:
    w, h = 1280, 400
    out = [svg_open(w, h, "SummonOS: native Mac apps, summoned by agents, in Swift"), "  ", background(w, h, p, dark, 24)]
    defs = [gradient_def("gm", p["accent"], p["accent2"])]
    defs += [gradient_def(f"g{i}", p[a], p[b]) for i, (_, _, (a, b), _) in enumerate(PROJECTS)]
    out.append(f'  <defs>{"".join(defs)}</defs>\n')
    # Portal rings behind the tiles, like the Summon wallpapers.
    cx, cy = 930, 200
    rings = "".join(f'<circle cx="{cx}" cy="{cy}" r="{r}" stroke="{p["accent"] if i % 2 == 0 else p["accent2"]}" '
                    f'stroke-opacity="{0.22 if i % 3 == 0 else 0.11}" stroke-width="{2 if i % 3 == 0 else 1}"/>'
                    for i, r in enumerate((90, 140, 200, 270, 350, 440, 540)))
    out.append(f'  <clipPath id="frame"><rect width="{w}" height="{h}" rx="24"/></clipPath>\n')
    out.append(f'  <g clip-path="url(#frame)"><circle cx="{cx}" cy="{cy}" r="420" fill="url(#glow)"/>'
               f'<g fill="none">{rings}</g></g>\n')

    # Left: mark, name, pitch.
    x = 64
    out.append(f'  {ring_mark(x - 8, 64, 96, "gm", glyph_summon(p["bright_foreground"]))}\n')
    out.append(f'  {text_el(x, 222, fits("SummonOS", 60, 700, 520), 60, p["bright_foreground"], 700, extra=TIGHT)}\n')
    for i, line in enumerate(("Native Mac apps, summoned by agents.", "Swift 6 and SwiftUI. Instant, offline, at home on a Mac.")):
        out.append(f'  {text_el(x, 272 + i * 32, fits(line, 21, 400, 540), 21, p["foreground"], 400, extra=SOFTER if i else "")}\n')
    out.append(f'  {text_el(x, 352, fits(TAGLINE, 15, 600, 540), 15, p["accent"], 600)}\n')

    # Right: a 2 x 2 grid of project tiles.
    tw, th, gap, x0, y0 = 300, 120, 16, 620, 72
    tile_fill = p["lighter_background"]
    for i, (name, glyph, _, lines) in enumerate(PROJECTS):
        tx, ty = x0 + (i % 2) * (tw + gap), y0 + (i // 2) * (th + gap)
        out.append(f'  <rect x="{tx}" y="{ty}" width="{tw}" height="{th}" rx="18" fill="{tile_fill}" fill-opacity="{0.78 if dark else 0.92}" '
                   f'stroke="{p["selection"]}" stroke-width="1.5"/>\n')
        out.append(f'  {ring_mark(tx + 14, ty + 26, 68, f"g{i}", glyph(p["bright_foreground"]))}\n')
        room = tw - 96 - 14
        out.append(f'  {text_el(tx + 96, ty + 46, fits(name, 20, 600, room), 20, p["bright_foreground"], 600)}\n')
        for j, line in enumerate(lines):
            out.append(f'  {text_el(tx + 96, ty + 72 + j * 20, fits(line, 14, 400, room), 14, p["foreground"], 400, extra=SOFT)}\n')
    out.append("</svg>\n")
    return "".join(out)


STEPS = [
    ("Plan", ("A new app idea, or a", "Linux widget to port")),
    ("Build", ("SwiftPM and SwiftUI,", "Core logic test-first")),
    ("Verify", ("Gate, previews, run", "the app, read the logs")),
    ("Publish", ("Dev repo PR, then a", "clean public snapshot")),
]


def lifecycle(p: dict, dark: bool) -> str:
    cw, ch, gap, pad = 200, 132, 48, 24
    w, h = pad * 2 + cw * 4 + gap * 3, ch + pad * 2
    out = [svg_open(w, h, "How a SummonOS app is made: plan, build, verify, publish"), "  ", background(w, h, p, dark, 20)]
    out.append(f'  <defs>{gradient_def("gs", p["accent"], p["accent2"])}'
               f'<marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
               f'<path d="M1 1L9 5L1 9" fill="none" stroke="{p["accent"]}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></marker></defs>\n')
    for i, (title, lines) in enumerate(STEPS):
        x, y = pad + i * (cw + gap), pad
        out.append(f'  <rect x="{x}" y="{y}" width="{cw}" height="{ch}" rx="16" fill="{p["lighter_background"]}" '
                   f'fill-opacity="{0.8 if dark else 0.95}" stroke="{p["selection"]}" stroke-width="1.5"/>\n')
        out.append(f'  <circle cx="{x + 34}" cy="{y + 36}" r="16" fill="none" stroke="url(#gs)" stroke-width="3"/>\n')
        out.append(f'  {text_el(x + 34, y + 41.5, str(i + 1), 15, p["bright_foreground"], 700, anchor="middle")}\n')
        out.append(f'  {text_el(x + 60, y + 43, fits(title, 20, 600, cw - 76), 20, p["bright_foreground"], 600)}\n')
        for j, line in enumerate(lines):
            out.append(f'  {text_el(x + 20, y + 84 + j * 20, fits(line, 14, 400, cw - 32), 14, p["foreground"], 400, extra=SOFT)}\n')
        if i < len(STEPS) - 1:
            ax = x + cw + 8
            out.append(f'  <path d="M{ax} {y + ch / 2:g}H{ax + gap - 16}" stroke="{p["accent"]}" stroke-width="2" '
                       f'stroke-linecap="round" marker-end="url(#arrow)"/>\n')
    out.append("</svg>\n")
    return "".join(out)


def pill() -> str:
    """A static two-part badge, readable on light and dark pages."""
    left, right, size, h = "Swift 6", "macOS 15+", 11, 20
    lw = round(text_width(left, size, 600) + 16)
    rw = round(text_width(right, size, 600) + 16)
    w = lw + rw
    return (svg_open(w, h, f"{left} | {right}") +
            f'  <clipPath id="r"><rect width="{w}" height="{h}" rx="4"/></clipPath>\n'
            f'  <g clip-path="url(#r)"><rect width="{lw}" height="{h}" fill="#C8412B"/>'
            f'<rect x="{lw}" width="{rw}" height="{h}" fill="#5B3FD9"/></g>\n'
            f'  {text_el(lw / 2, 14, left, size, "#FFFFFF", 600, anchor="middle")}\n'
            f'  {text_el(lw + rw / 2, 14, right, size, "#FFFFFF", 600, anchor="middle")}\n'
            '</svg>\n')


# ---------------------------------------------------------------- terminal cards

TOKEN = re.compile(r'(?P<key>"[^"]*"(?=\s*:))|(?P<str>"[^"]*")|(?P<lit>\btrue\b|\bfalse\b|\bnull\b|(?<![\w.])-?\d+(?:\.\d+)?(?![\w.]))'
                   r'|(?P<dim>->|\(unset\)|\(was\)|\(set\))')


def color_line(line: str, p: dict) -> str:
    """Escaped <tspan>s for one output line: JSON keys, strings, literals, arrows, status words."""
    fg = p["foreground"]
    head = re.match(r"^(ok|MISSING)(\s)", line)
    if head:
        col = p["green"] if head.group(1) == "ok" else p["red"]
        return f'<tspan fill="{col}">{head.group(1)}</tspan>' + color_line(line[len(head.group(1)):], p)
    if re.fullmatch(r"[A-Z]+(\s+[A-Z]+)+", line.strip()):
        return f'<tspan fill="{p["muted"]}" font-weight="700">{escape(line)}</tspan>'
    colors = {"key": p["cyan"], "str": p["green"], "lit": p["yellow"], "dim": p["muted"]}
    parts, pos = [], 0
    for m in TOKEN.finditer(line):
        if m.start() > pos:
            parts.append(escape(line[pos:m.start()]))
        parts.append(f'<tspan fill="{colors[m.lastgroup]}">{escape(m.group())}</tspan>')
        pos = m.end()
    parts.append(escape(line[pos:]))
    return f'<tspan fill="{fg}">{"".join(parts)}</tspan>' if parts != [""] else ""


def parse_transcript(text: str) -> tuple[bool, list[str]]:
    lines = text.rstrip("\n").split("\n")
    illustrative = False
    while lines and lines[0].startswith("#"):
        illustrative |= lines[0].lower().startswith("# illustrative")
        lines.pop(0)
    return illustrative, lines


def terminal_card(text: str, p: dict, title: str) -> str:
    illustrative, lines = parse_transcript(text)
    # The palette's muted color is too faint for text on the darkest background; lift it a little.
    p = {**p, "muted": "#%02X%02X%02X" % mix(p["muted"], p["foreground"], 0.35)}
    size, lh, pad, bar = 14, 21, 22, 38
    cols = max([len(line) for line in lines] + [52])
    w = round(pad * 2 + cols * size * MONO_ADVANCE)
    h = bar + pad + len(lines) * lh + pad - 6
    out = [svg_open(w, h, f"Terminal: {title}")]
    out.append(f'  <rect width="{w}" height="{h}" rx="12" fill="{p["darker_background"]}"/>\n')
    out.append(f'  <rect x=".5" y=".5" width="{w - 1}" height="{h - 1}" rx="11.5" fill="none" stroke="{p["selection"]}"/>\n')
    out.append(f'  <path d="M0 {bar}H{w}" stroke="{p["selection"]}"/>\n')
    for i, c in enumerate(("#FF5F57", "#FEBC2E", "#28C840")):
        out.append(f'  <circle cx="{20 + i * 20}" cy="{bar / 2:g}" r="6" fill="{c}"/>\n')
    out.append(f'  {text_el(w / 2, bar / 2 + 4.5, title, 13, p["foreground"], 600, anchor="middle", extra=DIM)}\n')
    if illustrative:
        tag = "illustrative"
        tw = round(text_width(tag, 11, 600) + 16)
        out.append(f'  <rect x="{w - tw - 12}" y="{bar / 2 - 10:g}" width="{tw}" height="20" rx="10" fill="none" stroke="{p["muted"]}"/>\n')
        out.append(f'  {text_el(w - 12 - tw / 2, bar / 2 + 4, tag, 11, p["muted"], 600, anchor="middle")}\n')
    out.append(f'  <g font-family="{MONO}" font-size="{size}" xml:space="preserve">\n')
    for i, line in enumerate(lines):
        y = bar + pad + 10 + i * lh
        if line.startswith("$ "):
            body = (f'<tspan fill="{p["accent"]}" font-weight="700">$</tspan> '
                    f'<tspan fill="{p["bright_foreground"]}" font-weight="700">{escape(line[2:])}</tspan>')
        else:
            body = color_line(line, p)
        if body:
            out.append(f'    <text x="{pad}" y="{y}" style="white-space:pre">{body}</text>\n')
    out.append("  </g>\n</svg>\n")
    return "".join(out)


# ---------------------------------------------------------------- main

def outputs() -> dict[Path, str]:
    files: dict[Path, str] = {}
    for mode, p in THEMES.items():
        dark = mode == "dark"
        files[ASSETS / f"wordmark-{mode}.svg"] = wordmark(p)
        files[ASSETS / f"macctl-logo-{mode}.svg"] = macctl_logo(p)
        files[ASSETS / f"hero-{mode}.svg"] = hero(p, dark)
        files[ASSETS / f"lifecycle-{mode}.svg"] = lifecycle(p, dark)
    files[ASSETS / "pill-swift-macos.svg"] = pill()
    for name, glyph, colors, _ in PROJECTS:
        if name != "Summon":  # Summon has its own app icon in incubator/summon/design/brand/
            files[ASSETS / f"icon-{name}.svg"] = project_icon(name, glyph, colors)
    for name, glyph, colors in APPS:
        files[ASSETS / f"icon-{name}.svg"] = project_icon(name, glyph, colors)
    for src in sorted(DEMO_SRC.glob("*.txt")):
        files[ASSETS / "demo" / f"macctl-{src.stem}.svg"] = terminal_card(src.read_text(), DARK, f"macctl {src.stem}")
    return files


def main() -> int:
    check = "--check" in sys.argv[1:]
    stale = []
    for path, content in outputs().items():
        current = path.read_text() if path.exists() else None
        if current == content:
            continue
        if check:
            stale.append(path.relative_to(ROOT))
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)
            print("wrote", path.relative_to(ROOT))
    if stale:
        print("readme-art: stale, run python3 tools/readme-art.py:", *stale, sep="\n  ", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
