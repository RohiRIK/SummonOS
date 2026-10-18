import Foundation
@testable import MacCtlCore

/// A fake `Runner` that records every call and answers from a handler. Never runs a process.
final class RecordingRunner: @unchecked Sendable {
    struct Call: Equatable, Sendable {
        let executable: String
        let arguments: [String]
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private let handler: @Sendable (String, [String]) -> CommandResult

    /// Answers every call with `result` (default: exit 0, empty output).
    convenience init(result: CommandResult = CommandResult(exitCode: 0, stdout: "")) {
        self.init { _, _ in result }
    }

    init(handler: @escaping @Sendable (String, [String]) -> CommandResult) {
        self.handler = handler
    }

    var calls: [Call] {
        lock.withLock { recorded }
    }

    var runner: Runner {
        { [self] executable, arguments in
            record(executable, arguments)
        }
    }

    private func record(_ executable: String, _ arguments: [String]) -> CommandResult {
        lock.withLock { recorded.append(Call(executable: executable, arguments: arguments)) }
        return handler(executable, arguments)
    }
}
