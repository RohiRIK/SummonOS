import Darwin
import Foundation

/// A synchronous, idempotent release lets `defer` protect an async transaction, including cancellation.
public final class TransactionLease: @unchecked Sendable {
    private let lock = NSLock()
    private var releaseAction: (@Sendable () -> Void)?

    init(release: @escaping @Sendable () -> Void) { releaseAction = release }
    public func release() {
        let action = lock.withLock {
            let action = releaseAction
            releaseAction = nil
            return action
        }
        action?()
    }
    deinit { release() }
}

/// Default for injected stores; filesystem stores use flock to include other CLI processes.
final class InProcessTransactionLock: @unchecked Sendable {
    static let shared = InProcessTransactionLock()
    private let lock = NSLock()
    private var held = false

    func acquire() async throws -> TransactionLease {
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        while true {
            try Task.checkCancellation()
            let acquired = lock.withLock {
                if held { return false }
                held = true
                return true
            }
            if acquired {
                return TransactionLease { [self] in lock.withLock { held = false } }
            }
            guard ContinuousClock.now < deadline else { throw MacCtlError.transactionBusy }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

enum FileTransactionLock {
    static func acquire(at file: URL, timeout: Duration = .seconds(30)) async throws -> TransactionLease {
        let descriptor = open(file.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var transferred = false
        defer { if !transferred { close(descriptor) } }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            throw MacCtlError.invalidProfile("transaction lock must be a regular file owned by this user")
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while true {
            try Task.checkCancellation()
            if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                transferred = true
                return TransactionLease {
                    flock(descriptor, LOCK_UN)
                    close(descriptor)
                }
            }
            guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            guard ContinuousClock.now < deadline else { throw MacCtlError.transactionBusy }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}
