---
type: Plan
title: SummonOS production readiness
description: Evidence-based audit, original product direction, release blockers, and staged acceptance criteria for a native macOS agent layer.
tags: [summonos, security, architecture, release, audit]
status: implemented-awaiting-release-qualification
created: 2026-10-20
---

# SummonOS production readiness

SummonOS has a working foundation for a native macOS agent layer. It is suitable for continued development;
this audit does not establish production readiness. The recommended path is a clearly labeled experimental
preview after the security and recovery blockers below are fixed, followed by a supported release once
installation, distribution, permissions, and recovery have been verified on other Macs.

## Approved implementation and verification — 2026-10-20

The owner approved the staged plan. Local hardening is implemented on
`audit/production-readiness-2026-10-20`; existing and concurrently edited UI/skills/registry work was preserved.
No changes have been installed into the owner's live Summon setup. The owner subsequently authorized
skill retesting and publication of all reviewed workspace changes; see the publication report.

- [x] S1/S3: theme text injection and wallpaper escape regressions fixed; foreign skill links preserved,
  exact ownership recorded, concurrent linking serialized.
- [x] S2/D2: private scans fail closed (including read errors, binaries and symlink targets); releases build
  exact public source SHA and carry checksums/provenance.
- [x] R1: failed capture cannot claim an old HEAD; failures persist, tasks stop, and pending macctl journals
  cannot serve as checkpoint markers. Config capture remains optional and coverage is explicitly scoped.
- [x] R2/R3/R5: serialized settings transactions, exclusive backups, pending/completed/failed outcomes,
  retryable failed undo, partial-failure recovery references, and per-display wallpaper metadata.
- [x] R4: bounded process groups, TERM/KILL escalation, cancellation, descriptor hygiene, capped output/logs;
  task failure returns nonzero, overlapping runs are refused, scheduling/removal serialize, failed unload
  preserves task recovery data. New tasks freeze agent/mode/cwd; unknown pinned agents never switch silently.
- [x] R6/R7: crash bursts drain with same-timestamp deduplication; corrupt task/agent/checkpoint stores remain
  intact and block mutations/execution. Event append/trim is serialized across processes and byte bounded.
- [x] Trust: new installs use normal harness controls; configured legacy installs retain unattended mode;
  explicit changes survive migration. Settings and CLI expose the preference. Known diagnostic identifiers
  are redacted on export, with owner-only files and an explicit review requirement.
- [x] D3/D4: staged installation with rollback/ownership receipt; preview-first ownership-aware uninstall;
  PR/workspace/shell/distribution checks, read-only CI token permissions, pinned action revisions.
- [x] Optional Developer ID/notarization tooling signs a copy and refuses output/publication after failed
  acceptance, stapling or Gatekeeper checks. Real credentials were not used.
- [x] Native template build/test/bundle gates now use external caches instead of source-tree `.build` folders.
- [x] D1 privacy/decision: the owner authorized existing-history publication. Generic secret scans and
  targeted history/file/image review passed; provider icon provenance is documented. Anonymous access
  and live CI remain publication verification steps in the publication report.
- [ ] Real install/upgrade/uninstall in a disposable account, permission/notification/agent smoke tests,
  distinct-monitor recovery, downloaded quarantined artifact verification, real signing and OS/CPU matrix.
- [ ] Real app idle energy/CPU/RSS and launcher latency measurements; a tested supported update channel.

Verified on Apple Silicon, macOS 26.6.2, Swift 6.4:

| Check | Result |
|---|---|
| Summon full gate (`scripts/check.sh`) | 175 Core + 5 CLI tests; release app/CLI bundle, plist/theme lint, command discovery passed |
| macctl | 94 tests passed; release CLI built |
| Distribution helpers | 45 isolated tests passed; no real install, GitHub writes, credentials or signing |
| Four generated project templates | Every build/test/plist/bundle or CLI release/help gate passed |
| Workspace example | Core test/build passed with an external cache |
| Settings General | Xcode rendered light/dark on this Mac; both images inspected and saved under `incubator/summon/docs/previews/` |
| Packaging | Local ad-hoc bundle passed `codesign --verify --deep --strict`; both executables are arm64 |
| Hygiene | Workspace, generated indexes, README art, shell syntax/ShellCheck and diff whitespace checks passed |

A bounded warm CLI baseline (15 release `summon commands --json` invocations, JSON decoded each time) measured
10.23 ms median and 12.69 ms nearest-rank p95. This is local command discovery, not GUI response time or a
before/after performance claim. Native runtime permissions, new settings interaction and signed distribution
are not established by a preview or fixture tests.

The original audit evidence below is retained as the pre-change assessment. The
[security model](../security-model.md) describes implemented behavior and remaining boundaries.

## Requirements and scope

Explicit requirements from the owner: understand the project and its README references; prepare it for
production, including security and efficiency; express an original idea inspired by Omarchy, implemented
as a native macOS layer with skills.

Proposed interpretation: keep the existing Swift architecture, agent choice, keyboard access, skills,
and small native apps. Prioritize dependable system operations over adding more features. Public preview
and stable distribution have separate acceptance gates. The owner approved these recommendations; implementation results are recorded above.

The audit covers the tracked workspace, current working-tree changes, installer, release/publish tooling,
Summon, macctl, shipped skills and templates. The separate plugin repositories were not audited end to end.
Existing uncommitted UI work was preserved. No agents were launched, system preferences changed, tasks
scheduled, software installed, repositories published, or visibility changed for this audit.

## Product direction

Proposed public description:

> SummonOS is an open-source, native macOS layer that connects your chosen coding agent to documented
> Mac tools and skills, so you can understand, customize, and build your own computing environment.

Its distinctive contribution should be the combination of native Swift tools, inspectable commands,
portable skills, visible results, and recovery with a stated scope. App generation is one capability
within that environment. Omarchy is credited as inspiration for a coherent, adaptable desktop.

The owner's [Omarchy article](https://rohi-lab.org/blog/omarchy) emphasizes supported operations,
verification, and understandable recovery. [Omarchy](https://omarchy.org/) currently also describes agents,
crash diagnosis, skills, plugins, and themes. Merely offering an agent launcher is therefore insufficient
as a differentiator. SummonOS should demonstrate how those ideas fit native macOS conventions.
[Raycast's Glaze introduction](https://www.raycast.com/blog/introducing-glaze) shows adjacent interest in
personal desktop apps; its product description does not establish that its implementation matches SwiftUI.

Proposed first audience: Mac users comfortable installing a coding agent and reviewing changes. Broader
consumer use needs a simpler first run, a declared support policy, and independently tested recovery.
Local execution of Summon and generated apps does not imply that the chosen model runs locally or that
agent-assisted tasks work offline. Document those distinctions explicitly.

## Current architecture worth keeping

- **SummonCore / CLI / UI library / app:** a useful separation with injectable runners and pure compilers.
- **macctl:** typed settings, validation, dry runs, JSON output, and snapshots before settings writes.
- **Skills:** procedural knowledge agents can read, with per-agent selections.
- **Templates:** SwiftPM projects for menu bar apps, window apps, CLIs, and screensavers.
- **User interface:** menu bar actions, a separate Settings window, Activity, keyboard launcher, crash handoff.

Keep native frameworks first, argv-based command invocation, user-owned configuration, separate preferences,
and no passwordless sudo. Skills are guidance; an unrestricted agent can bypass them. A checkpoint is a
recovery aid for specific state, not a sandbox or a system backup.

## Findings and release criteria

P1 below means fix before inviting general installation. P2 means fix or explicitly constrain the affected
feature before a supported release. These priorities describe release impact, not formal CVSS scores.

| ID | Priority | Finding and source evidence | Required result |
|---|---|---|---|
| S1 | P1 | Theme validation checks colors/slug but leaves `name` and `font` unvalidated; both are inserted into terminal config. A crafted font passed the actual decoder and generated a new Ghostty command directive in an isolated compilation. `incubator/summon/Sources/SummonCore/Theme.swift:45`, `:123`, `:132`, `:138`, `:147`. | Treat theme strings as data. Reject control/newline injection and encode values for each target. Add regression fixtures for names, fonts, quotes, backslashes, and both terminal formats. No theme data may introduce executable directives. |
| S2 | P1 | Privacy scanning uses `if grep ...`; a scanner error takes the same path as no matches. `tools/publish-public.sh:29`. | Distinguish match, clean, and error statuses; errors block publishing. Reject unusable pattern configuration. Test invalid regex, unreadable input, matches, clean exports, and empty configuration before invoking GitHub. |
| S3 | P1 | Skill linking removes any existing symlink for a selected shipped skill, including foreign links. App launch relinks automatically. `incubator/summon/Sources/SummonCore/SkillLinker.swift:47`; `Sources/SummonMenuUI/AppDelegate.swift:45`. | Preserve user-owned and foreign links; update only positively identified Summon links. Report conflicts. Cover relative, broken, owned, foreign, and deselected links; unlink must preserve foreign content too. |
| R1 | P1 | Checkpoints are best effort; failed Git capture can still record the previous HEAD. Scheduled tasks discard checkpoint problems. `incubator/summon/Sources/SummonCore/Checkpoint.swift:68`, `:84`; `Sources/SummonCLI/TaskCommands.swift:131`. README promises exceed this coverage. | Record successful capture and degraded coverage separately; never present a stale HEAD as a successful capture. Persist and display task checkpoint failures. Define the policy for proceeding with incomplete coverage. Replace universal undo claims with exact coverage/exclusions. |
| R2 | P1 | macctl saves an undo record with `undoes` before attempting restoration. A backend failure can cause the next bare undo to skip an unreverted original. `macctl/Sources/MacCtlCore/Engine.swift:103`, `:155`. | Persist pending/completed/failed outcomes so failure remains recoverable. Inject a failing backend write and verify retry/bare undo selects the correct remaining work. Report partial application with its recovery reference. |
| R3 | P1 | Settings planning, snapshot ID allocation, snapshot saving, and writing have no cross-process transaction lock. `macctl/Sources/MacCtlCore/Engine.swift:249`; `FileSnapshotStore.swift:39`. | Serialize the complete mutation across CLI processes; allocate unique snapshots without overwrite. Test concurrent invocations, lock release after failure, and recovery from interrupted work. Process-local actors alone are insufficient. |
| R4 | P1 | The advertised task runtime cap sends SIGTERM then waits without a hard deadline; task failure prints a message but returns normally. General Shell has no timeout/cancellation and buffers unlimited output. `incubator/summon/Sources/SummonCLI/TaskCommands.swift:140`, `:168`; `Sources/SummonCore/Shell.swift:55`, `:85`. | A shared process executor enforces deadline, cancellation, bounded output, and scoped child-process cleanup. Tasks return nonzero on failure/timeout and prevent overlapping runs. Prove behavior using harmless fixtures, including a SIGTERM-ignoring process and a descendant holding output open. |
| D1 | P1 | Authenticated GitHub metadata says `RohiRIK/SummonOS` is private. Repository, workflow, badge, and two raw install URLs return 404 anonymously. | Resolve publication through an explicit release decision after working-tree and reachable-history privacy/license review. Verify the published checkout and install instructions anonymously. Do not change visibility as an audit shortcut. |
| D2 | P1 | Release tooling builds a local working tree but tags public `main`; it checks only the local branch name. `tools/release.sh:21`, `:41`. | Build from the exact reviewed public commit in a clean checkout/export; record commit, toolchain, architecture, and checksum. Refuse dirty/unpublished source and validate the downloaded artifact against its source tag. |
| R5 | P2 | Wallpaper reads the main screen but changes every screen, losing distinct per-display pictures on undo. `macctl/Sources/MacCtlCore/Wallpaper.swift:16`, `:23`. | Capture/restore display-specific values and relevant options, or explicitly constrain the supported behavior until implemented. Verify distinct wallpapers on a real multi-display setup. |
| R6 | P2 | Crash scan limits fresh reports to five and advances the marker beyond omitted reports. `incubator/summon/Sources/SummonMenuUI/SummonModel.swift:127`. | Drain bursts without dropping reports, with a durable cursor/deduplication strategy. Test more than five new reports and identical timestamps. |
| D3 | P2 | Installer replaces macctl before Summon finishes building; app installation deletes the live app before copying. Doctor failure is ignored before printing success. `install.sh:58`, `:67`; `incubator/summon/scripts/install.sh:12`. | Stage and validate the whole installation before activation; preserve a usable prior version on failure. Separate required health failures from optional setup warnings. Verify upgrade, interrupted copy, build failure, and rollback in a disposable account. Add an ownership-aware uninstall path. |
| D4 | P2 | Workflow triggers only on push/manual invocation, and the workspace gate is an inactive snippet. `.github/workflows/swift.yml:5`; `tools/ci/check-workspace.yml`. | Run read-only checks for PRs and pushes, integrate workspace hygiene, restrict token permissions and pin actions. Resolve cloud/local gate policy explicitly: current instructions/context disagree. Do not substitute a gate silently. |
| R7 | P2 | Task storage decodes corruption as an empty list; adding a task then overwrites existing records while their LaunchAgents remain. `incubator/summon/Sources/SummonCore/RecurringTask.swift:90`; `Sources/SummonCLI/TaskCommands.swift:48`. | Distinguish missing, corrupt, and unreadable storage. Refuse mutations on corruption, preserve original bytes, and give a recovery path. Test corrupt JSON followed by task creation; apply the same rule to checkpoint and agent settings stores. |

The Ghostty impact follows its documented [`command` option](https://ghostty.org/docs/config/reference#command).
The audit proved configuration injection; it did not launch a terminal or execute the injected command.
Other findings above are source-based failure paths unless a verification result is stated explicitly.

## Security and trust decisions

The current stored owner preference is unattended agent execution with approval/sandbox bypass flags
(`incubator/summon/PROJECT-CONTEXT.md`, `Sources/SummonCore/Agent.swift:49`). This audit leaves that behavior
unchanged. It must be presented accurately to new users, independently of checkpoint status.

Recommended production policy for approval: retain an explicitly selected unattended mode, describe its
authority once during onboarding, preserve that choice, and bind recurring jobs to a reviewed prompt,
working directory, agent, and execution mode. Use the agent's normal controls where supported for new
users who have not made that choice. Do not claim a mode is restricted when its harness cannot enforce it.

First-run consent is separate from repeatedly interrupting authorized work. Existing user intent must
survive upgrades. Untrusted crash/log/file text must remain evidence, never instructions. Explain what
is handed to the chosen agent and that its provider may receive that context.

Before public preview also:

- Review filesystem containment and symlink handling for themes, hooks, project names, cleanup, and migrations.
- Set owner-only permissions on sensitive task prompts/logs and state; provide retention and redaction rules.
  `DebugBundle.swift:25` includes hardware information and logs; line truncation is not redaction.
- Make corrupt state distinguishable from an empty store; do not overwrite unrecoverable data silently.
- Inventory shipped skills and plugins with versions/source/license. Explain capability changes on update;
  preserve each agent's selected skills. No new marketplace or dependency framework is required for this.
- Keep URL routes narrow. `summon://agent` currently launches an unrestricted interactive agent but does not
  accept an attacker prompt; this is an external launch boundary, not demonstrated remote code execution.
  Remove the current development-only `test-crash` route from release builds.

## Efficiency work: measure before redesigning

No CPU, memory, energy, or launch-time benchmark was collected. Source review found useful existing work:
crash parsing runs off the main actor and caches recent paths; Activity refreshes while open; EventLog has
a byte threshold. There is no evidence here that a broad architecture rewrite would help.

The first efficiency change should be the bounded executor in R4, which also addresses reliability.
Next, record a baseline for cold/warm app launch, launcher visibility, idle CPU/RSS, wakeups, Activity load,
and a long history of snapshots/events. Use the same Mac, build type, dataset and power conditions before
and after. Proposed usability target: launcher visible within 200 ms warm, with no synchronous subprocess
wait on the UI thread; confirm the target against measured baseline rather than claiming it today.

Then consider filesystem notifications with a bounded reconciliation poll for crash/state changes;
incremental log reads and snapshot indexes if measurement identifies them as bottlenecks; and moving
remaining synchronous disk scans from `SummonModel.reload()` off the main actor. EventLog append/trim
must also be safe across simultaneous CLI/task writers (`EventLog.swift:73`). Keep caches bounded and
cancel UI work when the owning view closes.

## Staged implementation plan

1. **Security and trust:** fix S1–S3; correct recovery/authority language; define first-run execution mode
   and diagnostic data handling; audit path boundaries. Add focused regression tests before changes.
2. **Recovery and execution:** implement R1–R4 and structured partial-failure reporting. Keep schemas
   backward compatible or supply a tested migration. Address wallpaper/crash loss and store corruption.
3. **Installation and supply chain:** fix D2–D4; add a versioned source-preview install with exact commit
   provenance, repeatable upgrades, uninstall, and failure recovery. Do not make moving `main` the stable channel.
4. **Native release qualification:** run package/template gates; real app first-run and settings/notification
   checks; one independent clean Mac/account installation; supported macOS/architecture matrix; performance
   baseline. List unverified OS versions as unverified. Remove development routes from release builds.
5. **Public experimental preview:** review all reachable history/private data, credits, README, security and
   support policy, screenshots and known limits. Select clean publication versus existing-history publication
   explicitly; do not rewrite history or flip visibility without that decision. Publish only verified claims.
6. **Supported binary release:** versioned artifacts with Developer ID, hardened runtime, timestamps,
   notarization, stapling, checksums, and a tested update/rollback route. Verify a quarantined downloaded
   artifact on another Mac. Signing credentials/account availability remain external prerequisites.

Apple documents the [Developer ID distribution path](https://developer.apple.com/developer-id/) and
[notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Ad-hoc local builds remain a development path. A general release should not require deleting quarantine.

## README reference review

All nine README Markdown files in the workspace were read/inventoried, including four templates and the
GUI research README. Absolute external URLs occurred only in the root README. The table records all 17
unique external URLs checked on 2026-10-20. Fetches used anonymous HTTP GET; 404 is not evidence of deletion.

| README URLs | Result |
|---|---|
| [Omarchy](https://omarchy.org), [owner's article](https://rohi-lab.org/blog/omarchy) | Both HTTP 200; content read for product direction. |
| [OKF specification](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md), [Bun](https://bun.sh) | Both HTTP 200; documentation format and maintainer tooling references. |
| [SummonOS repository](https://github.com/RohiRIK/SummonOS), [workflow](https://github.com/RohiRIK/SummonOS/actions/workflows/swift.yml), [badge](https://github.com/RohiRIK/SummonOS/actions/workflows/swift.yml/badge.svg) | All HTTP 404 anonymously; authenticated repository metadata confirms private visibility. |
| [Installer](https://raw.githubusercontent.com/RohiRIK/SummonOS/main/install.sh), [agent installation guide](https://raw.githubusercontent.com/RohiRIK/SummonOS/main/docs/install-ai.md) | Both HTTP 404 anonymously. Local files reviewed; public contents unavailable. |
| [mac-breathe](https://github.com/RohiRIK/mac-breathe), [mac-calendar](https://github.com/RohiRIK/mac-calendar), [mac-network](https://github.com/RohiRIK/mac-network), [end-of-day](https://github.com/RohiRIK/end-of-day) | All HTTP 200; linked examples, not security endorsements. |
| [Breathe screenshot](https://raw.githubusercontent.com/RohiRIK/mac-breathe/main/docs/screenshots/window.png), [Calendar screenshot](https://raw.githubusercontent.com/RohiRIK/mac-calendar/main/docs/screenshots/panel.png), [Network screenshot](https://raw.githubusercontent.com/RohiRIK/mac-network/main/docs/previews/PanelView-0-Overview.png) | All HTTP 200 with image/png content. |

## Verification and limitations

- `swift test --package-path incubator/summon --scratch-path ~/Library/Caches/macplugins/production-audit-summon`:
  146 tests across 23 suites passed; current UI targets compiled.
- `swift test --package-path macctl --scratch-path ~/Library/Caches/macplugins/production-audit-macctl`:
  82 tests across 8 suites passed. Existing always-true cast warning in `ValueParsingTests.swift:34`.
- Workspace hygiene and shell syntax checks passed during the audit. ShellCheck reported SC2155 in
  publishing/release scripts: `readonly` declarations can hide command-substitution failures.
- Theme injection was reproduced by compiling the actual compiler/decoder with isolated files. No payload
  was executed. Existing test suites passing does not cover the newly identified failure scenarios.
- This was not a formal penetration test, full reachable-history secret scan, plugin audit, full template
  qualification, Gatekeeper/notarization check, GUI preview review, or performance benchmark. Real settings,
  launchd, multi-display restoration, first-run permissions and clean-account installation remain unverified.

The owner approved implementation, including the first-run execution policy. Local hardening is complete;
release qualification remains open as listed above. Public visibility changes, history rewriting, signing
expenditure and publishing a release still require their concrete release decision. No publication was performed.
