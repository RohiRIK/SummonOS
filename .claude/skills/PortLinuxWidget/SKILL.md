---
name: PortLinuxWidget
description: "Port a Linux bar widget (Quickshell/QML, Waybar, Omarchy plugins with manifest.json, nmcli/iw helpers) into a native macOS menu bar app. USE WHEN porting, converting, or migrating a Linux widget or script to macOS. NOT FOR building a new app from scratch (use MacAppArchitecture, then MacAppBuild)."
category: workflow
effort: high
domain: dev
---

# PortLinuxWidget

Turns a Linux bar widget (often a Quickshell/Omarchy plugin) into a SwiftUI menu bar app with the same features, keys, and tests.

## Workflow Routing

| Workflow | Trigger | File |
|----------|---------|------|
| **Port** | "port this plugin", "convert to macOS", a GitHub URL of an Omarchy plugin | `Workflows/Port.md` |

## Quick Reference

- Omarchy plugin anatomy: `manifest.json` (id, kinds, entryPoints) + `Panel.qml` (UI) + pure JS helpers (`Model.js`) + shell/Python helpers that call Linux tools.
- Port order: inventory, map, logic + tests, UI, verify. Never start with UI.
- Pure JS helpers port 1:1 to a Swift `enum` of static functions. Port their tests first.
- Every Linux command needs a macOS equivalent in `Mapping.md`. No row = research it, then add the row.
- Build and bundle rules: `MacAppBuild` skill. Views: `MacUX` skill.

## Gotchas

- `Quickshell.Networking` and `nmcli` have no macOS CLI twin for Wi-Fi. Use CoreWLAN in-process.
- SSID/BSSID read as nil on macOS 14+ until the app has Location authorization.
- `networksetup -set*` needs admin. Changing system settings means an auth prompt. Say so in the UI.
- Some Linux features have no macOS API (forcing Wi-Fi band). Drop them and write why in the README. Never fake them.
- JS `toFixed` rounds halves away from zero; Swift `String(format: "%.1f")` rounds exact halves to even (4.25 -> "4.2" vs "4.3"). Round with `.toNearestOrAwayFromZero` first. Port a `toFixed` test case to catch it.
- Nerd Font glyphs (`󰤨`) become SF Symbols. Test each name with `NSImage(systemSymbolName:accessibilityDescription:) != nil`; a wrong name renders nothing and does not error.
- Keep the source plugin's security notes (click-only network calls, secrets never in argv). They still apply.

## Examples

**Example 1: Port a network widget**
```
User: "port https://github.com/RohiRIK/rohi.network"
→ Port workflow → clone, inventory table, mapping gaps filled
→ plan in tasks/todo.md → on approval: plugins/<name>/ repo, logic + tests, UI
```
