---
type: Reference
title: Status and verification
description: "Published preview versus unreleased implementation, documentation baseline, and remaining release-acceptance limits."
tags: [status, releases, verification, roadmap]
---

# Status and verification

Documentation reviewed on **2026-11-11**, against source through **[`18c7688`](https://github.com/RohiRIK/SummonOS/commit/18c7688)**.
`VERSION` is **0.2.5**. A marketing version identifies a release family; it does not prove which commit an
installed build contains.

## Published preview

GitHub release metadata checked on November 11 lists **v0.2.5**, published **2026-11-11**, as the newest
numbered release. It is marked **prerelease**, not production-supported. The separate `edge` release can lag
numbered releases; inspect its actual version rather than assuming “edge” means this checkout.

| Version | Recorded change | Source |
|---|---|---|
| 0.2.0 | App self-update and consolidated update discovery | [Release](https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.0) |
| 0.2.1 | Working panel update action and dedicated Updates window | [Release](https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.1) |
| 0.2.2 | Fix with AI for a failed update | [Release](https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.2) |
| 0.2.3 | Siri, Shortcuts and Spotlight actions | [Release](https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.3) |
| 0.2.4 | Lower idle work in Summon and its templates | [Release](https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.4) |
| 0.2.5 | Runtime hardening, build identity, My Apps inventory and theme accents (#124) | [Release](https://github.com/RohiRIK/SummonOS/releases/tag/v0.2.5) |

See the [changelog](../incubator/summon/CHANGELOG.md) for earlier releases and detailed changes.
The `stable` channel name distinguishes numbered releases from rolling `edge`; it does not remove preview
status or qualify an unfinished development branch.

## Shipped in v0.2.5

The November work below shipped in v0.2.5 (#124, squash commit `90f7b81`); the commit links point at the
original branch commits.

| Area | Implemented change | Evidence/provenance |
|---|---|---|
| Task completion | Bounded encoded terminal events, identified outcomes, pending-run recovery and explicit lease release | [`a5a75e0`](https://github.com/RohiRIK/SummonOS/commit/a5a75e0), [`deb7eb1`](https://github.com/RohiRIK/SummonOS/commit/deb7eb1) |
| Refresh and watching | Shared off-main refresh, stale-publication rejection and watcher readiness/replacement handling | [`a5a75e0`](https://github.com/RohiRIK/SummonOS/commit/a5a75e0), [`e94dbfa`](https://github.com/RohiRIK/SummonOS/commit/e94dbfa) |
| Build identity and About | Staged manifest/compiled identity, native About, packaged identity checks and cold-launch focus correction | [`a5a75e0`](https://github.com/RohiRIK/SummonOS/commit/a5a75e0), [`18c7688`](https://github.com/RohiRIK/SummonOS/commit/18c7688) |
| My Apps | Shared six-category inventory, consistent counts, repair defects separated from recommendations | [`dbcb4fb`](https://github.com/RohiRIK/SummonOS/commit/dbcb4fb) |
| Theme accents | Active app tint synchronization and native macOS accent refresh; custom folder colors remain separate | [`dbcb4fb`](https://github.com/RohiRIK/SummonOS/commit/dbcb4fb) |
| Runtime tooling | Owned UI input, crash-burst fixtures, recording-content checks, bounded recorder diagnostics and native heap sampling | [Runtime audit and dated evidence](plans/2026-11-08-runtime-audit.md) |

Acceptance gates still open after v0.2.5: displayed-frame hitches, live-heap growth, VoiceOver and Reduce
Transparency. See the [runtime audit](plans/2026-11-08-runtime-audit.md).

## Verification is narrower than feature availability

The [runtime audit](plans/2026-11-08-runtime-audit.md) retains revision-specific tests and native evidence.
The initial source findings describe the October baseline; later sections record fixes and their verification.
Those historical measurements are not fresh measurements of every subsequent commit.

Recorded evidence includes successful Core lifecycle scenarios, packaged identity checks, hosted panel/search
cycles and native About/Activity captures. The November native crash-burst scenario observed all **13** fixture
reports, a “12 more” alert, dismissal and subsequent typed search. It does **not** establish native macOS banner
or VoiceOver delivery. The subsequent cold-launch About correction is an implementation change, not by itself
a completed cold-launch acceptance run.

Remaining acceptance gates are explicit:

- Reliable SwiftUI recorder completion **and actual SwiftUI data**; an empty/saved trace is not a pass.
- Controlled comparative GUI profiling and actual WindowServer-displayed frame timing.
- Full retained-memory analysis; RSS alone is not proof of a leak or a bounded heap.
- Native notification delivery, VoiceOver navigation and Reduce Transparency scenarios.

An independent hosted SwiftUI control also failed recording without Summon. That narrows the evidence but
does not establish a toolchain root cause or certify Summon's performance. Missing data remains blocked.

## Scope of this wiki

Current guides cover the code in this workspace: Summon, macctl, templates and workspace tooling. Plugin
repositories are separate; [their registry](../plugins.md) contains recorded status, not a new implementation
audit. Research and plans retain dated conclusions instead of being silently rewritten to match newer code.

Use [features](features.md) and component READMEs for current contracts; use
[plans/reports](plans/index.md) for rationale and provenance. Proposed work is labeled as planned, not shipped.
