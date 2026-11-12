---
type: Playbook
title: Release preparation and gates
description: "Prepare the combined source candidate, distinguish dry-run artifacts from attested releases, and retain explicit Mac and publication gates."
tags: [release, runbook, acceptance, verification]
---

# Release preparation and gates

**Preparation only. No candidate binary has been built in this Linux integration session.**
The combined branch is `integration/release-preparation`, based on main `ce9b765`, with the security,
manual and website UX changes selected together. Record its final full commit before testing or building.
This branch is not merged or deployed. Merging, website deployment and app publication need separate approval.

## Version and proposed release notes

`VERSION` remains **0.2.5**. The latest numbered public release checked on 2026-11-12 is **v0.2.5**,
published 2026-11-11 as a prerelease. **0.2.6 is a proposed next patch version**, not an allocated tag,
version bump, existing binary or release promise. A base version alone cannot identify this candidate.

Proposed next-preview notes, subject to exact-source verification:

- Downloaded installer and CLI/app updater authenticate release provenance before unpacking, in addition to
  checksums. A recent GitHub CLI (`gh`) with working GitHub access is now a dependency for that path.
- MCP tool safety hints match mutating checkpoint/settings behavior; annotations do not enforce consent.
- User manual includes command, configuration and removal references, with candidate trust requirements.
- Website back-to-top positioning avoids the old header-area overlap; native app styling is unchanged.
- `project new` help lists all nine accepted starter kinds.

Older installed updaters do not gain the provenance check retroactively. Source installs are a separate trust
choice. Preview/ad-hoc signing is not Apple Developer ID identity or notarization.

## 1. Prepare and verify source without publication

Use the final clean integration commit; preserve the original author branches and pending manual edit.
Run from the repository root:

```sh
git rev-parse HEAD
git status --short
python3 -m unittest discover -s tools/tests -p 'test_*.py'
tools/check-workspace.sh
python3 tools/docs-site.py build --site-dir "$HOME/Library/Caches/SummonOS/release-docs" --ref <full-candidate-sha>
```

Install `requirements-docs.txt` in an isolated environment before the site build. The builder runs strict
checks, including rendered local links and anchors. Run the shell syntax/lint and privacy gates from
`.github/workflows/swift.yml`, plus independent review, on the same candidate. Local Linux checks do not
replace Swift/macOS builds.

On a Mac with the selected Xcode toolchain, run the package builds/tests from `swift.yml` and the app gate:

```sh
swift build --package-path incubator/summon --build-tests
swift test --package-path incubator/summon --skip-build
swift build --package-path macctl --build-tests
swift test --package-path macctl --skip-build
incubator/summon/scripts/check.sh --report-dir "$HOME/Library/Caches/SummonOS/candidate-check" --runtime-smoke
```

Record actual toolchain, source SHA, exit codes and reports. Hosted minimum/current-macOS checks and the
real-Mac [acceptance checklist](mac-acceptance.md) remain separate evidence. Do not reuse the security-only
branch's macOS success as a combined-candidate pass.

## 2. Build and inspect a candidate, still without a release

The workspace's SummonOS pipeline is `.github/workflows/release.yml`, **not** `tools/release.sh` (the latter
releases separate plugin repositories). Its PR/manual dry runs build universal arm64/x86_64 packages and
upload workflow artifacts; they do **not** attest or publish a GitHub release. A Vercel-connected branch push
can also create a website deployment, so do not push merely to trigger CI while deployment approval is reserved.

A local or dry-run artifact may be checked on a Mac with the packaged `scripts/install.sh --verify-only`,
using its explicit app/macctl source paths as the release workflow does. This validates supplied package
identity/signature before promotion; it does not authenticate a download, initialize user state or prove GUI acceptance.
Do not bypass the updater's provenance failure to make an unattested workflow artifact look like a published release.

## 3. After the separate owner gates

This section is a future procedure, not an instruction to publish now.

1. Review exact-head combined macOS CI, independent review and real-Mac results; obtain the scoped merge approval.
2. Before merging, account for automatic side effects: successful main Swift CI triggers a rolling edge release;
   the connected website can deploy main. Approval must cover those effects, or an approved alternative is needed.
3. If a numbered preview is approved, update version metadata consistently, run fresh checks, and bind the
   approved `vX.Y.Z` tag to its recorded source SHA. The release workflow rejects tags that disagree with `VERSION`.
4. Inspect universal architectures, compiled revision, bundle identity and signature; verify checksums and
   GitHub attestation against repository `RohiRIK/SummonOS`, signer `.github/workflows/release.yml`, GitHub-hosted
   runner and requested tag. Edge binds to main, but that does not prove it is today's main head.
5. Test the published download and a controlled upgrade from a prior installation; record identity, health and
   preservation of user state. Observe failure/rollback behavior only in disposable test environments.
6. Verify website deployment and app release as distinct targets. Neither a successful build nor a release URL
   establishes anonymous website behavior or native-Mac acceptance.

## Current remaining gates

- **Combined macOS build and packaged candidate:** not run here; this host is Linux with no Swift/macOS toolchain.
- **Real-Mac installation, permissions, connection and UI:** Rohi's checklist is not yet run. Actual upgrade
  acceptance also needs a suitable published newer artifact; do not install an older preview to simulate it.
- **Production qualification:** retained-memory analysis, displayed-frame profiling, native notifications,
  VoiceOver and Reduce Transparency remain open in [status](status.md). Preview preparation is not production certification.

Developer ID/notarization is optional pipeline support requiring maintainer credentials. No purchase,
credential change, tag creation, merge, deployment or announcement is authorized by this runbook.

[Status](status.md) · [Security and recovery](security-model.md) · [Mac checklist](mac-acceptance.md) · [Product direction](product-direction.md)
