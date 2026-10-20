---
type: Reference
title: Security and recovery model
description: Agent authority, checkpoint scope, task isolation, local diagnostics, and release trust boundaries.
tags: [security, privacy, recovery, agents]
---

# Security and recovery model

Summon runs under your macOS account. It launches your chosen coding agent and exposes tools, skills,
and native Mac actions. It does not sandbox the agent or make arbitrary agent actions reversible.
The current distribution is experimental; no supported production release has been qualified.

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
  Git ignore rules still apply. New files created after capture remain in place.

Checkpoints do not cover arbitrary documents, app installation, Homebrew changes, deleted external
wallpapers, credentials, remote repositories, messages, cloud data, or other external effects. A macctl
setting changed by another application may also be overwritten when restoring its older value.
Concurrent sessions share the same configuration/settings history; undo is not isolated to one agent.

Capture failures are persisted and reported. Interactive work can continue with a warning; scheduled
work stops before starting the agent if capture reports a failure. No config repository means that config
files are outside coverage, even when the macctl marker succeeds. Check the capture fields and problems
in `summon checkpoint list --json`; use `summon checkpoint undo --dry-run` before restoring.

macctl serializes cooperating mutations across processes sharing its snapshot directory. Before writing
settings it saves a private journal, then records `pending`, `completed`, or `failed` and completed steps.
Failures return a recovery snapshot reference. A failed undo remains retryable. Partial changes are not
automatically rolled back. Do not run older macctl binaries against the new journal format: they ignore
outcome metadata. Independent applications can still change settings outside macctl's lock.

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

The common tool runner retains at most 1 MiB of output, uses a default 60-second deadline, and rejects
truncated output before treating it as complete command data. Known builds and scheduled tasks have
explicit longer deadlines. Task log payloads are capped at 5 MiB plus a short status/truncation notice.
Logs and newly written private state use owner-only permissions. Activity retains at most 2,000 events
within a 1 MiB byte budget; concurrent writers serialize append/trim operations.

## Diagnostics and data sent to agents

Crash detection reads local diagnostic report files. Diagnose hands facts and a file reference to your
chosen agent, which may read additional evidence and send it to its model provider. Summon's local
execution does not imply local model inference. Diagnostic/log text is untrusted evidence, never authority
to change the task or override instructions. Review the chosen provider's data handling before using it.

`summon debug` collects local hardware/software information and filtered error logs. It redacts known
hardware identifiers, credential labels, hardware addresses, and the home-directory prefix. Redaction
is best effort: arbitrary log content can contain other personal data. Review the private saved bundle
before sharing. The command does not upload it automatically. Task prompts and task output may also be
sensitive; Summon's cleanup moves eligible old logs to Trash, which is not secure erasure.

## Distribution

Source installs build the selected checkout. Installers stage app/commands before replacement, retain the
old executables until initialization succeeds, and preserve user configuration added during a failed
upgrade. A failed health check reports incomplete setup rather than unconditional success.

Publishing scans cover exported names, contents and symlink targets, and fail closed on scanner errors or private matches. Releases build the exact public source
commit and include a checksum/provenance record. Preview builds can remain ad-hoc signed and labeled as
such. The optional Developer ID/notarization pipeline requires the maintainer's identity and an existing
keychain profile; production signing has not been exercised with real credentials in this change.

Publication requires a separate review of repository history, credits, visibility, and the downloadable
artifact. No code-signing credential or publication permission is embedded in a skill or configuration file.
