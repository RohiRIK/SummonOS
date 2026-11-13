---
type: Playbook
title: Troubleshooting
description: "Diagnose installation, agent connection, permissions, updates, inventory and theme problems without discarding user state."
tags: [troubleshooting, permissions, agents, recovery, themes]
---

# Troubleshooting

## Start with read-only diagnostics

```sh
summon version
summon doctor
macctl doctor
```

`summon doctor` exits nonzero for failed checks; warnings alone do not fail it. A failure after installation
can mean the files were installed but the resulting setup still needs attention. Read the named check rather
than assuming the installer rolled back.

For a report, collect a debug bundle:

```sh
summon debug --since 1h
```

The command prints the saved private file's path. Redaction is best-effort: inspect it before sharing.
**Do not post tokens, prompts, real network identifiers or raw private logs.** Report vulnerabilities through
[private security reporting](../SECURITY.md), not a public issue.

## The command is not found

The installer puts commands in `~/.local/bin`. Add it to your shell configuration, then open a new terminal:

```sh
export PATH="$HOME/.local/bin:$PATH"
command -v summon
command -v macctl
```

If the shell and app find different agent copies, inspect `summon agents` and `summon doctor`. Summon follows
PATH order and includes common user install folders; stale Homebrew/npm/bun/vendor copies can still differ.
Do not delete installations until you know which one your shell is using.

## macOS blocks the downloaded app

Preview releases are ad-hoc signed and not notarized. Browser-downloaded archives receive quarantine metadata;
use **System Settings › Privacy & Security › Open Anyway** if you trust the release source. This is different
from Accessibility approval. Do not disable Gatekeeper globally.

The candidate remote installer and updater verify both `SHA256SUMS` and signed GitHub build provenance
before unpacking. A checksum, provenance or signature failure is a reason to stop, not bypass verification.
Check `gh --version`, `gh attestation verify --help`, `gh auth status` and network access; use a recent
GitHub CLI and authenticate if required. Missing attestations on an older release also fail closed.
Check the [release source](https://github.com/RohiRIK/SummonOS/releases) and retry only after resolving the
reported cause. Do not fall back to source merely to bypass failed release verification.
See [distribution trust](security-model.md#distribution) for the candidate versus older-release distinction.

## Selected text or window titles do not reach the agent

1. Open **Summon Settings › General** and inspect the Accessibility status.
2. In **System Settings › Privacy & Security › Accessibility**, enable Summon. If it already appears enabled
   after an update, turn it off and on again; ad-hoc builds can invalidate the effective grant.
3. Check **Settings › Agents** or `summon context fields` for fields you deliberately hid.
4. Try the agent hotkey while the intended app is still frontmost.

Browser-page and Finder selection integration use separate **Automation** grants. A denied grant omits that
field. Accessibility, Automation and Screen Recording are distinct permissions; one does not prove another.
Normal context capture does not need a screen recording just to read selected text.

## The agent does not see Summon's MCP server

```sh
summon connect claude --dry-run
```

Replace `claude` with the supported target you use. Check whether it is reported as not installed, connected,
or failed. Run the real connection command only after reviewing the proposed edits, then restart/reload the
client. The [connection guide](getting-started.md#choose-and-connect-an-agent) explains backups and disconnect.

A launchable agent is not necessarily a native MCP client. Pi uses the instructions/skills path. Consult
`summon commands --json` or the
[feature reference](features.md) for the installed version's available commands.

## The panel or a hotkey does not work

```sh
open "$HOME/Applications/Summon.app"
summon panel
```

If the CLI opens the panel but the shortcut does not, inspect the hotkey health reported by `summon doctor`
and check for a conflicting macOS/application shortcut. If the menu bar icon is hidden, use the CLI/URL entry
point to reach the app rather than resetting all preferences.

The panel is nonactivating and preserves the previous app's focus. Use **Activity**, **Updates** and the
separate **Settings** window for their respective tasks; they are not subpanels containing every preference.

## Ask Agent does nothing

Ask Agent opens your default agent in Ghostty or Terminal through AppleScript, so macOS must allow Summon to
control that terminal. Summon preview builds are ad-hoc signed, so after an update or on a new Mac macOS can ask
again, or keep an old refusal.

```sh
summon doctor                    # default agent installed, terminal chosen
summon agent prompt "hello"      # shows the real launch error in this terminal
```

1. Open System Settings › Privacy & Security › Automation › Summon and turn on Ghostty (or Terminal).
2. If Summon is not listed, reset its Automation answers, then use Ask Agent again and click **Allow**:
   `tccutil reset AppleEvents local.macplugins.summon`
3. If a permission dialog is open behind other windows, answer it. Ask Agent waits for it.

After the next release (#126), a failed launch posts an "Ask Agent could not start" notification, Activity logs
"Could not open <agent>" with the fix, and Settings › health flags a refused Automation permission.

## Updates fail or the update row does nothing

- **0.2.0:** run `summon update` once; 0.2.1 fixes the panel action.
- **0.1.x:** rerun the installer; it predates self-update.
- **Current builds:** `summon update --check` reports the installed and selected-channel versions without
  installing. A CLI update requires restarting Summon.app afterward.
- GitHub connectivity/rate limits can stop release discovery. The updater can fall back to an authenticated
  `gh` when available; the shell installer has its own release lookup.
- In the Updates window, a failed row offers **Fix with AI**. Password-required updates can need the provided
  terminal route. Inspect the error before giving an agent permission to repair it.

The `edge` artifact is independently published; its existence does not guarantee it is newer than the latest
numbered prerelease or contains the current branch. See [channels](getting-started.md#installation-options).

## My Apps says an item needs attention

**Development checkout behavior:** panel and Settings share six inventory categories. Repairs and review
recommendations are separate. A missing referenced file or unusable project is a repair defect; optional art,
hue suggestions and readability findings are recommendations for review, not permission to redesign a palette.

```sh
summon fix --apps
```

This launches the default agent for actual inventory repair defects, with a checkpoint; recommendations are
excluded. General `summon fix` covers Mac diagnostic issues and visible crashes instead. Neither is read-only.
See [release status](status.md) before expecting these newer distinctions in v0.2.4.

## A theme is missing or looks wrong

```sh
summon theme list
summon theme current
summon theme check <slug>
```

`<slug>` is a placeholder for your theme's slug. `theme check` validates the file and reports contrast/color
findings without modifying the palette. An unreadable or malformed `theme.json` can be skipped by `theme list`;
a missing referenced wallpaper remains a defect.

A preview is not an applied theme. Development builds synchronize the active palette across Summon's chrome,
panel actions and Settings. The macOS accent is a separate native setting. Finder folders set to **Automatic**
can follow it; folders with custom colors remain independent. Palette contrast advice does not silently rewrite
your installed custom theme.

## Undo does not restore everything

```sh
summon checkpoint list
summon checkpoint undo --dry-run
```

Inspect capture problems and the plan before applying undo. Recovery covers supported macctl changes and
successfully captured config; it cannot reverse arbitrary agent file edits, cloud actions or commands that
bypassed these mechanisms. Theme-created paths have explicit tracking and safety checks; user-added content
inside a created folder is not blindly deleted.

For a low-level macctl snapshot, use the [macctl recovery guide](../macctl/README.md). Do not remove journals,
checkpoints or locks to hide an error; retain the evidence and report the failed operation.
