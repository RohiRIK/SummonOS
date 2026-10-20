import Darwin
import Foundation

/// Advisory interprocess lock. The lock file remains in place: removing it would create two lock domains.
public final class FileLease: Sendable {
    private let descriptor: Int32

    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { close(descriptor) }

    public static func acquire(_ file: URL, timeout: TimeInterval = 5) async throws -> FileLease {
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            try Task.checkCancellation()
            if let lease = try attempt(file) { return lease }
            guard ProcessInfo.processInfo.systemUptime - start < timeout else { throw FileLeaseError.busy(file.path) }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// For short store updates and immediate rejection of overlapping scheduled jobs.
    public static func acquireSync(_ file: URL, timeout: TimeInterval = 5) throws -> FileLease {
        let start = ProcessInfo.processInfo.systemUptime
        while true {
            if let lease = try attempt(file) { return lease }
            guard ProcessInfo.processInfo.systemUptime - start < timeout else { throw FileLeaseError.busy(file.path) }
            Thread.sleep(forTimeInterval: 0.01)
        }
    }

    private static func attempt(_ file: URL) throws -> FileLease? {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let fd = open(file.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG, info.st_uid == getuid() else {
            close(fd)
            throw StateFileError.invalid(file, "lock must be a regular file owned by this user")
        }
        if flock(fd, LOCK_EX | LOCK_NB) == 0 { return FileLease(descriptor: fd) }
        let code = errno
        close(fd)
        if code == EWOULDBLOCK { return nil }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    public func hold() {} // Keep the lease alive through the enclosing operation's defer.
}

public enum FileLeaseError: Error, CustomStringConvertible {
    case busy(String)
    public var description: String {
        switch self { case .busy(let path): return "Another operation holds \(path); try again when it finishes." }
    }
}

public enum StateFileError: Error, CustomStringConvertible {
    case invalid(URL, String)
    public var description: String {
        switch self {
        case .invalid(let file, let detail): return "Cannot read \(file.path): \(detail). The file was preserved; repair or restore it before changing this state."
        }
    }
}

enum StateFile {
    static func load<T: Decodable>(_ type: T.Type, at file: URL, default fallback: T,
                                   decoder: JSONDecoder = .init()) throws -> T {
        do {
            return try decoder.decode(type, from: Data(contentsOf: file))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return fallback
        } catch {
            throw StateFileError.invalid(file, String(describing: error))
        }
    }
}
