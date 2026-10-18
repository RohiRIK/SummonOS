---
name: MacAppArchitecture
description: "Decide and build the structure of a native macOS app: app shape (menu, panel, window, NSPanel), layers, state, concurrency, backend/API calls, persistence and secrets, system tools, admin actions, polling, lifecycle, logging. USE WHEN planning a new macOS app or feature, calling an API or shell tool from Swift, storing data or tokens, or adding background work. NOT FOR view styling (use MacUX) or build/release (use MacAppBuild)."
category: reference
effort: medium
domain: dev
---

# MacAppArchitecture

How a plugin is put together behind the views. Decide the shape first, then fill the layers.

## Quick Reference

- **Shape first:** `AppShapes.md`: menu vs `.window` panel vs window app vs `NSPanel`; activation policy; Settings window. A wrong shape is the most expensive mistake.
- **Layers, state, concurrency, lifecycle:** `Layers.md`. `Core` (pure logic + services, tested) / `UI` library (views + `@Observable` model, previews) / thin `@main` executable.
- **Talking to backends:** `Backend.md`: `APIClient` with async/await, DTO to domain at the boundary, typed errors with status, curl first, OAuth via `ASWebAuthenticationSession`.
- **Storing things:** `Data.md`: `@AppStorage` for prefs, atomic JSON in Application Support for user data, Keychain for secrets, SwiftData only for relational data.
- **System tools, admin, permissions, polling:** `System.md`.
- Deep SwiftUI questions: `swiftui-expert-skill`. Actors, `Sendable`, cancellation: `swift-concurrency-pro`.

## Gotchas

- Frontend-first: keep behavior in the model/services unless it needs the OS. Views never call `Process`, `URLSession`, or the Keychain directly.
- Never store user data in the repo, the bundle, or `cwd`. Use `URL.applicationSupportDirectory/<bundle id>/`.
- Missing file means use the default. Corrupt file means throw and show it. Never silently overwrite user data.
- Secrets never go in `UserDefaults`, JSON, logs, or argv (`ps` shows argv). Keychain in-process, stdin for tools.
- `Process` must not run on the main actor, and always needs a timeout. A tool that exits 0 can still have failed (`networksetup` does): parse stdout.
- Poll only while visible (1-5 s); slow down or stop when hidden. Prefer OS notifications (`NSWorkspace`, `SCDynamicStore`, FSEvents).
- Every cache is bounded, and failures are not cached forever.
- Location, camera and similar TCC prompts only appear from a bundled `.app` with a usage string, and only when triggered by a user action.
- An `LSUIElement` app has no Dock icon and no app menu: its panel footer **must** offer `Settings…` (⌘,) and `Quit <App>` (⌘Q), or the user cannot quit it. "Open at Login" goes in the Settings window (AGENTS.md › Panel vs Settings window). mac-network shipped without Quit until the audit.
- `NSDataDetector` resolves a time with no date or am/pm ("10:30") to its *next* occurrence: 22:30 after 10:30 in the morning. Read `HH:mm` from the text yourself (mac-calendar `QuickAdd.clock`). Date-only phrases come back at 12:00; decide "has a time" from the text.
- `@AppStorage` has no `[String]` type on macOS 15; store a comma-joined `String`.
- EventKit: request access only from a user action (`requestFullAccessToEvents` / `…ToReminders`, completion-handler form under Swift 6), `NSCalendarsFullAccessUsageDescription` / `NSRemindersFullAccessUsageDescription` in Info.plist, reload on `.EKEventStoreChanged`.
- Opening Ghostty from an app: `open -na Ghostty --args -e …` starts a *second* Ghostty process each time (extra Dock icon, stray window, tabs merging oddly). If Ghostty is running, use its AppleScript (1.3+): `new surface configuration` + `new window with configuration`, argv joined with `quoted form of`. Use `open -na` only on a cold start (Summon `LaunchPlan.swift`).
- A new feature is done only when it is reachable (menu, key, button), persisted if it should be, and verified running.

## Examples

**Example 1: A GitHub notifications menu bar app**
```
→ AppShapes: .window panel (list + live data) + Settings window for the token
→ Backend: APIClient + NotificationDTO → Notification; token in Keychain; poll 60 s only while panel open
→ Data: read-state in JSONStore; → MacUX for the panel, MacAppBuild to ship
```
