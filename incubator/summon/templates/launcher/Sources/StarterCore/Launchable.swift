import Foundation

/// One thing the launcher can open. The starter's job is opening apps; add your own kinds of item next to it.
public struct Launchable: Identifiable, Equatable, Hashable, Sendable {
    public var id: String { path }
    public var title: String
    /// The file to open (for an app, its `.app` bundle).
    public var path: String

    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }
}

/// Finds the apps in the usual folders, one level deep (so `Utilities` counts), without duplicates.
public enum AppCatalog {
    public static var standardFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["/Applications", "/System/Applications", home.appendingPathComponent("Applications").path]
            .map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public static func scan(_ folders: [URL] = standardFolders) -> [Launchable] {
        var seen = Set<String>()
        var found: [Launchable] = []
        func add(_ url: URL) {
            let title = url.deletingPathExtension().lastPathComponent
            guard seen.insert(title.lowercased()).inserted else { return }
            found.append(Launchable(title: title, path: url.path))
        }
        for folder in folders {
            for entry in children(of: folder) {
                if entry.pathExtension == "app" {
                    add(entry)
                } else if isFolder(entry) {
                    children(of: entry).filter { $0.pathExtension == "app" }.forEach(add)
                }
            }
        }
        return found.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// The folders' modification dates: they change when an app is added to or removed from a folder, so an
    /// unchanged stamp means a cached scan is still good (apps inside a subfolder like Utilities are not seen).
    public static func stamp(_ folders: [URL] = standardFolders) -> [Date?] {
        // FileManager, not URL.resourceValues: a URL caches its values, so a second read would miss the change.
        folders.map { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.modificationDate] as? Date }
    }

    private static func children(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles])) ?? []
    }

    private static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }
}

/// Ranks items for a query the way launchers do: every query character must appear in order; a prefix beats a
/// word start, which beats a match in the middle; runs of consecutive characters score higher.
public enum FuzzyMatch {
    /// Nil when `query` doesn't match `text`.
    public static func score(_ query: String, in text: String) -> Int? {
        let needle = Array(query.lowercased().filter { !$0.isWhitespace })
        let haystack = Array(text.lowercased())
        guard !needle.isEmpty else { return 0 }
        var score = 0
        var position = 0
        var previous = -2
        for character in needle {
            guard let found = haystack[position...].firstIndex(of: character) else { return nil }
            score += 1
            if found == 0 || !haystack[found - 1].isLetter && !haystack[found - 1].isNumber { score += 8 }
            if found == previous + 1 { score += 5 }
            previous = found
            position = found + 1
        }
        if text.lowercased().hasPrefix(String(needle)) { score += 20 }
        return score - haystack.count / 10
    }

    /// The matches, best first; ties keep their order. An empty query matches nothing (the launcher starts as a bar).
    public static func rank(_ items: [Launchable], query: String, limit: Int = 50) -> [Launchable] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return items.enumerated()
            .compactMap { offset, item in score(query, in: item.title).map { (item, $0, offset) } }
            .sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 < $1.2 }
            .prefix(limit)
            .map { $0.0 }
    }
}
