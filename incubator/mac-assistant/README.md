# mac-assistant

A native macOS assistant that tells you what is wrong with your Mac, shows the evidence, proposes a
specific change, and checks whether it helped. It runs locally, and you choose a local model
(Apple Foundation Models) or a cloud model (Claude) for each task.

**Status:** Phase 1 (diagnostics foundation). The first milestone, **Mac Health**, works on
read-only evidence. It does not change anything on the Mac yet.

## How it works

```
App / CLI ──► Coordinator ──► Policy broker ──► Typed tools (allowlisted, bounded, read-only for now)
                 │  ▲                │
                 ▼  │                └──► Journal (SQLite, redacted, crash-recoverable)
            Local or cloud model
            (explains findings; cites evidence; never grants permissions)
```

- Every operation goes through one policy broker. It checks the tool, version, input schema, OS,
  permissions, scope, and approval, then rechecks the host right before running.
- There is no "run any command" tool. Only allowlisted executables run, with fixed arguments,
  deadlines, and output caps.
- Nothing leaves the Mac unless you choose cloud mode and approve an export preview showing the
  data, redactions, and cost.

Details: `docs/roadmap.md`, `docs/adr/`, `PROJECT-CONTEXT.md`.

## Build and test

```bash
scripts/test.sh                  # macOS (Xcode or Command Line Tools) or Linux (Swift 6.4)
scripts/mac-profile.sh           # on the Mac: chip, RAM, OS, local-model support
```

Requires Swift 6 and macOS 15 or later. The SwiftUI app arrives with milestone M1-UI.
