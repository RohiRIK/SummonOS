---
type: Plan
title: "mac-network: port of rohi.network"
description: Port of the rohi.network Linux bar widget to a native macOS menu bar app.
tags: [mac-network, port]
status: done
created: 2026-09-29
---

# Plan: port rohi.network to macOS as `mac-network`

Status: Phase 3 in review: https://github.com/RohiRIK/mac-network/pull/1 (55 tests, previews rendered). Manual checks pending.

Source: https://github.com/RohiRIK/rohi.network (Omarchy bar widget: `Panel.qml` 2182 lines,
`Model.js` 25 pure helpers, `settings.py` nmcli wrapper, 84 tests).
Target: native SwiftUI `MenuBarExtra` app. Repo: https://github.com/RohiRIK/mac-network (private).
Linux-to-macOS mapping: `.claude/skills/PortLinuxWidget/Mapping.md`.

## Decisions

- Everything lives in this workspace. Plugin repos under `plugins/<name>/`, skills in `.claude/skills/`.
- No personal names in repo names.
- Build cache outside Drive (`~/Library/Caches/macplugins/<name>`).
- Band switching dropped (no macOS API). Band shown read-only.
- Admin actions (static IP, forget network) via `osascript ... with administrator privileges`.

## Phase 0: Workspace

- [x] `AGENTS.md` + `CLAUDE.md` (`@AGENTS.md`)
- [x] Skill `PortLinuxWidget` (Port workflow + Mapping.md)
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
