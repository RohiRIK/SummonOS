import Darwin
import Foundation

/// Reads only complete JSONL records appended since the previous read. A new inode, a truncated
/// file, or an in-place rewrite starts a new stream; the caller can then reconcile identities.
/// No wall-clock timestamp is used as a high-water mark: writers can append out of time order.
public struct EventLogCursor: Sendable {
    public struct Batch: Sendable {
        public let events: [LoggedEvent]
        public let reset: Bool
    }

    private struct FileState: Equatable, Sendable {
        let device: UInt64
        let inode: UInt64
        let size: UInt64
        let changedSeconds: Int
        let changedNanoseconds: Int
    }

    private let file: URL
    private var state: FileState?
    private var offset: UInt64 = 0

    public init(file: URL) { self.file = file }

    public mutating func read() throws -> Batch {
        let descriptor = open(file.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        if descriptor < 0 {
            if errno == ENOENT {
                let hadFile = state != nil
                state = nil
                offset = 0
                return Batch(events: [], reset: hadFile)
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let current = FileState(device: UInt64(info.st_dev), inode: UInt64(info.st_ino),
                                size: UInt64(info.st_size), changedSeconds: Int(info.st_ctimespec.tv_sec),
                                changedNanoseconds: Int(info.st_ctimespec.tv_nsec))
        let reset = state == nil || state?.device != current.device || state?.inode != current.inode
            || current.size < offset || (state?.size == current.size &&
                                          (state?.changedSeconds != current.changedSeconds ||
                                           state?.changedNanoseconds != current.changedNanoseconds))
        if reset { offset = 0 }
        let start = reset ? 0 : offset
        state = current
        guard current.size > start else { return Batch(events: [], reset: reset) }
        try handle.seek(toOffset: start)
        let bytes = try handle.readToEnd() ?? Data()
        guard let newline = bytes.lastIndex(of: 10) else { return Batch(events: [], reset: reset) }
        offset = start + UInt64(newline - bytes.startIndex + 1)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = bytes[...newline].split(separator: 10).compactMap { line in
            try? decoder.decode(LoggedEvent.self, from: Data(line))
        }
        return Batch(events: events, reset: reset)
    }
}
