---
type: Playbook
title: Real-Mac acceptance checklist
description: "Record the exact candidate, then check installation, permissions, connection, native UI and safe recovery on a real Mac."
tags: [acceptance, macos, checklist, installation]
---

# Real-Mac acceptance checklist

**Not run yet.** Rohi runs this on his Mac. Hosted CI does not prove the real installation or interface works.
Keep personal logs and screenshots private; report only redacted results.

## Identify what you are testing

Record: macOS version and architecture; source commit; build version/revision from About;
installation method; existing versus fresh configuration; chosen agent and its version.
Mark each check **PASS / FAIL / BLOCKED / NOT RUN**, with the actual result. A skipped check is not a pass.

**Do not install moving `main` or the latest public release and call that this candidate.** Before a new
archive exists, use a reviewed source checkout pinned to the integration candidate's full commit:

```sh
git rev-parse HEAD
git status --short
sw_vers -productVersion
uname -m
./install.sh
```

Run these from that checkout's root, only after reviewing replacement of your existing app. Source builds
need Git, Swift 6, Python 3 and selected Xcode for full App Intents metadata. The base `VERSION` can still be
0.2.5; it does not identify the candidate. If there is no pinned source checkout or matching packaged
candidate, mark installation **BLOCKED**, not passed. See [release preparation](release-candidate.md).

## Main checks

- [ ] **Install and identity.** The exact candidate installs into `~/Applications/Summon.app` and provides
  `~/.local/bin/summon` / `macctl`. Run `summon version`, `summon doctor`, `macctl doctor`; record warnings
  separately from failures. About identifies the expected revision. Stop on failed installation or identity.
- [ ] **Welcome and panel.** Open the app. New configurations show the four-step welcome flow; existing ones
  can use Settings → General → Show Welcome Again. Skip/close remains usable. `⌃⌥Space` opens the searchable
  panel, typing filters entries, Escape closes it, and Settings… / `⌘,` opens a separate preferences window.
- [ ] **Permissions and context.** Review execution mode (`normal` for a fresh setup) and `summon context fields`.
  Test initially without Accessibility/Automation, then grant only the permissions you choose in System Settings.
  Denied fields are absent; allowed selected text reaches the agent hotkey. Hide `selected-text` and repeat:
  it must no longer reach the agent. Restore only your chosen sharing settings.
- [ ] **Connect one agent.** Choose an installed, logged-in agent. Run `summon connect <id> --dry-run`, review
  its proposed changes, then approve `summon connect <id>`. Restart that client and ask for an inspection-only
  Mac context query. For MCP clients verify tools/resource discovery; Pi uses instructions/skills instead.
  `⌃⌥⌘A` starts the selected agent with only permitted context. Do not approve unrelated settings changes.
- [ ] **Activity and accessibility.** Open Activity and Updates. Navigate the panel, Settings and welcome flow
  by keyboard; test VoiceOver and Reduce Transparency, recording focus/label/contrast failures. Do not infer
  native notifications from Activity alone. No unattended task or repository creation is required here.
- [ ] **Recovery preview.** Run `summon checkpoint list` and `summon checkpoint undo --dry-run`; review scope
  without restoring personal state. To test actual undo, use a disposable Mac account and one recorded,
  supported macctl setting: capture its value, make a checkpoint, change only that setting, undo, and compare.
  Do not promise full-machine or arbitrary agent-action recovery.

## Separate gates: packaged update and removal

- [ ] **Downloaded provenance.** Once a matching archive exists, require its `SHA256SUMS` and signed build
  provenance before unpacking. A recent `gh` with working GitHub access is required. Missing/invalid provenance
  must stop the candidate installer/updater. Source installation above does not exercise this path.
- [ ] **Update end to end.** `summon update --check` is read-only. Actual update acceptance requires an explicitly
  approved, newer published candidate on the selected channel, not today's older public release. Otherwise
  mark **BLOCKED**. Record starting/ending build identity, restart, health checks and preservation of settings,
  themes and projects. Failure/rollback tests belong in a disposable account, never by corrupting live files.
- [ ] **Removal preview.** From the same source checkout run `tools/uninstall.sh`; review the ownership receipt
  and proposed list. Preview must remove nothing. Actual `--apply` is optional and requires a disposable test
  account or explicit owner consent to remove installed binaries; it is not part of routine personal-Mac testing.
  Modified/unowned files and personal configuration/projects/logs/tasks must remain. See [uninstall](uninstall.md).

## Report back

Send the candidate revision, Mac version/architecture, each result and the first failing action plus redacted
error text. Never include tokens, selected personal text or raw debug bundles. Passing this checklist does not
close retained-memory, displayed-frame or profiler gates in [status](status.md).

[Installation](getting-started.md) · [Security and recovery](security-model.md) · [Release preparation](release-candidate.md)
