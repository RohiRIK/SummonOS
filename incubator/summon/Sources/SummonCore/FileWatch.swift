import Darwin
import Foundation
import os

/// Calls `onChange` when a file or folder changes, through a kqueue vnode source: no polling, no wakeups while
/// nothing happens. A folder reports added, removed and renamed entries; a file reports writes. When a watched file
/// is deleted or replaced (renamed over), `isGone` turns true and the owner opens a new watch.
public final class FileWatch: @unchecked Sendable {
    private let source: DispatchSourceFileSystemObject
    private let gone = OSAllocatedUnfairLock(initialState: false)

    public var isGone: Bool { gone.withLock { $0 } }

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
        source.resume()
    }

    deinit { source.cancel() }
}
