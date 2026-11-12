---
type: Reference
title: Summon UX implementation audit
description: Current Summon surfaces checked against source, with historical design decisions and remaining native accessibility and profiling gates.
tags: [summon, macos, ux, accessibility, performance]
---

# Summon UX implementation audit

Source review updated 2026-11-11 through `18c7688`. The original audit was written on 2026-10-25; this page
now describes the current implementation rather than treating that audit's proposed fixes as missing features.
The [surface table](../../../docs/ux-surfaces/surface-table.md) and its per-surface research explain design
principles, not proof that a particular Summon build passed runtime acceptance.

**Labels:** **Implemented** is a source-backed capability, not a native verification claim. **By design** is an
intentional difference. **Open** is an actual remaining feature gap. **Unverified** is an acceptance check that
still needs its real scenario. Historical test/render results apply only to their recorded revision and scope.

The numbered baseline is `v0.2.4` (2026-10-28, a published preview/prerelease). November hardening, My Apps and
accent work is implemented after that tag; it is not a new numbered release. Stable/Edge select distribution
channels, not a guarantee of production maturity or that the published Edge artifact equals this branch.

## Surface map

| Surface | Current shape | Main source |
|---|---|---|
| Menu bar | `NSStatusItem` + nonactivating `StatusPanel` | `StatusPanel.swift`, `PanelView.swift`, [panel contract](menubar-panel.md) |
| Search/launcher | Always-visible search inside that panel; no separate launcher window | `PanelView.swift`, `MenuTree.swift` |
| Activity | Standalone history window with search/filter and agent actions | `ActivityView.swift`, `ActivityModel.swift` |
| Settings | One sidebar Settings window with grouped forms | `SettingsView.swift`, `SettingsSection.swift` |
| Updates | Standalone foreground window, sectioned updates and live row state | `UpdatesView.swift`, `SoftwareUpdates.swift` |
| Crash alert | Optional nonactivating alert; macOS banners are the other preference | `CrashAlertView.swift`, `AppDelegate.swift`, `CrashAnnouncement.swift` |
| Onboarding | Optional four-step welcome window | `OnboardingView.swift`, `Onboarding.swift` |
| About | AppKit standard About panel, shared immutable build identity | `AboutPresenter.swift`, `BuildInfo.swift` |
| System extensions | None in Summon itself; widget/notch are generated-project starters | `Projects.swift`, `templates/` |

Source basenames above are under `Sources/SummonMenuUI/` or `Sources/SummonCore/` unless stated otherwise.

## 1. Menu bar and search

| Dimension | Status | Current contract |
|---|---|---|
| Shape | Implemented | Borderless 320 pt panel, 4 pt below the status item, height capped to the visible screen and top-pinned on resize. No traffic lights or user resize. |
| Panel justification | By design | Searchable actions, agent state and nested inventory need more than a plain menu. The frontmost app keeps its menu bar. |
| Home anatomy | Implemented | Summon mark/title, agent state/picker, update badge, always-visible search, Ask Agent, Make Something, My Apps, optional setup-attention/Undo, then Activity…, Settings… and Quit. |
| Focus/dismissal | By design | No global outside-click dismissal and no close merely on resign-key. Returning to the previous app keeps the panel open; switching to a third app, changing Space, lock/sleep, action, Settings/Quit or a crash alert closes it. |
| Search | Implemented | Searches runnable entries across the visible menu tree, including actions hidden from home. Submenus have breadcrumb back navigation; empty categories remain discoverable by browsing My Apps. |
| Keyboard | Implemented | Recordable ⌃⌥Space and panel-agent shortcut (default ⌥Return), arrows, Return, Esc, Delete/Back, ⌘, and ⌘Q. In submenu search, Esc goes back; at root it closes. Non-click opens guard Return for 300 ms. |
| Context menu | Implemented | Right-click/Control-click offers Settings… and Quit. Footer retains both. |
| Status label | Implemented | Icon only by default. Optional elapsed `mm:ss` is off until enabled in General. Status-item accessibility text includes running state even with the visible clock off. |
| Refresh ownership | Implemented | One shared Activity refresh owner; off-main source collection, generation-checked publication, filesystem invalidation and slow reconciliation. No panel-specific one-second disk reload. One-second label ticks run only for an enabled visible session clock. |
| Materials/accent | Implemented | Liquid Glass on supported macOS 26+ paths, earlier material fallback; active-theme tint through `ThemeAccent.swift`. Health has text/accessibility labels as well as color. |
| Timing/memory | Unverified | Signposts exist, but ordered-front and pre-display AppKit update timings are not composited-frame timing or retained-heap proof. Comparative profiling gates remain open. |
| Hide/remove icon | Open | Summon itself has no Show in Menu Bar preference or removable-status-item behavior. Do not confuse this with the generated `menubar-panel` starter, which has a hide toggle. |
| File drop/action palettes | Open (low) | No file-drop target, ⌘K secondary-action palette or ⌘1–9 result launch in Summon's panel. The separate `launcher` starter implements those features. |

### Superseded designs

The 2026-10-25 Now/Recent home was implemented and then rejected. The intermediate hidden-until-typing
search field was superseded by always-visible search. An older active-theme header pill is also gone.
Do not use screenshots or dated changelog entries for those layouts as the current panel spec. History stays
in Activity, preferences in Settings, and update progress in Updates.

## 2. Activity

| Dimension | Status | Current contract |
|---|---|---|
| Window | Implemented | Standard foreground window, minimum 640 × 420, default 980 × 640, toolbar search/filter. Summon becomes a regular app while Activity is open. |
| Layout | By design | A single log rather than sidebar/canvas/inspector; that surface-table convention is for collection-based apps. |
| Actions | Implemented | Selected-line agent question, copy, diagnose, Finder reveal and undo where applicable. Undo uses a confirmation dialog. Empty states use native unavailable-content UI. |
| Terminal state | Implemented | Shared `TaskResults` projection distinguishes success, failure, cancellation, timeout and interruption. Result persistence/retention/notification errors do not become contradictory execution outcomes. |
| Live lifecycle | Implemented | Panel/window interests share source refresh and invalidation; stale completions cannot overwrite a newer generation. Closing the last interested surface cancels workers and removes watches. |
| Quick Look | Open (low) | No Space-to-preview diagnostic report; Finder reveal is available. |

## 3. Settings and My Apps

| Dimension | Status | Current contract |
|---|---|---|
| Window | Implemented | One sidebar window, 780–820 pt wide, minimum 520 pt tall, close-only chrome: minimize/zoom dimmed and no full screen. |
| Pages | Implemented | General, Agents, My Apps, Terminal, Notifications, Appearance, Setup and Tasks. Every app preference stays here rather than in the panel. |
| Controls | Implemented | Instant apply for preferences and shortcut reset controls. Appearance explicitly separates preview from Apply Theme. |
| Permissions | Implemented | Accessibility status, Allow/System Settings deep link and refresh while unavailable. Browser/Finder Automation may prompt when that action first runs. Permission checks are not proof that the OS grant is effective for every candidate binary. |
| Notifications prompt | By design | Authorization is requested at startup after the event-watch baseline, not from an early bare SwiftPM launch. Task-result notifications are a primary app function. |
| Agents | Implemented | Ten launch targets, eight MCP connect targets and five headless task targets are distinct registries/capabilities; see the [README matrix](../README.md#agents-and-connections). Not every harness has login/model/plugin probe support. |
| Execution | Implemented | New installs use Agent controls; existing configured choices persist. Unattended bypasses supported harness controls. Neither mode creates a Summon sandbox. |
| My Apps taxonomy | Implemented | Panel Apps, Themes, Art & Wallpapers, Window Apps, Command-Line Tools, Screensavers; shared order and empty categories in panel/Settings. Built-in and custom themes stay visible. |
| Health | Implemented | Shared deduplicated item repair totals and separate recommendation totals. Actual missing files/builds/referenced images can be repairs; optional art, colors-only themes, contrast review and hue advice are not automatic repairs. Numerical contrast findings remain visible. |
| Fix with AI | Implemented | My Apps and `summon fix --apps` target counted inventory defects. General Mac diagnosis remains separate. Theme/art name collisions do not dispatch a project. |
| Accent synchronization | Implemented | Theme switches update control tint and active checkmarks from one observed selection; previous-theme revert is shared. macctl posts accent-refresh notifications after apply/undo/recovery. Finder Automatic folder colors follow system accent; explicit folder colors remain unchanged. Other apps may still need reopening. |
| Import/export, Dock mode | Open (low) | No app-preference export/import or menu-bar/Dock/both mode picker. Project import is a different feature. |

## 4. Updates

Updates is no longer a panel submenu that runs installs inline. The panel's Update row and count tag close it
and open the Updates window. Settings › General retains check/channel/group preferences.

- Summon has What's New and Install and Relaunch; its installer uses the verified staged/rollback path.
- Agents, Homebrew, bun/npm and macOS have their own sections. Command updates show queued/running/done/failed
  state; Update All operates on installable command rows, not an unattended macOS upgrade or silent Summon install.
- Failures expose output and Fix with AI. Password-needed failures offer Open in Terminal; other failures offer
  Retry. macOS opens Software Update. Non-Summon rows offer What's New when known and Skip This Version.
- Automatic checks are on by default, due at launch and 24 hours after the last check, and skipped automatically
  in Low Power Mode. Agent auto-update is a separate preference. Stable follows numbered tags; Edge follows the
  published rolling artifact, which can lag the branch.

## 5. Crash alert and notifications

| Dimension | Status | Current contract |
|---|---|---|
| Presentation | Implemented | Settings chooses macOS notification (default) or Summon alert; do not describe both as firing for each report. Routine user-fault/memory reports remain history without actionable alerts. |
| Focus | Implemented; native scenarios incomplete | Alert orders front without taking key so background crashes do not steal Return. Clicking it allows keyboard actions. It first closes the menu panel. |
| Geometry/visibility | Implemented | 440 pt alert, `.statusBar` level, all Spaces/full-screen auxiliary, `.transient`/`.ignoresCycle`, excluded from Window menu. It is an actionable alert, not an ambient 120–320 pt HUD. |
| Motion | Implemented; accessibility acceptance open | Fade in/out and untouched-alert auto-dismiss exist. Source animation duration alone is not Reduce Motion/Transparency acceptance. |
| Burst | Recorded native evidence | A 13-report equal-timestamp fixture passed the real watcher across five-file batches; the native alert showed newest + “12 more new reports”, dismissed, and post-burst search accepted typed input. This proves that fixture path, not banner grouping/delivery or VoiceOver. |
| Task delivery | Implemented; full native delivery open | App posts recorded task outcomes with Show Log/Ask Agent actions; CLI fallback is bounded and runs after lease release. Cancelled runs skip notification. Submission failure does not alter execution success. |

## 6. Welcome

The old three-step 640 × 440 flow is superseded. Current `OnboardingFlow` has **four** steps at **720 × 480**:

1. Welcome explains screen questions, crash diagnosis and making small Mac apps.
2. Agent selection shows installed agents and available login information; it can recheck missing/login state.
3. Accessibility explains the context it enables, with live status and System Settings action. It is optional.
4. Ready points to the status item, offers Try It Now, tracks whether the panel opened and warns if the icon is
   not visible in the menu bar.

The window is close-only and temporarily brings Summon into the Dock. Closing skips it. A completed flow or
Visual QA skips automatic presentation; an existing default agent plus Accessibility marks an older setup
complete without reopening the flow. Settings › General › Show Welcome Again and `summon://welcome` reopen it.
VoiceOver, Reduce Motion and multi-display/menu-bar-overflow scenarios still need their own acceptance.

## 7. Native About and build identity

About is **implemented**, not a future settings screen. Settings › General › About Summon and the standard
About command use AppKit's singleton panel. It shows app identity, marketing version, numeric build, revision
and dirty/unknown state, channel, configuration and UTC build time from immutable compiled `BuildInfo`.
Opening it does not query Git, disk metadata or the network/updater. Packaging stages one identity into compiled
constants, plist and manifest; unknown development fields are not invented.

The panel temporarily uses regular activation for native keyboard focus and returns to accessory mode when
no regular titled window remains. Commit `18c7688` additionally unhides the app and explicitly raises the native
window on cold launch/reopen. One earlier native cold launch did not expose a visible About window; the source
correction is not itself completed cold-launch acceptance. Recorded metadata/capture/Command-W evidence has
narrower scope than full keyboard and VoiceOver coverage.

## 8. Projects versus system extensions

Summon ships nine project starters: `menubar`, `menubar-panel`, `launcher`, `hud`, `notch`, `app`, `widget`, `cli`,
`screensaver`. They are generated projects, not extra Summon app surfaces. Widget is the embedded-extension
Xcode-project exception; its registry kind is window app. Launcher/HUD/notch register as panel apps. New
repositories default to approval via `summon project repo`; standing `always` is retained when chosen, and
created repositories are private. The notch starter's real-hardware geometry remains explicitly unverified.

## Evidence boundaries and remaining acceptance

The [runtime audit](../../../docs/plans/2026-11-08-runtime-audit.md#implementation-evidence-and-unverified-acceptance-2026-11-08)
preserves the original `3f37adf` findings and later revision-specific implementation/evidence. Earlier
statements there such as “no About surface” describe the original audit, not the current branch.

Recorded evidence includes hosted macOS 15/26 visual/native About checks, real terminal-event delivery,
owned-window Command-W, query-value-checked panel cycles, and the native crash-burst result above. Content-only
renders, a signed bundle, a green diagnostic control job and a successful local install are not substitutes for
installed-window capture, accessibility navigation or performance acceptance.

The following remain **Unverified / release gates** until their real scenarios finish:

- SwiftUI recorder completion and meaningful instrument content; the hosted independent control reproduced an
  empty-data/finalization failure without Summon, but that does not waive Summon's profiling gate.
- Controlled comparative panel/search profiling, actual WindowServer-displayed/composited frame timing and
  long-run retained-memory/retain-graph analysis. `PanelOpen` and `PanelWindowUpdate` stop before display.
- Live malloc sampling with complete post-warmup samples and growth bounds; RSS, malloc totals and retained
  graphs measure different things. Missing samples cannot pass, and growth is not automatically leak attribution.
- Native macOS banner delivery/actions/grouping, full notification/crash-focus scenarios, VoiceOver navigation,
  Full Keyboard Access, Reduce Transparency and Reduce Motion behavior across the supported OS/display cases.
- The current cold About visibility correction under repeated real cold launches and close/reopen conditions.

No crash or memory-leak cause is established merely by these source changes. This documentation refresh
performs source/history reconciliation only; it does not add a new build, test, profiling or accessibility pass.
