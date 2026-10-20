# System integration: tools, admin, permissions, polling

## Order of preference for a capability

1. A native framework in-process (CoreWLAN, EventKit, IOKit, `NSWorkspace`, `SCDynamicStore`).
2. A built-in command-line tool via `Process` (`networksetup`, `pmset`, `defaults`, `mdls`, `ioreg`).
3. AppleScript / JXA via `NSAppleScript` or `osascript` (app automation, admin prompt).
4. A Homebrew tool (`ffmpeg`, `yt-dlp`) only if the user already has it; detect and explain, never auto-install.
5. A privileged helper (`SMAppService.daemon`) only when an admin prompt per action is not acceptable.

## Running tools (`Process`)

- Absolute path (`/usr/sbin/networksetup`), arguments as an array. Never build a shell string.
- Off the main actor, with a timeout; read stdout and stderr; non-zero exit → error with stderr text.
- Enforce deadlines with a bounded termination grace period and escalation for the invocation's process
  group. Propagate cancellation, close unrelated inherited descriptors, and cap output before buffering it.
  Test a TERM-ignoring parent, a descendant holding stdout open, and a noisy child. Summon's
  `Sources/SummonCore/ProcessExecutor.swift` provides the current implementation; detached sessions remain outside cleanup.
- Some tools report failure on stdout with exit 0 (`networksetup -setairportnetwork`). Parse the output.
- Secrets go through stdin or an in-process API, never argv.
- Inject the runner (`typealias Runner = @Sendable (String, [String]) async throws -> String`) so
  tests use a fake and never touch the real system.
- Reference implementation: `plugins/mac-network/Sources/MacNetworkCore/Shell.swift`.

## Recoverable mutations across CLI processes

- Hold an interprocess lock across read/plan, backup, writes and completion recording. Atomic file replacement
  protects one write; it does not serialize a transaction or prevent two writers allocating the same backup ID.
- Save a pending journal before changing state, then record completed steps and completed/failed outcome.
  Only a completed undo consumes its original operation. Preserve a recovery reference on partial failure;
  a failed or stale capture does not establish recovery coverage. Test failing writes and concurrent processes.
- Migrate stored preferences under the same lock as explicit changes, and leave an already valid choice in
  place. Resolve a missing preference separately from corrupt data so migration cannot broaden authority.

## Admin actions

- One password prompt per user action: `osascript` with `do shell script … with administrator privileges`.
  Pass values as argv after `--`, build the command with `quoted form of`. Never splice values into
  script text. Covered by an injection test in mac-network.
- User cancel returns `-128`; treat it as a silent no-op, not an error.
- Tell the user before the prompt appears (ellipsis on the button, `.help()` text).

## Permissions (TCC)

- Add the usage string to Info.plist (`NSLocationUsageDescription`, `NSCameraUsageDescription`, …).
- Check status first; request only from a user action and only when `notDetermined`.
- Denied/restricted: show why the feature is off and a button that opens the right System Settings pane
  (`x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices`).
- **Menu bar apps need Location "Always".** When-In-Use (status 4) is granted but the app is never
  "in use", so CoreWLAN SSIDs stay nil. Call `requestAlwaysAuthorization()`; treat only
  `.authorizedAlways` as granted. After the first decision macOS never prompts again: the button must
  open System Settings > Location Services.
- Prompts work only from the bundled `.app`. Command-line sidecars cannot reliably request Location.
- Ad-hoc signed rebuilds can reset grants; `tccutil reset <Service> <bundle id>` to retest first-run.

## Polling vs events

- Prefer notifications: `NSWorkspace.didActivateApplicationNotification`, `SCDynamicStore` for network
  changes, `NSWorkspace.didWakeNotification`, FSEvents / `DispatchSource` for files.
- Poll when no event exists: fast (1-2 s) only while a panel is open, slow (10-60 s) otherwise, stop on sleep.
- Poll results carry metadata only. Load heavy data (images, file contents) on demand per item.
- Bounded caches with TTL; do not cache failures permanently.
