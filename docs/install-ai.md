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

This guide describes the checkout's installer behavior. The base version is **0.2.4**, but runtime hardening,
staged build identity and other later branch changes are unreleased. Installing a published tag does not
install this branch; `edge` is opt-in and its published artifact may also lag source. See [status](status.md).

## 1. Check the Mac

Run these and read the output:

```sh
sw_vers -productVersion      # needs 15 or newer
```

- macOS older than 15: stop and tell the user SummonOS needs macOS 15+.
- A downloaded release needs no Xcode. A source build needs Swift 6 and git: check `swift --version` and
  `git --version` if using a checkout, `--from-source`, or the installer's fallback to source. If missing/too
  old, explain `xcode-select --install` or the required Xcode update and stop; do not install Xcode yourself.
- The current source/staged installer also invokes Python 3; check `python3 --version` before that path.
  Full Siri/Shortcuts metadata needs Xcode; a Command Line Tools source build can omit those optional actions.
  The installer's automatic source fallback also occurs when GitHub's release-list request fails, not just
  when no release exists. If that path lacks prerequisites, stop and report rather than installing tools silently.

## 2. Install

```sh
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
```

The default release path selects the **first non-`edge` tag** in GitHub's returned release list, including
prereleases (not the `/releases/latest` API). It verifies the universal archive against `SHA256SUMS` and refuses
missing/mismatched checksums. Published previews can be ad-hoc signed, not notarized; inspect the selected
release's notes rather than assuming production signing. Checksums are integrity checks, not independent
publisher authentication. It installs `Summon.app` into `~/Applications`, links `summon` into `~/.local/bin`,
copies macctl there and links Summon's skills while preserving foreign folders/links.

If the release list is empty or unavailable, the script falls back to cloning/updating `~/.summonos` and
building source (default ref `main`; `SUMMONOS_HOME` and `SUMMONOS_REF` override those choices). An explicit
tag/edge download failure stops rather than falling back. Pass options after `bash -s --`:

| Option | Effect |
|---|---|
| `--from-source` | Build source; a local checkout uses itself |
| `--version vX.Y.Z` | Install the exact numbered tag |
| `--channel stable` | Default non-edge release selection |
| `--channel edge` | Install the currently published rolling asset, only when requested |
| `--yes` | Never prompt; does **not** connect agents |
| `--connect` | Run agent connection after installation; only with the user's approval |

Do not combine `--from-source` with `--version`, or `--channel edge` with either. A checkout defaults to source,
but an explicit `--version` or `--channel edge` still selects a downloaded release. Current installers stage
the app/commands before replacement and roll them back if initialization fails, retaining added configuration.
A subsequent failed `summon doctor` reports incomplete setup; it does not automatically undo the installation.

If the user asked to install an existing checkout, run `./install.sh` from its root (builds its current content;
it does not fetch another branch). Do not choose the checkout merely because it exists if the user requested a release.

**Already installed?** Update instead: `summon update --check` reports whether a newer build exists, and
`summon update --yes` downloads it, verifies the checksum, installs it with rollback and runs `summon doctor`.
`summon update --channel edge --yes` selects the rolling channel; `--channel stable` selects numbered releases.
The updater's stable selection uses the **highest semantic-version tag** in the returned list, including previews,
which differs from the top-level installer's first-non-edge selection. Stable updates only newer versions;
edge installs a different version even if older. `--channel` is remembered except with `--check` (and is saved
before any install prompt). CLI updates require `--yes` without a terminal, and the menu app must be restarted
after a CLI update. Neither channel proves unreleased branch changes were published.

Piped/noninteractive installation does not prompt to connect; without `--connect`, use step 3 for consent.

## 3. Make it usable

1. If `~/.local/bin` is not on `PATH`, add it to the user's shell profile (`~/.zshrc` on a default Mac):
   `export PATH="$HOME/.local/bin:$PATH"`. Tell the user you did.
2. Set yourself as the default agent only if you are in Summon's launch registry. Use your canonical id:
   `claude`, `codex`, `opencode`, `copilot`, `cursor-agent` (alias `cursor`), `agy`, `pi`, `hermes`, `openclaw`,
   or `grok`. Do not substitute another agent if your harness has no launch entry; report that limitation.
   ```sh
   summon default agent <your-name>
   ```
3. Open the menu app: `open ~/Applications/Summon.app`.
4. Ask whether to connect installed coding agents to this Mac. The **eight** automatic targets are Claude Code,
   Codex, Cursor, OpenCode, Hermes, OpenClaw, Antigravity CLI and Pi—not all ten launchable agents. Connect adds
   the MCP server and, where supported, a This Mac note/session hooks. Cursor/Hermes receive no instructions
   note. Summon backs up files it directly edits; vendor `mcp add` commands own their own configuration writes.
   Show `summon connect --dry-run`; run `summon connect` only with approval. Skip if the installed version's
   `summon commands` has no `connect`. The current MCP implementation exposes 11 tools plus `mac://context`.
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
- Do not change macOS settings during installation. Later, use `macctl` and preview its declared recovery
  contract rather than promising every effect is reversible. Checkpoint coverage is limited to supported settings,
  successfully captured config and explicitly recorded theme-created files; see [security and recovery](security-model.md).
- Do not create GitHub repositories or publish anything.
