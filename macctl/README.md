<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../docs/assets/macctl-logo-dark.svg">
    <img alt="macctl" src="../docs/assets/macctl-logo-light.svg" height="96">
  </picture>
</p>

<p align="center">
  <img alt="Swift 6 | macOS 15+" src="../docs/assets/pill-swift-macos.svg">
</p>

# macctl

A command-line tool that reads, sets, diffs, applies and undoes macOS settings. It is built for AI
agents, and people can use it too. Every setting comes from a typed catalog, so an agent never has to
guess a `defaults` key. Every change saves a snapshot first, and `macctl undo` restores it.

<p align="center">
  <img alt="macctl diff profiles/default.json lists six settings that would change, from their current value to the profile's value" src="../docs/assets/demo/macctl-diff.svg" width="100%">
</p>

<sub>Terminal output on this page was recorded on macOS 26.6.2 by `tools/record-demos.sh` (read-only
commands; the home folder is shown as `~`).</sub>

## Why

- **A typed catalog.** Each setting has an id, a type (`bool`, `int 16...128`, `left|bottom|right`), a
  risk tier, the permissions it needs and its side effects. `describe` shows all of it before you `set`.
- **Snapshots and undo.** Every write saves the old values first. `macctl undo` puts them back, one
  change at a time, including keys that were unset before.
- **JSON for agents.** `--json`, or any pipe, gives exactly one object per run with stable error codes
  and exit codes, so an agent can act on the result without parsing text.

Requires macOS 15 or later.

## Install

```sh
swift build -c release
cp .build/release/macctl /usr/local/bin/   # or anywhere on your PATH
```

## Quick tour

**1. Check permissions.** `doctor` shows the macOS version, which permissions are granted, and a System
Settings link for each missing one.

<img alt="macctl doctor: macOS 26.6.2, Automation of System Events granted, snapshots folder writable" src="../docs/assets/demo/macctl-doctor.svg" width="100%">

**2. Look before you write.** `diff` (above) shows what a profile would change. `--dry-run` does the
same for `set` and `apply`. Neither writes anything.

<img alt="macctl set dock.autohide true --dry-run: one change would be made, nothing written" src="../docs/assets/demo/macctl-dry-run.svg" width="100%">

**3. Change, then undo.** A real `set` or `apply` prints the snapshot id it saved; `undo` restores it.

```sh
macctl set dock.autohide true    # Applied 1 change. Snapshot <id>. Revert with: macctl undo <id>
macctl undo                      # restores the newest change that was not undone yet
```

## Commands

| Command | What it does |
|---|---|
| `macctl doctor` | macOS version, which permissions are granted, and a System Settings link for each missing one |
| `macctl list [--domain <d>]` | every setting with its type, risk and current value |
| `macctl describe <id>` | full schema of one setting (read this before `set`) |
| `macctl get <id>...` | current value of one or more settings |
| `macctl set <id> <value> [--dry-run] [--yes]` | change one setting |
| `macctl diff <profile.json>` | what `apply` would change; writes nothing |
| `macctl apply <profile.json> [--dry-run] [--yes] [--only <domain>]` | make the Mac match a profile |
| `macctl snapshot list` | snapshots, newest first (`macctl snapshot` alone does the same) |
| `macctl snapshot show <id>` | the old values one snapshot holds |
| `macctl undo [<id>]` | restore a snapshot (the newest when no id is given) |

Every command takes `--json`. Run `macctl <command> --help` for details. The full catalog is in
[`docs/settings.md`](docs/settings.md).

<img alt="macctl list --domain dock: six Dock settings with type, risk and current value" src="../docs/assets/demo/macctl-list.svg" width="100%">

<img alt="macctl describe dock.tilesize: id, summary, type, risk, current and default value, backend, permissions, side effects" src="../docs/assets/demo/macctl-describe.svg" width="100%">

### Examples

```sh
macctl doctor
macctl list --domain dock
macctl describe dock.tilesize
macctl get dock.autohide dock.tilesize
macctl set dock.autohide true --dry-run
macctl set dock.autohide true
macctl set desktop.wallpaper ~/Pictures/wall.jpg   # every screen; undo restores the old picture
macctl diff profiles/default.json
macctl apply profiles/default.json --only finder
macctl snapshot list
macctl snapshot show 20261016-142501
macctl undo
```

A value that starts with `-` needs `--` before it: `macctl set some.setting -- -1`.

### Profiles

A profile is a JSON file of desired values. `apply` is idempotent: it changes only the settings that
differ, and does nothing when the Mac already matches.

```json
{
  "name": "my-mac",
  "version": 1,
  "settings": {
    "dock.autohide": true,
    "dock.tilesize": 40,
    "finder.show-extensions": true,
    "screenshots.location": "~/Pictures/Screenshots"
  }
}
```

`--only dock` applies just the settings whose id starts with `dock.`.

## Reference

### JSON output

Output is JSON when you pass `--json`, or when stdout is not a terminal (a pipe, or an agent's
shell). Each run prints exactly one object, with sorted keys and ISO 8601 dates.

<img alt="macctl get dock.autohide dock.tilesize --json prints one object with command, ok and result" src="../docs/assets/demo/macctl-get-json.svg" width="100%">

Success:

```json
{
  "command" : "get",
  "ok" : true,
  "result" : [
    { "id" : "dock.autohide", "value" : true }
  ]
}
```

Failure (the exit code matches the error):

```json
{
  "command" : "set",
  "error" : {
    "code" : "needs_confirmation",
    "message" : "network.hostname is admin risk; pass --yes to apply."
  },
  "ok" : false
}
```

`result` by command:

- `list`: an array of settings. `describe`: one setting. Each setting has `id`, `domain`, `summary`,
  `type` (`{"kind": "int", "min": 16, "max": 128}`, or `{"kind": "enum", "values": [...]}`), `risk`,
  `permissions` (such as `"automation:com.apple.systemevents"`), `sideEffects` (such as
  `"restart:Dock"` or `"logout"`), `backend`, `verified`, `verifiedOn`, `systemDefault`, `current`, and
  `currentError` when the value could not be read.
- `get`: an array of `{"id", "value"}`; `desktop.wallpaper` reads the main screen's picture path. `value` is `null` when the key is unset and has no known default.
- `diff`: `{"profile", "changes": [{"id", "from", "to"}]}`. A missing `from` means the key is unset.
- `set`, `apply`, `undo`: `{"snapshotID", "changes", "dryRun", "notes"}`.
- `snapshot list`: an array of `{"id", "createdAt", "changeCount", "settings"}`.
- `snapshot show`: `{"id", "createdAt", "changes"}`.
- `doctor`: `{"macOSVersion", "checks": [{"name", "ok", "detail", "fixURL"}]}`.

Error codes: `unknown_setting`, `invalid_value`, `command_failed`, `permission_missing`,
`needs_confirmation`, `unsupported`, `snapshot_not_found`, `no_snapshots`, `invalid_profile`,
`internal_error`.

### Exit codes

| Code | Meaning |
|---|---|
| 0 | ok |
| 1 | error (unknown setting, invalid value, bad profile, a system command failed) |
| 2 | needs a permission; run `macctl doctor` for the System Settings link |
| 3 | needs confirmation; rerun with `--yes` |
| 4 | not supported on this macOS version |

Command-line usage errors (a missing argument) exit with 64 and print usage to stderr.

### Safety

- **Snapshots.** Before writing anything, `set`, `apply` and `undo` save the old values to
  `~/Library/Application Support/macctl/snapshots/`. `macctl undo` restores the newest one;
  `macctl undo <id>` restores a given one. A key that was unset before is deleted again on undo.
- **Dry runs.** `--dry-run` and `diff` show the plan and write nothing.
- **Risk tiers.** Each setting has a risk: `read`, `user` (Dock, Finder, keyboard, appearance: applied
  directly), `admin` and `destructive` (refused with exit code 3 unless you pass `--yes`).
- **Permissions.** macctl checks permissions without triggering a prompt. A missing one stops the
  command with exit code 2 and a link to the right System Settings pane. macOS gives the grant to the
  app that runs macctl (Terminal, iTerm, or your agent's host app).
- **No shell strings.** Values reach `defaults` and `osascript` only as separate arguments, never spliced
  into a shell or AppleScript text.
- **Side effects.** Some settings need Dock or Finder restarted, or a logout. `apply` restarts each
  process once at the end and lists what still needs a logout in `notes`.

## Demos

The terminal cards are rendered from the transcripts in [`docs/demo/`](docs/demo) by
`tools/readme-art.py` (from the repo root). To record real ones on a Mac, with macctl installed:

```sh
brew install vhs          # optional, for docs/demo/demo.gif
tools/record-demos.sh     # runs only read-only commands, scrubs $HOME and tools/private-patterns.txt
```

## License

MIT
