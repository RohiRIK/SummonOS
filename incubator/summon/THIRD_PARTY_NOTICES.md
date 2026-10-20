# Third-party notices

## Omarchy

Summon's design (default agent, summon points, crash handoff, menu tree, hooks, theme layout) follows
[Omarchy](https://github.com/omacom/omarchy). The skill `diagnose-crash-mac` adapts the structure of
Omarchy's `diagnose-crash` skill to macOS. The ported theme palettes in `themes/` were taken from
Omarchy's `themes/<name>/colors.toml`.

MIT License, Copyright (c) David Heinemeier Hansson.

## Theme palettes

Each ported palette is the work of its original project, all MIT licensed:

| Theme | Project |
|---|---|
| Tokyo Night | [enkia/tokyo-night-vscode-theme](https://github.com/enkia/tokyo-night-vscode-theme) |
| Catppuccin | [catppuccin/catppuccin](https://github.com/catppuccin/catppuccin) |
| Gruvbox | [morhetz/gruvbox](https://github.com/morhetz/gruvbox) (Material variant by sainnhe) |
| Nord | [nordtheme/nord](https://github.com/nordtheme/nord) |
| Rosé Pine Dawn | [rose-pine/rose-pine-theme](https://github.com/rose-pine/rose-pine-theme) |
| Kanagawa | [rebelot/kanagawa.nvim](https://github.com/rebelot/kanagawa.nvim) |
| Everforest | [sainnhe/everforest](https://github.com/sainnhe/everforest) |

The wallpapers, the Summon mark, and the Summon Night / Summon Dawn themes are original to this project.

## Agent provider icons (CodexBar)

The following files in `Resources/agents/` are byte-for-byte copies of the corresponding files in
[CodexBar's provider icon directory](https://github.com/steipete/CodexBar/tree/215efbd39ad58acb4b0cd637c407d63e6183bc8d/Sources/CodexBar/Resources)
at commit `215efbd39ad58acb4b0cd637c407d63e6183bc8d`:

- `ProviderIcon-antigravity.svg`
- `ProviderIcon-claude.svg`
- `ProviderIcon-codex.svg`
- `ProviderIcon-copilot.svg`
- `ProviderIcon-cursor.svg`
- `ProviderIcon-devin.svg`
- `ProviderIcon-gemini.svg`
- `ProviderIcon-grok.svg`
- `ProviderIcon-ollama.svg`
- `ProviderIcon-opencode.svg`

The embedded SVG fallbacks in `Sources/SummonMenuUI/AgentBrandIcon.swift` reuse these paths, with
presentation attributes adjusted for template rendering. The Devin-labelled asset is CodexBar's
gear-shaped icon; it is not original Summon artwork, and this attribution does not establish it as
an official Devin brand mark. Provider names and marks remain the property of their respective owners;
including them identifies supported agents and does not imply endorsement.

[Upstream license](https://github.com/steipete/CodexBar/blob/215efbd39ad58acb4b0cd637c407d63e6183bc8d/LICENSE):

```text
MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
