# Plan: `macctl` — macOS setup CLI for AI agents (new tool)

Status: plan approved 2026-10-16; milestone 1 not started. Full plan: `docs/plans/2026-10-16-macctl.md`.
Repos: `mac-ctl-dev` (private) / `mac-ctl` (public). Bundle id `local.macplugins.macctl`.

## Decisions
- Swift binary (Core / CLI / later MCP + helper app), JSON profiles, snapshot before every change, `--json` everywhere.
- `swift-argument-parser` approved by the user as the one dependency (exception to the no-deps rule).

## Milestone 1
- [ ] Scaffold `mac-ctl-dev`, PROJECT-CONTEXT.md
- [ ] Core test-first: registry, values, profile diff, snapshots, restart batching
- [ ] Backends: defaults, killall, AppleScript (argv only + injection test)
- [ ] ~15 settings verified on a real Mac (dock, finder, keyboard, screenshots, dark mode)
- [ ] Commands: doctor, list, describe, get, set, diff, apply, snapshot list, undo
- [ ] Sample profile + `MacSetup` skill; verify apply/undo on the Mac; PR + report

---

# Plan: `mac-calendar` v0.2 — events, reminders, quick add, Hebrew dates, hotkey, week view

Status: done (2026-09-30). Merged mac-calendar-dev PR #2, public snapshot published. Branch `feat/events` in `plugins/mac-calendar`.

## Requirements (explicit, from the user)
1. Show events from the user's calendars (EventKit).
4. Quick add: type "Lunch with Dan Fri 1pm" and it creates the event.
8. Hebrew date under each day + Israeli holidays.
9. Global hotkey ⌥⌘P opens the panel.
10. Reminders due each day.
11. Week view.

## Decisions (inferred, cheap to change)
- Permissions: Calendars + Reminders full access, requested only from a Settings toggle (user action).
  Denied: Settings explains and links to System Settings › Privacy. Info.plist usage strings.
  No sandbox / hardened runtime, so no entitlements needed.
- Panel: day dots (up to 3 calendar colors) under each day. Click a day to select it; the list under
  the grid shows that day's events (time, title, calendar color) and reminders (checkbox completes it).
  Default selection = today. List scrolls past ~6 rows so the panel stays compact.
- Quick add: a text field at the bottom of the day list. `NSDataDetector` (Foundation) finds the date;
  the rest is the title. No time = all-day on the selected day. Duration 1 h (or detector duration).
  Goes to the default calendar for new events. Parser in Core, tested.
- Hebrew: `Calendar(identifier: .hebrew)`, gematria numerals via locale `he@numbers=hebr` (verified:
  "י״ט תשרי ה׳תשפ״ז"). Holidays computed in Core from Hebrew dates (Rosh Hashana, Yom Kippur, Sukkot,
  Simchat Torah, Hanukkah, Tu BiShvat, Purim, Pesach, Yom HaShoah, Yom HaZikaron, Yom HaAtzmaut,
  Lag BaOmer, Yom Yerushalayim, Shavuot, Tisha B'Av), with Israeli postponement rules. Tested against
  known dates. Offline, no permission. Two toggles in Settings, both OFF by default (user: optional).
  User chose: Hebrew letters, built-in holidays, agenda-list week view.
- Hotkey ⌥⌘P: Carbon `RegisterEventHotKey` (no Accessibility permission). Opens the existing
  MenuBarExtra panel by clicking its `NSStatusBarButton` (public AppKit type), so the app shape stays
  as is. Toggle in Settings (on by default). Fixed shortcut, not rebindable.
- Week view: Month/Week switch in the panel header (a view mode, not a setting; remembered).
  Week = 7 rows (day name + date + Hebrew date) with that day's events under each; ‹ › moves by week.
- Live updates: `EKEventStoreChanged` notification, no polling.

## Phases
- [x] 1 Core, test-first: `HebrewDates` (day label, holidays + rules), `QuickAddParser`, week range
- [x] 2 `EventService` (EventKit wrapper: access, events + reminders for a range, create event, complete reminder)
- [x] 3 Panel: dots, day selection, day list, quick add, reminders, Hebrew row, holidays
- [x] 4 Week view + header switch
- [x] 5 Hotkey ⌥⌘P
- [x] 6 Settings: Calendars (events toggle, calendar picker), Reminders, Hebrew, Shortcut sections
- [x] 7 Verify: 29 tests, window frames logged, user verified in app: check.sh, previews, run app, grant permissions, manual checklist
- [x] 8 PR, merge, publish public, PROJECT-CONTEXT, lessons

## Review
- Shipped all six. Surprises: MenuBarExtra shrinks its window late and toward the bottom (fixed with FitWindowHeight); ad-hoc re-signing drops TCC grants (designated requirement); NSDataDetector reads "10:30" as the next 10:30.

---

# Plan: `mac-calendar` — menu bar calendar (new plugin)

Status: PR https://github.com/RohiRIK/mac-calendar-dev/pull/1 (2026-09-29). Previews + manual checks pending. Branch `feat/calendar-panel` in `plugins/mac-calendar`.

## Requirements (explicit)
- Menu bar item; click it and a calendar appears. Simple and efficient.

## Decisions (inferred, cheap to change)
- Menu bar label = today's date as text ("Tue 29"), updates at midnight (`NSCalendarDayChanged`).
- Panel (`.window` style, system-menu look): month title, ‹ Today › buttons, weekday row, 6×7 day grid.
  Today = accent circle; other-month days dimmed. Week start + names from system locale.
- Keys: ← / → month, T = today.
- Footer: Open Calendar (Calendar.app), Open at Login toggle, Quit (⌘Q).
- Dropped: events (EventKit permission + more UI), Settings window, onboarding. Add if asked.

## Phases
- [x] 2 Scaffold: SwiftPM `MacCalendar` / `MacCalendarUI` / `MacCalendarCore`, scripts from mac-network
- [x] 3 Core test-first: `MonthGrid.days(for:calendar:today:)` → 42 cells; tests for Sunday/Monday start, leap Feb, today flag
- [~] 4 UI: panel done; previews blocked on Xcode MCP approval
- [x] 5 Shell: menu bar label, midnight refresh, Quit, Open at Login
- [x] 6 Audit + 7 `check.sh`, launch app, private `mac-calendar-dev` repo, PR + report
- [x] 8 Record: PROJECT-CONTEXT.md, plugins.md, lessons

---

# Plan: port rohi.network to macOS as `mac-network`

Status: Phase 3 in review: https://github.com/RohiRIK/mac-network/pull/1 (55 tests, previews rendered). Manual checks pending.

Source: https://github.com/RohiRIK/rohi.network (Omarchy bar widget: `Panel.qml` 2182 lines,
`Model.js` 25 pure helpers, `settings.py` nmcli wrapper, 84 tests).
Target: native SwiftUI `MenuBarExtra` app. Repo: https://github.com/RohiRIK/mac-network (private).
Linux-to-macOS mapping: `.claude/skills/PortOmarchyPlugin/Mapping.md`.

## Decisions

- Everything lives in this workspace. Plugin repos under `plugins/<name>/`, skills in `.claude/skills/`.
- No personal names in repo names.
- Build cache outside Drive (`~/Library/Caches/macplugins/<name>`).
- Band switching dropped (no macOS API). Band shown read-only.
- Admin actions (static IP, forget network) via `osascript ... with administrator privileges`.

## Phase 0: Workspace

- [x] `AGENTS.md` + `CLAUDE.md` (`@AGENTS.md`)
- [x] Skill `PortOmarchyPlugin` (Port workflow + Mapping.md)
- [x] Skill `MacAppBuild` (Scaffold.md, gotchas)
- [x] Skill `MacUX` (Principles, Patterns (type-checked), Review checklist)
- [x] `plugins.md`, `tasks/lessons.md`

## Phase 1: Repo

- [x] `plugins/mac-network/` SwiftPM package, `MacNetwork` + `MacNetworkCore` + tests
- [x] `scripts/test.sh` (CLT-aware), `scripts/bundle.sh`, CI on `macos-latest`
- [x] Bundle launches as menu bar extra (process confirmed; screenshot blocked, see Review)
- [x] `gh repo create mac-network --private`, pushed

## Phase 2: Logic port (test-first)

- [x] Port remaining 23 `Model.js` helpers + their cases from `test/model.test.js`
- [x] `IPSettings` over `networksetup` with injected runner; port every case from `test/settings.test.py`
- [x] `PublicIP` via URLSession, IPv4 validated
- [x] `WiFiService` over CoreWLAN (scan, connect, power, link info) + Location auth

## Phase 3: UI (load MacUX)

- [x] Panel: header + toggle, details grid (IP, speed, band, ping, loss, rate), Wi-Fi list
- [x] Public IPv4 row, click-only
- [x] IP settings screen: service picker, DHCP/Manual, "Use current IP", Save
- [x] Keys s / r / w / Esc; permission + error states (PR #1; manual checks pending)

## Phase 4: Verify + ship

- [ ] Tests green, Review.md checklist on the running app (user screenshot)
- [ ] README: features, dropped features, install, permissions
- [ ] GitHub Release with zipped `.app`

## Review (Phase 0-1)

- Skills and scaffold verified by real build: patterns type-check on macOS 14 target, 3 ported tests pass, `.app` launches.
- Found and recorded: CLT has no `Testing` on search path; `.build` 461 MB in Drive; background session cannot screenshot.

## Review (Phase 2)

- Ported: formatting, Wi-Fi list sort/sections, credentials rule, forget rule, throughput, ping windows,
  settings validation (all settings.test.py cases), public IP. 49 tests incl. live read-only networksetup
  and an osascript injection test.
- Not ported (Linux-only): nmcli/iw parsers, band selection, enterprise nmcli script, NM failure reasons
  (CoreWLAN errors get mapped in Phase 3 when the connect UI exists).
- macOS differences: one static address per service; gateway required for manual.
- Unverified until run in the UI: admin save (needs password prompt), CoreWLAN scan/connect, Location prompt.
