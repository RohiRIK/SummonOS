import Darwin
import Foundation
import os

/// Calls `onChange` once when observation is registered, then when a file or folder changes through a kqueue
/// vnode source: no polling, no wakeups while nothing happens. The first call is a readiness/reconciliation
/// signal, not a filesystem event: owners must read current state to cover mutations made during startup.
/// A folder reports added, removed and renamed entries; a file reports writes. When a watched file is deleted
/// or replaced (renamed over), `isGone` turns true and the owner opens a new watch.
public final class FileWatch: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let gone = OSAllocatedUnfairLock(initialState: false)

    public var isGone: Bool { gone.withLock { $0 } }

    /// Watch an ancestor until a not-yet-created directory exists, then rearm on the new directory.
    /// Missing log files need a directory wakeup; kqueue cannot watch a path that does not exist.
    public static func nearestExistingDirectory(to directory: URL) -> URL? {
        var candidate = directory.standardizedFileURL
        var isDirectory: ObjCBool = false
        while !FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            let parent = candidate.deletingLastPathComponent()
            guard parent != candidate else { return nil }
            candidate = parent
        }
        return candidate
    }

    public init?(_ url: URL, queue: DispatchQueue = .global(qos: .utility), onChange: @escaping @Sendable () -> Void) {
        let fd = open(url.path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else { return nil }
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename],
                                                           queue: queue)
        let source = source
        let gone = gone
        source.setEventHandler {
            if !source.data.isDisjoint(with: [.delete, .rename]) {
                gone.withLock { $0 = true }
                source.cancel()
            }
            onChange()
        }
        source.setCancelHandler { close(fd) }
        // resume() starts registration asynchronously. Reconcile only once kevent is installed so a change
        // between the owner's initial read and registration cannot leave that owner's snapshot stale.
        source.setRegistrationHandler(handler: onChange)
        source.resume()
    }

    deinit { source.cancel() }
}
