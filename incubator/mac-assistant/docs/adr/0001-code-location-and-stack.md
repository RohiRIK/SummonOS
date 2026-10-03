# ADR 0001: Code location and stack

Status: accepted (2026-10-03) · Revisit: when the dev repo exists

## Context

Workspace rule: each plugin is its own private `<name>-dev` repo under `plugins/<name>/` (gitignored
here). The kickoff ran in a cloud session that can push only to `macos-plugins` and was not allowed
to attach or create other repos. The audit found no existing assistant code to reuse or wrap.

## Decision

- Incubate at `incubator/mac-assistant/` in `macos-plugins`, on branch `feat/mac-assistant`.
- Move it to `RohiRIK/mac-assistant-dev` once someone with repo access is available, keeping history:
  ```bash
  git subtree split --prefix=incubator/mac-assistant -b mac-assistant-export
  gh repo create mac-assistant-dev --private
  git push git@github.com:RohiRIK/mac-assistant-dev.git mac-assistant-export:main
  git clone git@github.com:RohiRIK/mac-assistant-dev.git plugins/mac-assistant
  git rm -r incubator/mac-assistant   # in the workspace, after the dev repo is confirmed
  ```
- Never run `tools/publish-public.sh` or `tools/release.sh` on the incubator: `git archive` would
  export the whole workspace.
- Stack: Swift 6 strict concurrency, SwiftPM, no third-party dependencies, minimum macOS 15
  (workspace stack). macOS 26 features (Foundation Models, Liquid Glass) sit behind `#available`.
- `MacAssistantCore` and the CLI build on **Linux too** (Foundation + SQLite only), so logic and
  tests run in cloud sessions. Anything macOS-only lives in `#if os(macOS)` / `#if canImport(...)` or
  in the macOS-only UI and app targets.

## Consequences

- The cross-platform rule excludes CryptoKit, so Core has its own SHA-256, verified against the NIST vectors.
- Parsers for macOS command output are tested on Linux with synthetic fixtures; real formats are
  confirmed on the Mac with `scripts/capture-health-fixtures.sh`.
