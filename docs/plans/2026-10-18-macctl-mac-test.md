---
type: Report
title: macctl and Summon on a real Mac
description: Results of the first run of macctl and Summon on macOS 26.6.2.
tags: [macctl, summon, testing]
status: done
created: 2026-10-18
---

# macctl and Summon on a real Mac: results (2026-10-18)

Plan: `plans/2026-10-18-readme-plugin-home-mac-test.md`, section 3. Mac: macOS 26.6.2 (25G83), Swift 6.4,
Xcode selected. Branch `test/macctl-on-mac`.

## 0. Backup

`defaults export` of `com.apple.dock`, `com.apple.finder`, `NSGlobalDomain`, `com.apple.screencapture`
and both trackpad domains, plus dark mode (`Dark`) and the wallpaper path, saved to
`~/macctl-backup-20261018-093639/`.

## 1. Build

- macctl: release build and `swift test`, 82 tests pass. Installed to `~/.local/bin/macctl`.
- Summon: release build, `swift test` 39 tests pass, `scripts/bundle.sh` + `scripts/install.sh` install
  `~/Applications/Summon.app` and 9 themes.

## 2. Smoke test: pass

- `doctor`: Automation of System Events granted, snapshots folder writable.
- `list --json`: 19 settings (the plan said 18; `desktop.wallpaper` was added since), every field present.
- `describe` and `get` exit 0 for all 19 ids.
- Exit codes: `unknown_setting` 1, `invalid_value` 1, usage error 64, `snapshot_not_found` 1.

## 3. Every setting: 19 of 19 pass

Per setting: get, `--dry-run` (1 change, nothing written), `set`, read back with `defaults read` /
System Events, `undo`, read back again. All 19 wrote the right native value and undo restored it.
A key that was unset before is deleted again on undo, as designed.

Not done: the human look at the screen per setting, the logout for keyboard settings, and the ⌘⇧4
check for the screenshot folder. `verifiedOn` stays empty until Rohi does that look.

**Bug found and fixed (865dff3):** the previous wallpaper pointed at a file that no longer existed (an
image from a removed Raycast extension). `undo` failed with `invalid_value`, and because it always picks
the newest snapshot, every later `undo` failed too, so a full-profile undo would have been stuck. Undo now
skips a value that can no longer be written, says so in `notes`, and still records the undo. `set` and
`apply` warn up front: "Undo cannot restore the current desktop.wallpaper (no such file)."

## 4. End to end: pass

- `diff profiles/default.json`: 6 changes. `apply --dry-run`, then `apply`: 6 changes, logout note for the
  two keyboard settings.
- `diff` again: empty. Second `apply`: 0 changes, no snapshot.
- `undo`: 6 changes restored, then `no_snapshots`.
- Compared with the backup: every key matches except `com.apple.dock tilesize`, which came back as the
  integer `52` instead of the real `52.0` the Dock had written (macctl writes `-int`). Harmless; reset to
  the original with `defaults write com.apple.dock tilesize -float 52`.

## 5. Themes and wallpapers: pass

- `summon theme set summon-dawn`: light mode and the Dawn wallpaper through macctl, Ghostty, borders and
  Claude Code theme files written. `summon undo-session` restored dark mode and the previous wallpaper.
- `summon theme set summon-night` and `undo-session`: same, pass.
- Known gap: `~/.config` is not a git repo, so `undo-session` leaves the generated theme files and
  `summon theme current` still says the last theme set.

## 6. Dogfood: pass, with skill fixes

Seven plain-language asks to a fresh headless Claude Code session in this repo, one resumed session.

| Ask | What the agent did |
|---|---|
| hide my Dock | `macctl set dock.autohide true`, reported the snapshot. No `--dry-run` first; confirmed with `defaults read`; told the user `macctl undo dock.autohide` (wrong: undo takes a snapshot id). |
| show file extensions | Read the current value, said it was already on, changed nothing. |
| set my wallpaper to Tokyo Night | Did not find Summon's installed `tokyo-night` theme; downloaded an Omarchy image from GitHub with `curl`, then `macctl set desktop.wallpaper`. Warned up front that undo could not restore the old picture. |
| turn on dark mode | Already on, changed nothing. |
| make my key repeat as fast as possible | `macctl apply` of a two-setting profile (1 and 10, the catalog minimums), no `diff` first; mentioned the logout. |
| turn on night shift | Said plainly macctl has no such setting and did not run a raw command. |
| undo that wallpaper change | `macctl undo <snapshot id>`; reported honestly that the old file is gone, and corrected its earlier undo hint. |

Never bypassed macctl for a write, always reported snapshot ids, mentioned the logout. Misses fixed in
the MacSetup skill: always `--dry-run` first, confirm with `macctl get`, `undo` takes a snapshot id, and use
`summon theme` for theme wallpapers instead of downloading.

The old wallpaper path came back between tests: a Raycast extension sets `Loupe.heic` and later deletes
the file, so macctl snapshots a path that soon disappears. Undo's skip-with-note handles it.

## 7. README demos

`tools/record-demos.sh` recorded every transcript empty: the redact step took its Python source from a
heredoc on stdin, so the piped output never reached it. Fixed (099f520), recorded real output
(9557704); the home folder now shows as `~`. No GIF: `vhs` is not installed.

## Other notes

- `summon checkpoint` ids are UTC while macctl snapshot ids are local time.
- `summon path` before `install.sh` prints `~/.local/bin` (the binary's folder), which has no themes.
