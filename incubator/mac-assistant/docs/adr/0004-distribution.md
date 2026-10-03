# ADR 0004: Distribution

Status: accepted (2026-10-03) · Revisit: before any public release

## Decision

- Phase 1–3: run on the user's own Mac. Ad-hoc signed with a stable designated requirement
  (workspace `bundle.sh` pattern) so TCC grants survive rebuilds.
- Beyond the development Mac: Developer ID signed, hardened runtime, notarized (`MacAppBuild/Release.md`).
- No App Sandbox / Mac App Store edition until the system-management capabilities are proven; then
  evaluate an App Store edition against the actual permission needs.
- Public snapshots only after the move to its own repo (ADR 0001), via `tools/publish-public.sh`.
