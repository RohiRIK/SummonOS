<p align="center"><img src="design/brand/banner.png" alt="Summon: a glowing summoning circle around a terminal prompt" width="800"></p>

<p align="center">
  <b>Status:</b> incubating in <code>macos-plugins</code>. Design, themes, plugin and configs are merged;
  the Swift app is in review and has not been compiled on a Mac yet.
</p>

# Summon

The Omarchy experience on macOS: **one agent you can summon from anywhere**, that sees the whole Mac
through documented commands, is handed problems automatically (crashes, failing services), and can set up,
theme, fix, and build things for you. Every session is checkpointed, so anything it does can be undone.

Moves to `mac-summon-dev` / `mac-summon` once it compiles on a Mac.
Plan: [`docs/plans/2026-10-17-summon.md`](../../docs/plans/2026-10-17-summon.md).

## Brand

| App icon | Mark | Wordmark |
|:---:|:---:|:---:|
| <img src="design/brand/app-icon-128.png" width="96" alt="Summon app icon"> | <img src="design/brand/mark-on-dark.svg" width="96" alt="Summon mark"> | <picture><source media="(prefers-color-scheme: dark)" srcset="design/brand/wordmark-dark.png"><img src="design/brand/wordmark-light.png" height="72" alt="summon wordmark"></picture> |

Also in [`design/brand/`](design/brand): app icons at 128 to 1024 px, the menu bar template icon
(`menubar-icon.png`, `@2x`), `mark.svg` (transparent), `mark-template.svg` (black, for templates), and
the 1600x900 banner above.

## Themes

Nine themes, each a `theme.json` (colors, 16 terminal colors, font) plus 5K wallpapers in
[`themes/`](themes): **Summon Night** (the default) and **Summon Dawn** (its light variant), and
Omarchy's Tokyo Night, Catppuccin, Gruvbox, Nord, Rosé Pine Dawn, Kanagawa and Everforest.

![Every Summon wallpaper: portal, aurora and sigil styles for Summon Night and Dawn, and a portal for each Omarchy port](design/wallpapers-preview.png)

## What is here

| Path | What |
|---|---|
| `plugin/` | Claude Code plugin (needs the `summon` and `macctl` binaries, which are still in review): skills `summon`, `mac-app`, `diagnose-crash-mac`, `mac-logs`; commands `/summon:setup`, `/summon:fix`, `/summon:theme`, `/summon:icon`, `/summon:new-menubar`, `/summon:new-app`, `/summon:new-cli`, `/summon:new-screensaver`, `/summon:activity`; `SessionStart`/`SessionEnd` hooks that record agent sessions for the Activity window; `macctl` MCP server |
| `themes/` | 9 themes (`theme.json` + 5K wallpapers): Summon Night, Summon Dawn, and Omarchy's Tokyo Night, Catppuccin, Gruvbox, Nord, Rosé Pine Dawn, Kanagawa, Everforest |
| `config/` | Desktop layer: `Brewfile` (AeroSpace, Ghostty, JankyBorders, Nerd Font), `aerospace.toml` (Omarchy-style ⌥ keymap), Ghostty config with a drop-down quick terminal, borders, shell aliases (`a`, `ap`) |
| `design/` | Logo, app icon, menu bar icon, wordmarks, `generate.py`, which renders all of them plus the wallpapers, and `brandkit.py`, the palettes and SVG mark it shares with the workspace README art |
| `Sources/`, `Tests/` | The `summon` CLI, the Summon Menu app, and their tests (Swift; separate PR) |

## Install the plugin (Claude Code)

Not yet: the skills and commands call the `summon` CLI and the `macctl` MCP server, which ship with the
Swift PRs. Once those build, a marketplace entry and `plugin/.mcp.json` are added so it installs with
`claude plugin install summon`. For development now: `claude --plugin-dir incubator/summon/plugin`.

## Default keys

| Keys | Does |
|---|---|
| ⌃⌥Space | Summon Menu |
| ⌃⌥⌘A | Summon the agent |
| ⌃⌥⌘\` | Drop-down terminal (type `a` for the agent) |
| ⌥1…9, ⌥⇧1…9 | Workspaces |
| ⌥H J K L, ⌥⇧H J K L | Focus, move windows |
| ⌥Return | Ghostty |

## Regenerate the art

```bash
python3 incubator/summon/design/generate.py          # full 5120×2880 wallpapers
python3 incubator/summon/design/generate.py --quick  # 1/4 size, for iterating
```

Needs Pillow and numpy. The Inter and DejaVu fonts it uses are the defaults on most Linux images; on a Mac,
point `FONT_BOLD` / `FONT_MONO` at any bold sans. Palettes and the SVG mark live in `design/brandkit.py`;
after changing them, also run `python3 tools/readme-art.py` from the repo root so the workspace README art
follows.

## License

MIT. Omarchy and the theme palettes: see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
