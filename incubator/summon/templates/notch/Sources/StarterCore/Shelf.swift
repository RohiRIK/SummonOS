import Foundation

/// The starter's job: a shelf of files dropped into the notch, to drag out again later. It holds the files'
/// locations, never copies; newest first, no duplicates, at most `capacity`.
public struct Shelf: Equatable, Sendable {
    public static let capacity = 24
    public private(set) var files: [URL]

    public init(files: [URL] = []) {
        self.files = []
        add(files)
    }

    /// Adds files to the front; a file already on the shelf moves to the front.
    public mutating func add(_ urls: [URL]) {
        for url in urls.reversed() {
            let file = url.standardizedFileURL
            files.removeAll { $0 == file }
            files.insert(file, at: 0)
        }
        if files.count > Shelf.capacity { files.removeLast(files.count - Shelf.capacity) }
    }

    public mutating func remove(_ url: URL) {
        files.removeAll { $0 == url.standardizedFileURL }
    }

    public mutating func clear() {
        files.removeAll()
    }

    /// Drops files that were moved or deleted since they were shelved.
    public mutating func prune(exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }) {
        files.removeAll { !exists($0) }
    }

    /// Paths, for UserDefaults.
    public var stored: [String] { files.map(\.path) }

    public init(stored: [String]) {
        self.init(files: stored.map { URL(fileURLWithPath: $0) })
    }
}
