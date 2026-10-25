---
type: Playbook
title: Install SummonOS (for an AI agent)
description: "Step-by-step install, check and report instructions a coding agent follows to install SummonOS on a Mac."
tags: [install, agents]
---

# Install SummonOS (instructions for an AI agent)

You are a coding agent (Claude Code, Codex, OpenCode, Cursor, or similar) running on the user's Mac, and the
user asked you to install SummonOS. Follow these steps in order. Stop and tell the user if a step fails;
do not work around a failure by changing system settings yourself.

## 1. Check the Mac

Run these and read the output:

```sh
sw_vers -productVersion      # needs 15 or newer
```

- macOS older than 15: stop and tell the user SummonOS needs macOS 15+.
- The default install downloads a release and needs no Xcode. Only a source build (`--from-source`, or no
  release published yet) needs Swift 6 and git: check `swift --version` and `git --version` then. No Swift, or
  Swift older than 6: tell the user to install or update Xcode (or run `xcode-select --install`), then stop.
  Do not install Xcode yourself.

## 2. Install

```sh
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
```

The script downloads the newest SummonOS release from GitHub (a universal zip; releases are ad-hoc signed
previews, not notarized), checks it against the release's `SHA256SUMS` and refuses on a mismatch. It installs
`Summon.app` into `~/Applications`, links `summon` and `macctl` into `~/.local/bin`, and links Summon's skills into
each agent's skill folder while preserving foreign links. If no release is published yet, it says so and builds
from source instead: it clones SummonOS into `~/.summonos` and builds `macctl` and Summon (a few minutes the first
time). Options go after `bash -s --`: `--from-source` always builds, `--version vX.Y.Z` installs that release,
`--channel edge` installs the rolling build of the newest green `main` (only when the user asks for it). Both executables
are staged before replacement, with rollback on initialization failure. Configuration added during a
failed upgrade is retained. A nonzero health check means setup still needs attention.

If the user already has a checkout, run `./install.sh` from its root instead (it builds that checkout).

**Already installed?** Update instead: `summon update --check` reports whether a newer build exists, and
`summon update --yes` downloads it, verifies the checksum, installs it with rollback and runs `summon doctor`.
`summon update --channel edge --yes` switches to the edge channel (remembered for later updates); `--channel stable`
switches back.

Run this way the script has no terminal to ask on, so it does not run `summon connect`; step 3 covers it.

## 3. Make it usable

1. If `~/.local/bin` is not on `PATH`, add it to the user's shell profile (`~/.zshrc` on a default Mac):
   `export PATH="$HOME/.local/bin:$PATH"`. Tell the user you did.
2. Set yourself as Summon's default agent, using your own name from this list:
   `claude`, `codex`, `opencode`, `copilot`, `cursor`, `agy`, `pi`, `grok`.
   ```sh
   summon default agent <your-name>
   ```
3. Open the menu app: `open ~/Applications/Summon.app`.
4. Ask the user whether to connect their coding agents to this Mac. `summon connect` adds the summon MCP server
   and a short "This Mac" note to every installed agent (Claude Code, Codex, Cursor, OpenCode, Hermes, OpenClaw,
   Antigravity CLI, Pi) and backs up each file first. Show what would change with `summon connect --dry-run`, and
   run `summon connect` only if the user says yes. Skip this step if `summon commands` has no `connect`.
5. Keep `summon default execution normal` for a new installation unless the user selects unattended
   execution. Existing configured installs retain their prior mode. Explain the authority and scoped
   recovery in [the security model](security-model.md); do not infer approval to bypass controls.

## 4. Verify and report

```sh
summon doctor
macctl doctor
```

Tell the user, in a few lines:

- what was installed and where,
- anything `summon doctor` or `macctl doctor` reports as missing, with the exact fix it suggests
  (macOS permissions such as Automation or Accessibility can only be granted by the user, in System Settings),
- how to start: press ⌃⌥Space for Summon Menu, or run `summon` in a terminal.

## Rules while you do this

- Do not run anything with `sudo`.
- Do not change macOS settings during the install. After it, change them only through `macctl`, which
  snapshots each change so `macctl undo` can reverse it.
- Do not create GitHub repositories or publish anything.
