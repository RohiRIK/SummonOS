# Layers, state, concurrency, lifecycle

## Package layout (SwiftPM)

```
Sources/
  <App>Core/   pure logic + services (APIClient, stores, tool wrappers). No SwiftUI. Tested.
  <App>UI/     views + @Observable model + #Previews. Library product (previews need it).
  <App>/       @main App only.
Tests/<App>CoreTests/
```

- Services take their side effects as injected values (`Runner`, `URLSession`, `token:` closure) so
  tests pass fakes. No protocols with one implementation; a closure or struct field is enough.
- Pure helpers are `enum Namespace { static func … }`. Domain types are `struct`, `Sendable`, `Equatable`.
- Handlers/actions in the model stay thin; business rules live in `Core`.

## State

- One `@MainActor @Observable final class <Feature>Model` per surface. Views take it as `let` or
  `@Bindable`. Views hold only view-local state (`@State` for hover, focus, expansion).
- Give the model a `static func preview(...)` with fake data and `init(live: false)` that skips
  services, so every `#Preview` renders without network, CoreWLAN, or permissions.
- Derived values are computed properties, not stored copies that can go stale.
- Loading/error per item where the user acted (row spinner, row error), not one global banner.

## Concurrency

- UI model on `@MainActor`. Blocking or slow work (`Process`, CoreWLAN scan, file I/O, big decode)
  runs off-main: `async` service methods, `actor` for shared mutable state, `Task.detached` only to
  wrap a blocking synchronous API.
- Cancel what you start: keep the `Task` and cancel it on disappear/quit; loops check `Task.isCancelled`.
- **One poll loop, restarted, never called alongside.** Keep `pollTask`; open/close, a refresh key, or a
  finished action cancel and restart it. Calling `refresh()` next to a running loop overlaps work
  (double-counted rates, duplicate pings). Reference: `NetworkModel.refreshNow(rescan:)` in mac-network.
- Service wrapping a non-Sendable Apple client (CoreWLAN, EventKit): make it an `actor`, not
  `@unchecked Sendable` + `Task.detached`. Calls become async and run off-main automatically.
- View reads keyed on a selection: `.task(id: selection)`, not `onChange` + `Task {}` (older result can win).
- Concurrent independent calls: `async let` or `withTaskGroup`, not sequential awaits.
- Swift 6 strict mode stays on. `@unchecked Sendable` only for a thread-safe Apple type that is not
  annotated, with a `ponytail:` comment.
- Deep rules: `swift-concurrency-pro`.

## Lifecycle

- Quit from a menu: `NSApplication.shared.terminate(nil)` (runs `applicationWillTerminate`).
- Clean up pollers, file handles, child processes on terminate. Leaked timers keep the app busy.
- Menu bar app with windows: re-apply `.accessory` activation policy after closing a window if you
  switched to `.regular` to show it.

## Logging

- `Logger(subsystem: <bundle id>, category: "<area>")` from `os`. `.debug` for chatter, `.info` for
  state changes, `.error` for failures.
- Mark user data `privacy: .private` (the default); counts and error strings `privacy: .public`.
- Read logs: `/usr/bin/log show --last 10m --predicate 'subsystem == "<bundle id>"' --info --debug`
  (`log` alone is a zsh builtin).
