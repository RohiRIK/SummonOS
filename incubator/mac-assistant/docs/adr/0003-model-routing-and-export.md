# ADR 0003: Model routing and cloud export

Status: accepted (2026-10-03) · Revisit: after the Mac profile is known

## Decision

- Provider-neutral `ModelAdapter` (contracts). First adapters: **local = Apple Foundation Models**
  (macOS 26 + Apple Intelligence, checked at runtime), **cloud = Claude (Anthropic Messages API)**.
- The model **proposes**; deterministic code **decides**. Rules turn evidence into `Finding`s; the
  model explains and ranks them in a structured reply whose claims must cite evidence ids. The
  coordinator rejects claims that cite unknown ids. The model never invokes tools directly in
  Phase 1.
- Each task shows its mode (local/cloud). **A local failure never falls back to the cloud**: the
  router returns `localUnavailable(cloudAvailable:)` and the user chooses.
- Cloud export requires a preview: what leaves the Mac (evidence titles, byte count), redactions,
  estimated cost. `.secret` evidence never leaves. `.personal` values (process names, paths) are
  replaced by stable placeholders unless the user approves them in the preview. A per-task cost
  cap stops further calls; an unknown cost is not treated as free.
- API key: Keychain in the app, `ANTHROPIC_API_KEY` for the CLI; never argv, logs, journal, errors.
- Evidence, logs, and app content are untrusted data in prompts, never instructions.

## Consequences

- Without macOS 26 + Apple Intelligence there is no local model. The Mac profile decides whether a
  second local option (for example a local HTTP model server) is worth adding.
- Diagnostics still work with **no model at all**: findings and evidence are useful on their own.
