---
type: Reference
title: Security and recovery model
description: Agent authority, checkpoint scope, task isolation, local diagnostics, and release trust boundaries.
tags: [security, privacy, recovery, agents]
---

# Security and recovery model

Summon runs under your macOS account. It launches your chosen coding agent and exposes tools, skills,
and native Mac actions. It does not sandbox the agent or make arbitrary agent actions reversible.
The current distribution is experimental; no supported production release has been qualified. This page describes
the checkout, including unreleased changes after the **0.2.5** tag. A shared version number does not prove a
published build includes later hardening; see [release/branch status](status.md) and the
[historical runtime audit](plans/2026-11-08-runtime-audit.md#implementation-evidence-and-unverified-acceptance-2026-11-08).

## Agent execution

New installations use **Agent controls** (`summon default execution normal`): Summon leaves the chosen
agent's normal permission and sandbox behavior in place. Some agents have no such controls. The setting
does not add a sandbox, guarantee read-only execution, or change the provider's policies.

**Unattended** (`summon default execution unattended`) uses the registry's bypass flags where supported.
Choose it only for work you authorize the agent to perform with your account's access. Change this in
Settings › General › Agent execution or through the CLI. Existing installations with a configured
default agent retain their previous unattended behavior; an explicit saved choice wins thereafter.

Skills guide behavior and are executable-trust inputs to an agent, not enforced access controls. Summon
preserves foreign skill folders/symlinks and records the exact links it creates. Updates replace Summon's
own selected skill content; selecting all shipped skills also includes skills added by later updates.
Per-agent selections remain available. Hooks, user menu commands, and installed agent plugins run code
under your account; review their sources before enabling them.

## What checkpoint undo covers

- A marker in macctl's settings snapshot history. Undo reverses supported macctl operations after it.
- Existing files captured by Git under `~/.config`, only if it was already a repository and capture succeeded.
  Git ignore rules still apply. Ordinary new files created after capture remain in place.
- Files explicitly recorded as **created by a theme** are removed by checkpoint undo; recorded folders are
  removed only when they contain no unrecorded files. This is not a general new-file tracker. The records live
  in the bounded Activity log, so missing/trimmed creation events remove that cleanup coverage. These recorded
  files are not content-fingerprinted before deletion: later edits to a recorded file do not protect it.
  Existing editor-theme files outside captured `~/.config` (for example under `.vscode`/`.cursor`/`.claude`)
  have no prior-content backup through this mechanism. Theme hooks can have additional uncovered effects.

Checkpoints do not cover arbitrary documents, app installation, Homebrew changes, deleted external
wallpapers, credentials, remote repositories, messages, cloud data, or other external effects. A macctl
setting changed by hand or by another application after macctl wrote it is **not** overwritten on undo: it is
flagged, left as it is, and reported (`partial_restore`); only an explicit `macctl undo <id> --force` overwrites it.
`--force` (on `undo` or `recover`) is never a default and needs an explicit user action: Summon, its menu and
its agent commands never pass it (they run `macctl undo <id> --json` only), and agents must not add it without the
user confirming that the hand-edited keys should be overwritten.
Concurrent sessions share the same configuration/settings history; undo is not isolated to one agent.

Capture failures are persisted and reported. Interactive work can continue with a warning; scheduled
work stops before starting the agent if capture reports a failure. No config repository means that config
files are outside coverage, even when the macctl marker succeeds. Check the capture fields and problems
in `summon checkpoint list --json`; use `summon checkpoint undo --dry-run` before restoring.

macctl serializes cooperating mutations across processes sharing its snapshot directory
([ADR](adr/ADR-macctl-recovery.md)). Each session writes a write-once snapshot header (status `pending`, never
rewritten) and an append-only journal (`journal/<id>.jsonl`, 0600 in a 0700 directory) in which every change's
prior state (absent, explicit with its exact type, or inherited) is fsynced (`F_FULLFSYNC`) before the write.
A failed batch attempts rollback; if rollback itself fails, pending recovery remains and the command reports
failure rather than guaranteeing nothing changed. After a crash, every write refuses with `recovery_pending`
until `macctl recover` rolls the unfinished session back; recover is idempotent. Managed (MDM) keys are refused
(`managed_setting`). Settings marked sensitive keep only a keyed hash (HMAC-SHA256, key in `journal/.key`) and
cannot be restored. Journals never leave the Mac. Do not run older macctl binaries against the new journal
format: they ignore it. Independent applications can still change settings outside macctl's lock.

A corrupt recovery journal can block older overlapping sessions. `recover` can still restore unrelated sessions
before reporting an error, so a failed recovery does not mean no writes occurred. `recover --abandon <id>`
quarantines the unreadable journal and removes its blocker; it does not restore that session's settings.

Wallpaper recovery records images by display UUID. A disconnected display must be reconnected before
its saved image can be restored. Legacy snapshots with one wallpaper retain their historical scalar behavior.
Missing wallpaper files are reported rather than reconstructed from a backup of their contents.

## Scheduled tasks and processes

New tasks save their agent, execution mode, working directory, prompt, and schedule. Use `--execution`
and `--directory` with `summon task add` to choose those explicitly. Existing tasks retain their previous
unattended behavior and legacy default-agent selection. Task IDs cannot escape the log/LaunchAgent folder.
Corrupt task/config stores block mutations and execution; the original bytes remain available for repair.

One invocation of a task runs at a time. Agent failure returns nonzero and records a failure in Activity.
Each run has a 30-minute deadline; termination has a grace period then escalation. Cancellation stops the
invocation's process group. A process that deliberately starts another session, a remote action already
sent, or a process surviving a forced kill of Summon itself is outside this cleanup guarantee.

The common shell runner retains at most **16 MiB** of captured output, uses a default 60-second deadline, and
rejects truncated output before treating it as complete command data. Individual callers can choose smaller
bounds; known builds/downloads and scheduled tasks have explicit longer deadlines. Scheduled runs retain no
duplicate output buffer and write private logs capped at 5 MiB plus a short status/truncation notice.
Logs and newly written private state use owner-only permissions. Activity trims when it exceeds **1,000,000
bytes**, retaining the newest suffix of at most 2,000 events that fits that budget. This is a trim policy,
not an unconditional 2,000-row cap below the threshold; a trim failure is reported separately after a committed
append. Concurrent writers serialize append/trim operations. A task's recorded terminal result is separate
from notification delivery: a failed or timed-out notification does not turn completed work into execution failure.

## Diagnostics and data sent to agents

Crash detection reads local diagnostic report files. Diagnose hands facts and a file reference to your
chosen agent, which may read additional evidence and send it to its model provider. Summon's local
execution does not imply local model inference. Diagnostic/log text is untrusted evidence, never authority
to change the task or override instructions. Review the chosen provider's data handling before using it.

Screen-context prompts can include the frontmost app/window, selected text, supported browser tab and Finder
selection. Selected text/window title require existing Accessibility access; browser/Finder lookups can request
Automation permission. Context visibility controls in Settings › Agents reduce the fields Summon supplies;
they do not prevent an agent with account access from reading those sources independently. `summon connect`
grants configured MCP clients access to 11 tools and `mac://context`; its `confirm: true` field is an assertion
by the client that the user agreed, not a separate native approval dialog or a sandbox boundary.

MCP annotations describe effects, not permissions. Read tools advertise `readOnlyHint: true` and
`destructiveHint: false`; `settings_set`, `settings_undo` and `checkpoint_create` advertise the opposite.
Settings can overwrite state even when journaled, and checkpoint creation can prune retained records.
`openWorldHint: false` describes these tools' local, closed-account scope; a mutation does not itself imply
interaction with external entities. These hints do not replace client approval or existing validation.

`summon debug` collects local hardware/software information and filtered error logs. It redacts known
hardware identifiers, credential labels, hardware addresses, and the home-directory prefix. Redaction
is best effort: arbitrary log content can contain other personal data. Review the private saved bundle
before sharing. The command does not upload it automatically. Task prompts and task output may also be
sensitive; Summon's cleanup moves eligible old logs to Trash, which is not secure erasure.

## Distribution

Source installs build the selected checkout. The default downloaded installer selects the first non-edge
release returned by GitHub, including prereleases; the CLI updater instead chooses the highest semantic-version
tag from its returned list. Neither promises production stability. Edge is opt-in and can lag source.
In this checkout, both the remote installer and CLI/app updater check the downloaded zip against
`SHA256SUMS`, then require cryptographically verified GitHub build provenance **before unpacking or executing
anything from the archive**. The trusted local GitHub CLI (`gh attestation verify`) must validate the exact
archive digest, repository `RohiRIK/SummonOS`, signer workflow `.github/workflows/release.yml`, and GitHub-hosted
runners. Numbered releases must bind to the requested `refs/tags/vX.Y.Z`; edge must bind to `refs/heads/main`.
The edge source ref does not pin to the current main commit: an older legitimate green build can still verify.

This makes a swapped archive plus a matching swapped checksum insufficient without the accepted signing
workflow's provenance. Missing/invalid attestations, a missing/unsupported `gh`, authentication problems and
verification network failures stop installation; there is no unverified-release fallback. Install a recent
`gh` through your package manager (for example, `brew install gh`), use `gh auth login` if required and retry.
Read-only update checks do not require `gh` when anonymous GitHub API access works.

The bootstrap installer itself is still trusted through the selected checkout or GitHub HTTPS download;
provenance does not protect against a compromised authorized build workflow, malicious source, rollback to
an older otherwise valid build or arbitrary actions after installation. Source builds remain a separate trust
choice and do not verify release attestations; automatic source fallback when no release is selectable remains
unchanged. Published older installers/updaters, including v0.2.5, do not gain these checks retroactively.
These checks do not establish Apple Developer ID identity or notarization.

Current build tooling generates compiled identity, `BuildInfo.json` and the bundle plist in an isolated source
stage, without rewriting tracked development version files. Stable/edge metadata requires a clean identified
checkout; development metadata records dirty/unidentified source. Base version, numeric build, revision, channel,
configuration and UTC time identify the candidate; identity checks do not prove its safety or performance.
`scripts/install.sh --verify-only` validates the supplied candidate/signature/packaged command before any live
promotion. It does not initialize user state, replace installed files or run a GUI acceptance test.

Normal installation stages the app/commands, retains originals until initialization succeeds and restores them
on failure; newly added themes/configuration are retained. Incomplete rollback preserves backups and reports
their staging paths for recovery. The later top-level `summon doctor` health check can fail **after** executable
promotion has committed; that reports incomplete setup and does not roll back the committed installation.
Ownership receipts support preview-first removal of unchanged installed files with `tools/uninstall.sh`;
modified/unowned files and user projects/configuration/logs/tasks remain.

Publishing scans cover exported names, contents and symlink targets and fail closed on errors/private matches.
Release workflows build the selected source SHA, verify signatures/architectures/identity and publish checksums;
tagged/edge publication also attests the archive. Ad-hoc previews are not notarized. Developer ID/notarization
is optional and needs maintainer credentials/keychain configuration; the existence of that pipeline is not
evidence that a particular release was notarized. Read its release notes and verify the actual artifact.

Publication requires a separate review of repository history, credits, visibility, and the downloadable
artifact. No code-signing credential or publication permission is embedded in a skill or configuration file.
