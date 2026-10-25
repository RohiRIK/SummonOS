import Foundation

/// Files and folders a change created (they did not exist before it), recorded on its Activity event as the
/// `created` ref so `summon checkpoint undo` removes them too. Restoring a checkpoint only puts back what
/// existed; without this, a theme's generated files outlived its undo.
public enum CreatedFiles {
    public static let ref = "created"

    /// Which of `candidates` exist now.
    public static func existing(_ candidates: [URL]) -> Set<String> {
        Set(candidates.map(\.path).filter { FileManager.default.fileExists(atPath: $0) })
    }

    /// The `created` ref: candidates that exist now and did not before, newline-separated; nil when none.
    public static func ref(_ candidates: [URL], before: Set<String>) -> String? {
        let created = existing(candidates).subtracting(before).sorted()
        return created.isEmpty ? nil : created.joined(separator: "\n")
    }

    /// Removes what events tied to `checkpoint` created, deepest paths first so a created folder is removed after
    /// the files in it. Only paths inside `home`; a folder is removed only when nothing else is left in it.
    /// Returns the removed paths.
    public static func removeAll(for checkpoint: String, in log: [LoggedEvent], home: URL, dryRun: Bool) -> [String] {
        let root = home.resolvingSymlinksInPath().path + "/"
        let paths = Set(log.filter { $0.refs["checkpoint"] == checkpoint }
            .flatMap { ($0.refs[ref] ?? "").split(separator: "\n").map(String.init) })
        var removed: [String] = []
        let fm = FileManager.default
        for path in paths.sorted(by: { $0.count > $1.count }) {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            guard resolved.hasPrefix(root) || path.hasPrefix(home.path + "/"), fm.fileExists(atPath: path) else { continue }
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: path, isDirectory: &isDirectory)
            // A created folder goes only when everything left in it is recorded too (removed before it, or
            // about to be in a dry run): anything the user added since keeps it.
            if isDirectory.boolValue {
                let inside = (try? fm.contentsOfDirectory(atPath: path)) ?? []
                guard inside.allSatisfy({ removed.contains(path + "/" + $0) }) else { continue }
            }
            if !dryRun { try? fm.removeItem(atPath: path) }
            removed.append(path)
        }
        return removed
    }
}
