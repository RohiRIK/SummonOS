import Foundation

/// Refreshes appearance and runs `killall <process>` once per distinct effect.
/// Logout/relaunch are advisory; the engine turns them into notes for the user.
public struct KillallRestarter: Restarter {
    private let runner: Runner

    public init(runner: @escaping Runner) {
        self.runner = runner
    }

    public func run(_ effects: Set<SideEffect>) async throws {
        #if os(macOS)
        if effects.contains(.refreshAppearance) {
            // CoreUI listens for both names. Keep this in the audited effect path so undo/recovery
            // refresh colors too; apps that ignore the notifications still need reopening.
            let center = DistributedNotificationCenter.default()
            for name in ["AppleAquaColorVariantChanged", "AppleColorPreferencesChangedNotification"] {
                center.postNotificationName(Notification.Name(name), object: nil, userInfo: nil, deliverImmediately: true)
            }
        }
        #endif
        var processes = Set<String>()
        for effect in effects {
            guard case .restart(let process) = effect else { continue }
            processes.insert(process)
        }

        // Try every restart, then report the first failure.
        var firstError: MacCtlError?
        for process in processes.sorted() {
            let result = try await runner(Tool.killall, [process])
            if result.exitCode == 0 { continue }
            let text = result.stderr + result.stdout
            // Not running means there is nothing to restart; it picks up the new value on next launch.
            if result.exitCode == 1, text.contains("No matching processes") { continue }
            if firstError == nil {
                firstError = SystemBackend.failure("killall \(process)", result)
            }
        }
        if let firstError { throw firstError }
    }
}
