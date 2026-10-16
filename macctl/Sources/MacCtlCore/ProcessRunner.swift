import Foundation

/// The real `Runner`: runs a tool with `Foundation.Process`, off the caller's executor.
///
/// - stdout and stderr are drained while the process runs (no pipe-buffer deadlock).
/// - On timeout the process gets SIGTERM, then SIGKILL two seconds later, and the call throws
///   `MacCtlError.commandFailed` with exit code -1.
/// - Task cancellation terminates the process and throws `CancellationError`.
public enum ProcessRunner {
    public static func live(timeout: Duration = .seconds(30)) -> Runner {
        { executable, arguments in
            try await run(executable, arguments, timeout: timeout)
        }
    }

    static func run(_ executable: String, _ arguments: [String], timeout: Duration) async throws -> CommandResult {
        let execution = Execution(executable: executable, arguments: arguments, timeoutSeconds: seconds(timeout))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CommandResult, any Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result { try execution.runBlocking() })
                }
            }
        } onCancel: {
            execution.cancel()
        }
    }

    static func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return max(0, Double(parts.seconds) + Double(parts.attoseconds) / 1e18)
    }
}

/// One process run. Mutable state is guarded by `lock`; Process and Pipe are only touched through it
/// or from the single thread that runs `runBlocking`.
private final class Execution: @unchecked Sendable {
    let executable: String
    let arguments: [String]
    let timeoutSeconds: Double

    private let process = Process()
    private let stdoutPipe = Pipe()
    private let stderrPipe = Pipe()
    private let lock = NSLock()
    private var launched = false
    private var timedOut = false
    private var cancelled = false
    private var stderrData = Data()

    init(executable: String, arguments: [String], timeoutSeconds: Double) {
        self.executable = executable
        self.arguments = arguments
        self.timeoutSeconds = timeoutSeconds
    }

    /// Short command text for error messages (scripts can be long).
    var commandText: String {
        let name = (executable as NSString).lastPathComponent
        let text = ([name] + arguments).joined(separator: " ")
        return text.count > 200 ? String(text.prefix(200)) + "…" : text
    }

    func runBlocking() throws -> CommandResult {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        if lock.withLock({ cancelled }) { throw CancellationError() }

        do {
            try process.run()
        } catch {
            throw MacCtlError.commandFailed(
                command: commandText, exitCode: -1,
                stderr: "could not start: \(error.localizedDescription)"
            )
        }
        lock.withLock {
            launched = true
            if cancelled { terminateLocked() }
        }

        let timer = DispatchWorkItem { [self] in expire() }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds, execute: timer)

        // Drain stderr on another thread while this thread drains stdout.
        let group = DispatchGroup()
        DispatchQueue.global(qos: .userInitiated).async(group: group) { [self] in
            let data = (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
            lock.withLock { stderrData = data }
        }
        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        group.wait()
        exited.wait()
        timer.cancel()

        let state = lock.withLock { (timedOut, cancelled, stderrData) }
        if state.1 { throw CancellationError() }
        if state.0 {
            throw MacCtlError.commandFailed(
                command: commandText, exitCode: -1,
                stderr: "timed out after \(Int(timeoutSeconds.rounded())) seconds"
            )
        }
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: state.2, as: UTF8.self)
        )
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if launched { terminateLocked() }
        }
    }

    private func expire() {
        let fired: Bool = lock.withLock {
            guard launched, process.isRunning else { return false }
            timedOut = true
            terminateLocked()
            return true
        }
        guard fired else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) { [self] in
            lock.withLock {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
    }

    /// Caller holds `lock`. `terminate()` raises if the process was never launched, hence `launched`.
    private func terminateLocked() {
        if launched, process.isRunning { process.terminate() }
    }
}
