import Foundation

/// Runs `killall <process>` once per distinct restart effect, in name order.
/// `.logout` is ignored here; the engine turns it into a note for the user.
public struct KillallRestarter: Restarter {
    private let runner: Runner

    public init(runner: @escaping Runner) {
        self.runner = runner
    }

    public func run(_ effects: Set<SideEffect>) async throws {
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
