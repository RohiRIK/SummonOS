---
type: Playbook
title: Getting started
description: "Install SummonOS, choose an agent, review permissions and connect Mac context safely."
tags: [installation, onboarding, agents, updates]
---

# Getting started

<div class="summon-install-risk" markdown="1">

!!! warning "Experimental software — your responsibility"
    SummonOS is not production-qualified or guaranteed secure. Safeguards are incomplete and security work
    is ongoing. Read the [risk and responsibility disclaimer](disclaimer.md) before installing or connecting
    an agent. Use it at your own risk, with independent backups and only the permissions you accept.

</div>

## Requirements

- **macOS 15 or newer.** Liquid Glass is used only on macOS 26 and later; older systems use native materials.
- An installed coding agent and any account/login that agent requires. SummonOS does not provide the model.
- **Downloaded installs and updates in this candidate:** a recent GitHub CLI (`gh`) with `gh attestation verify`
  and working GitHub access. Install it with your package manager (for example, `brew install gh`);
  use `gh auth login` if needed. Missing or invalid provenance stops installation before unpacking.
  Source builds are a separate trust choice. Older releases do not gain these checks retroactively.
- Internet access for downloading releases, connecting to model services and installing tools. Local context,
  the panel and local settings operations do not require a cloud service.
- **Source builds only:** Git, Swift 6 and Python 3 for current staging. Use selected Xcode for the full
  build/test flow and App Intents metadata. The bundler can omit Siri/Shortcuts actions with Command Line Tools
  alone; that is not equivalent to a fully qualified app build. Packaged releases do not need Xcode.

Read the [status page](status.md) before treating development features as available in a downloaded release.

## Install the preview

```sh
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash
```

The remote installer selects the newest numbered GitHub release, including prereleases but excluding `edge`,
verifies the archive against `SHA256SUMS` and signed GitHub build provenance, installs it, and runs `summon doctor`. If no release is selectable
(including when GitHub is unreachable), it attempts a source build instead. Review the installer before
executing it if your policy forbids piping downloads directly to a shell.

| Installed item | Location |
|---|---|
| Menu bar app | `~/Applications/Summon.app` |
| Commands | `~/.local/bin/summon`, `~/.local/bin/macctl` |
| Themes and agent configuration | `~/.config/summon/` |
| Events, logs and recovery state | `~/.local/state/summon/` |
| Your private app projects | `~/Summon/Apps/` |

If `summon` is not found, add `~/.local/bin` to your shell's `PATH` and open a new terminal:

```sh
export PATH="$HOME/.local/bin:$PATH"
summon version
summon doctor
open "$HOME/Applications/Summon.app"
```

The app's welcome flow helps you select an agent, check its login and configure Accessibility. You can reopen
it from Settings. Preview releases are ad-hoc signed, not notarized. For a browser-downloaded archive,
macOS may require **System Settings › Privacy & Security › Open Anyway**; see [troubleshooting](troubleshooting.md).

## Choose and connect an agent

First inspect what is installed:

```sh
summon agents
```

For example, if Claude Code is installed:

```sh
summon default agent claude
summon connect claude --dry-run
summon connect claude
```

With no agent argument, `summon connect` considers all supported connection targets. It registers MCP where
supported and writes a marked instruction block; supported clients also receive session hooks. Existing files
are backed up. Restart or reload the agent so it reads the new configuration.

The launchable agent registry and the connection targets are different lists. Consult the
[agent reference](features.md#summon-the-agent) and [connection research](research/2026-10-25-agent-mcp-configs.md),
not an assumed one-to-one mapping. Pi uses instructions/skills rather than a native MCP registration.

To preview removal and then remove only Summon's integration:

```sh
summon disconnect claude --dry-run
summon disconnect claude
```

Disconnecting is not uninstalling the app and does not undo work the agent performed.

## Review authority and context

In **Settings › General**, review **Agent execution**. New installations retain the agent's own approval
controls. Existing configured installations can retain unattended execution; inspect rather than assume.

In **Settings › Agents**, choose which context fields are shared. The CLI exposes the same visibility choices:

```sh
summon context fields
summon context hide selected-text
summon context hide browser-page
summon context
```

Selected text/window titles use Accessibility when already granted; browser and Finder integration can require
Automation permission for each target app. Denied permissions omit those fields rather than granting them.

A checkpoint covers supported settings and successfully captured config, not every command an agent can run.
The [security and recovery model](security-model.md) is the recovery contract.

## First actions

- **⌃⌥Space** opens the searchable panel; Escape dismisses it.
- **⌃⌥⌘A** opens the default agent with permitted screen context and asks it to wait for your question.
- **Settings… / ⌘,** opens preferences separately from the panel.
- **Activity** shows sessions and recorded task outcomes.
- **Updates** opens the dedicated update window; installing is an explicit action.

For an inspection-only CLI tour:

```sh
summon context
summon checkpoint list
summon theme list
summon commands --json
macctl list
```

Applying a theme changes the Mac and supported tool configuration. `summon theme set <slug>` prints its
checkpoint undo command. Review any checkpoint warnings; they indicate recovery coverage may be incomplete.

## Installation options

Pass remote-installer options after `bash -s --`:

```sh
curl -fsSL https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh | bash -s -- --version v0.2.5
```

| Option | Behavior |
|---|---|
| `--version vX.Y.Z` | Install a particular numbered release. |
| `--channel stable` | Default remote selection: newest numbered release, including previews; not a production certification. |
| `--channel edge` | Install the separately published rolling `edge` artifact; not necessarily the newest branch or tag. |
| `--from-source` | Build source; a remote run uses `SUMMONOS_HOME` and `SUMMONOS_REF` (default `main`). |
| `--connect` | Run `summon connect` after installation without asking. |
| `--yes` | Disable prompts; does not imply `--connect`. |

`--channel edge` cannot be combined with `--version` or `--from-source`. Running `./install.sh` inside a source
checkout builds **that checkout**, unless a release/edge option explicitly selects a package.

### Update an existing installation

```sh
summon update --check
summon update
```

The app checks at launch and daily when enabled. Current builds open the Updates window for installation and
relaunch the app afterward. A CLI install asks you to restart the app. In 0.2.0, use the CLI because the
panel's update row does not work; on 0.1.x, rerun the installer once.

An explicit `summon update --channel edge` remembers that channel when installing. Adding `--check` only
checks it and does not change the saved channel. Switch back with `summon update --channel stable`.
Custom themes, projects and settings are preserved, but ad-hoc updates can require Accessibility reauthorization.

## Next

[Feature reference](features.md) · [macctl guide](../macctl/README.md) · [Configuration & state](configuration.md) · [Uninstall SummonOS](uninstall.md) ·
[Troubleshooting](troubleshooting.md) · [Build native apps](workflow.md)
