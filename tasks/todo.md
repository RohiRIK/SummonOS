# Current plan — SummonOS production readiness

## Requirements
- Review the project and the URLs in its README files.
- Preserve the idea: an original, native macOS layer centered on agents and skills, inspired by Omarchy.
- Assess security, efficiency, reliability, installation, and public release readiness.
- Preserve existing uncommitted work; make scoped changes on an audit branch.

## Audit and proposal (authorized now)
- [x] Read workspace instructions, lessons, existing project context, and relevant skills.
- [x] Inventory components, shipped skills, README links, and current public claims.
- [x] Review security boundaries, recovery, installation, and release tooling with source evidence.
- [x] Review architecture and efficiency, and run non-mutating verification where practical.
- [x] Write a production-readiness assessment with priorities, acceptance criteria, and a staged implementation plan.
- [x] Validate documentation and prepare the concrete plan for confirmation before implementation.

## Implementation (approved 2026-10-20)
- [x] S1/S3: validate theme configuration and preserve foreign skill links, with regression tests.
- [x] S2/D2–D4: fail-closed publishing, exact release provenance, transactional installation and PR checks.
- [x] R2/R3/R5: retryable undo, cross-process settings transactions and display-aware wallpaper recovery.
- [x] R1/R4/R6/R7: honest checkpoints, bounded/cancellable processes, durable tasks/events and crash cursors.
- [x] Document trust/diagnostic boundaries and implement release-safe first-run behavior without resetting existing choices.
- [x] Address the approved code release blockers with regression coverage.
- [x] Update feature/security/install docs and project context to match verified behavior.
- [x] Run the workspace gate and relevant package checks; record runtime/manual gaps.
- [x] Publication authorized by the owner: retest new skills, push all reviewed changes, make GitHub public, verify live CI.

## Skills and publication (approved 2026-10-20)
- [x] Validate and repair the six new design skills and compile their Swift examples.
- [x] Compare skill-guided and baseline responses to realistic design requests.
- [x] Add repeatable skill validation to CI and rerun the project gates.
- [x] Review intended files and reachable history for private data and asset provenance.
- [ ] Commit and push all reviewed workspace changes; make RohiRIK/SummonOS public.
- [ ] Open a PR, verify live GitHub CI, and merge only after all checks pass.
- [ ] Verify public default-branch files and record final results.

## Review
- Detailed results: `docs/plans/2026-10-20-production-readiness.md`; behavior: `docs/security-model.md`.
- Green: Summon 175 Core + 5 CLI tests and full release bundle gate; macctl 94 tests and release build;
  45 distribution fixtures; all four template gates and workspace example; shell/docs/art/workspace/diff checks.
- Xcode General settings previews rendered in light/dark and visually checked. Ad-hoc signature verified;
  artifacts are arm64. Warm command discovery median10.23ms/p9512.69ms (15 samples), not a GUI benchmark.
- Existing/concurrent UI, skills and registry edits preserved; no installation, credentials, publication,
  visibility change or settings mutation performed. No commits/PR made from the mixed working tree.
- Remaining production gates: disposable-account install/upgrade/uninstall and real permissions/agents;
  multi-monitor recovery; real signing/notarization and quarantined download; supported OS/CPU matrix;
  runtime performance and stable update qualification; history/privacy/publication decision.
