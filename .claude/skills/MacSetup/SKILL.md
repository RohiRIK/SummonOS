---
name: MacSetup
description: "Read, change, and roll back macOS settings with the macctl CLI (Dock, Finder, keyboard, screenshots, dark mode, wallpaper) and apply JSON profiles. USE WHEN asked to configure or set up a Mac, change a system preference, or apply/undo a profile. NOT FOR building macOS apps (use MacAppBuild)."
---

# MacSetup: configure macOS through `macctl`

`macctl` is the one audited path for changing macOS settings. Do not run `defaults write` or
`osascript` yourself for anything the catalog covers: macctl validates values, snapshots old values,
batches Dock/Finder restarts, and can undo.

## Workflow

1. `macctl doctor --json`: OS version and missing permissions. A missing permission has a `fixURL`;
   tell the user to grant it there. Never try to bypass TCC.
2. `macctl list --json` (or `--domain dock`) to discover ids, types, risk, and current values.
   `macctl describe <id> --json` before setting anything unfamiliar. Never guess a defaults key.
3. One change: always run `macctl set <id> <value> --dry-run --json` first, then the same command
   without `--dry-run`.
4. Many changes: write a profile (`{"name", "version", "settings": {id: value}}`), run
   `macctl diff profile.json --json`, show the user the changes, then `macctl apply profile.json --json`.
5. Confirm with `macctl get <id> --json`, not `defaults read`.
6. Report the `snapshotID` from the result. `macctl undo <snapshotID>` reverts it; the argument is a
   snapshot id such as `20261018-120923`, never a setting id. Plain `macctl undo` reverts the newest change.

## Rules

- Exit codes: 0 ok, 1 error, 2 needs permission, 3 needs confirmation (admin risk), 4 unsupported.
- Pass `--yes` only after the user agreed to that specific admin change.
- Results with a `logout` note need a logout to take effect; say so.
- Settings with empty `verifiedOn` are unverified on this macOS version; mention it if a change seems not to apply.
- A wallpaper or look by theme name ("Tokyo Night"): check `summon theme list` first and use
  `summon theme set <slug>` (or an image in `~/.config/summon/themes/<slug>/`). Do not download images.
- A setting macctl lacks: say so and propose adding it to `macctl/Sources/MacCtlCore/Catalog.swift`
  (verified on a real Mac) rather than running a raw command.
