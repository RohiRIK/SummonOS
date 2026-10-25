---
type: Research
title: Where each agent keeps its MCP servers and instructions
description: "MCP config, instructions file, launch commands and start hooks for the eight agents summon connect reaches."
tags: [research, agents, mcp]
created: 2026-10-25
---

# Research: agent MCP configs (2026-10-25)

This page backs `summon connect` (`incubator/summon/Sources/SummonCore/AgentConnect.swift`). The targets were chosen
by the owner on 2026-10-25. Gemini CLI is excluded: it is deprecated and replaced by the Antigravity CLI (`agy`).

**Status:**
- Checked on a Mac: Claude Code 2.1.310, Codex 0.158.0, opencode 2.0.32.
- From docs only (not installed): Hermes, OpenClaw, `agy`, pi.

| Agent | MCP server | `summon connect` uses | Instructions file | Start hook |
|---|---|---|---|---|
| Claude Code | `~/.claude.json` › `mcpServers` | `claude mcp add --scope user summon -- <summon> mcp` (and `remove`, `get`) | `~/.claude/CLAUDE.md` | `SessionStart` in `~/.claude/settings.json`; stdout or `additionalContext` |
| Codex | `~/.codex/config.toml` › `[mcp_servers.summon]` | `codex mcp add summon -- <summon> mcp` (and `remove`, `get`) | `~/.codex/AGENTS.md` | `SessionStart` in `~/.codex/hooks.json` |
| Cursor | `~/.cursor/mcp.json` › `mcpServers` (the editor and the `agent`/`cursor-agent` CLI share it) | edit the file. The CLI has no `mcp add` | none (User Rules are set in the app) | `sessionStart` in `~/.cursor/hooks.json`, `additional_context` |
| opencode | `~/.config/opencode/opencode.json[c]` › `mcp` (`command` is an array, `environment`) | `opencode mcp add --global summon -- <summon> mcp`. There is no `remove`, so disconnect is manual | `~/.config/opencode/AGENTS.md` | plugin (not verified on v2) |
| Hermes | `~/.hermes/config.yaml` › `mcp_servers` | `hermes mcp add summon --command <summon> --args mcp` (`--args` last) | none. `~/.hermes/SOUL.md` is its identity; the server's MCP instructions cover it | `pre_llm_call` shell hook can add context |
| OpenClaw | `~/.openclaw/openclaw.json` (JSON5) › `mcp.servers` | `openclaw mcp add summon --command <summon> --arg mcp` | `~/.openclaw/workspace/AGENTS.md` | `agent:bootstrap` via `bootstrap-extra-files` |
| Antigravity CLI | `~/.gemini/config/mcp_config.json` › `mcpServers` (the IDE uses `~/.gemini/antigravity/mcp_config.json`) | edit the file. Whether `agy mcp add` exists is unconfirmed | `~/.gemini/GEMINI.md` | `SessionStart` in `~/.gemini/config/hooks.json`, `injectSteps` |
| pi | `~/.pi/agent/mcp.json` › `mcpServers` (built-in `builtin:mcp` extension) | edit the file (also `pi mcp add`) | `~/.pi/agent/AGENTS.md` (also `APPEND_SYSTEM.md`) | TS extension: `before_agent_start` |

## Launch commands for agents new to the registry

- **Hermes:**
  - Install: `curl -fsSL https://hermes-agent.nousresearch.com/install.sh | bash`.
  - Interactive: `hermes`. With a first message: `hermes chat -q "<prompt>"`, which stays open on a terminal.
    One-shot: `-Q` / `--oneshot`.
  - Skills: `~/.hermes/skills/`.
- **OpenClaw:**
  - Install: `curl -fsSL https://openclaw.ai/install.sh | bash`, then `openclaw onboard --install-daemon`.
  - Interactive: `openclaw tui`. With a message: `openclaw agent --message "<prompt>"`.
  - Skills: `~/.openclaw/skills`.
- **`agy`:**
  - Install: `curl -fsSL https://antigravity.google/cli/install.sh | bash` (to `~/.local/bin`).
  - Skills: the official docs say `~/.gemini/antigravity-cli/skills/`. Summon's registry still uses `~/.gemini/config/skills`
    (also cited by Omarchy), and the two sources disagree.
- **pi:**
  - The repo moved to `github.com/earendil-works/pi`.
  - Skills: the docs name `~/.agents/skills/`. The registry's `~/.pi/agent/skills` is not in the docs.

## Sources

- Claude Code: https://code.claude.com/docs/en/mcp.md
- Codex: https://developers.openai.com/codex/mcp and /codex/guides/agents-md and /codex/hooks
- Cursor: https://cursor.com/docs/context/mcp and /docs/cli/mcp and /docs/agent/hooks
- opencode: https://opencode.ai/docs/mcp-servers/ and /docs/rules/
- Hermes: https://hermes-agent.nousresearch.com/docs/user-guide/features/mcp, /configuration, /features/hooks
- OpenClaw: github.com/openclaw/openclaw `docs/tools/mcp.md`, `docs/concepts/agent-workspace.md`
- Antigravity CLI: https://antigravity.google/docs/mcp/ and /docs/rules/ and /docs/hooks/
- pi: github.com/earendil-works/pi `packages/coding-agent/docs/mcp.md`
