---
type: Playbook
title: Uninstall SummonOS
description: "Preview and apply removal of the installed app and commands; projects, configuration, checkpoints and tasks always remain."
tags: [uninstall, removal, data-preservation]
---

# Uninstall SummonOS

`tools/uninstall.sh` removes only the installation entries recorded in a private ownership receipt. Your projects, configuration, themes, checkpoints, logs and scheduled tasks always remain.

## Before you run

The uninstaller takes `~/Applications/.summon-install.lock`, so an installer and uninstaller cannot run at the same time; if the lock exists it reports that an install or uninstall may already be running.

## Preview (default — removes nothing)

```sh
tools/uninstall.sh
```

Lists every entry it would remove and exits without deleting anything. Review the list first.

## Apply

```sh
tools/uninstall.sh --apply
```

Removes each receipt entry whose path, parent directory and fingerprint still match: `~/Applications/Summon.app`, `~/.local/bin/summon`, `~/.local/bin/macctl`, and owned skill symlinks in the agents' skill folders. Changed or unowned entries are reported and kept, and remain in the receipt so the next run retries them.

## The receipt

Removal is driven by `~/Library/Application Support/Summon/install-manifest.json`, written by a successful install. It records each installed path, its parent directory and a SHA-256 fingerprint, and the entire receipt is validated before anything is deleted.

If the receipt is missing or invalid (for example an installation too old to have one), uninstall refuses:

```
Install ownership check failed: No valid install receipt. Reinstall with the current installer before automatic uninstall
```

Install successfully with the current installer first (it records the receipt), then uninstall.

## What is preserved

- Projects in `~/.config/summon/projects.json` and their folders under `~/Summon/Apps/` — folders and any GitHub repo stay
- Configuration and themes under `~/.config/summon/`
- State, activity log, checkpoints and crash history under `~/.local/state/summon/`
- macctl snapshots and journals under `~/Library/Application Support/macctl/`
- Scheduled tasks — remove them first with `summon task remove <id>` if you want them unscheduled

Uninstall is not a data-destruction tool: user files are never touched.

## After removal

Remove `~/.local/bin` from your shell profile if you added it during installation. To install again, run the installer; it replaces the app and commands with rollback and keeps your themes, projects and settings.
