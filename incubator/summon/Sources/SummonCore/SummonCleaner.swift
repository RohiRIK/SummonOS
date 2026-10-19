import Foundation

/// Keeps `~/Summon` tidy. Everything removed goes to the macOS Trash, so it can be put back. Apps are never touched,
/// and unfinished work (a theme without its wallpaper, an app Summon does not know) is reported, never removed.
///
/// Rules (owner, 2026-10-19): task logs keep the newest 20 and none older than 30 days; a removed task's folder goes
/// after 7 days; an art job untouched for 30 days goes; Antigravity originals after 14 days.
public enum SummonCleaner {
    public static let keepLogs = 20
    public static let logDays = 30.0
    public static let removedTaskDays = 7.0
    public static let artDays = 30.0
    public static let originalsDays = 14.0
    /// The automatic run happens at most once a day.
    public static let interval: TimeInterval = 24 * 3600

    public struct Item: Sendable, Equatable, Codable {
        public var path: String
        public var reason: String
    }

    public struct Plan: Sendable, Equatable, Codable {
        public var trash: [Item] = []
        /// Things to look at, never removed.
        public var notes: [String] = []
    }

    public static func plan(_ paths: SummonPaths, tasks: [RecurringTask], now: Date = Date()) -> Plan {
        var plan = Plan()
        let fm = FileManager.default
        func age(_ url: URL) -> Double { now.timeIntervalSince(newest(url)) / 86_400 }

        // Tasks: logs per task; folders of tasks that no longer exist.
        let known = Set(tasks.map(\.id))
        for folder in children(paths.taskLogs) where isDirectory(folder) {
            guard known.contains(folder.lastPathComponent) else {
                if age(folder) > removedTaskDays { plan.trash.append(Item(path: folder.path, reason: "its task was removed")) }
                continue
            }
            let logs = children(folder).filter { $0.pathExtension == "log" && $0.lastPathComponent != "launchd.log" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for (index, log) in logs.enumerated() {
                if index >= keepLogs {
                    plan.trash.append(Item(path: log.path, reason: "older than the newest \(keepLogs) runs"))
                } else if age(log) > logDays {
                    plan.trash.append(Item(path: log.path, reason: "older than \(Int(logDays)) days"))
                }
            }
        }

        // Art: whole jobs; Antigravity's originals per session.
        for job in children(paths.art) where isDirectory(job) {
            if job.lastPathComponent == "antigravity-originals" {
                for session in children(job) where isDirectory(session) && age(session) > originalsDays {
                    plan.trash.append(Item(path: session.path, reason: "Antigravity originals older than \(Int(originalsDays)) days"))
                }
            } else if age(job) > artDays {
                plan.trash.append(Item(path: job.path, reason: "untouched for \(Int(artDays)) days"))
            }
        }

        // Reported only.
        let registered = Set(((try? ProjectStore(paths: paths).load())?.projects ?? []).map { URL(fileURLWithPath: $0.path).lastPathComponent })
        for app in children(paths.apps) where isDirectory(app) && !registered.contains(app.lastPathComponent) {
            plan.notes.append("Apps/\(app.lastPathComponent) is not in Summon's project list (left as is)")
        }
        for theme in children(paths.themes) where isDirectory(theme) {
            guard let data = try? Data(contentsOf: theme.appendingPathComponent("theme.json")) else { continue }
            guard (try? Theme.decode(data)) != nil,
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                plan.notes.append("Theme \(theme.lastPathComponent) cannot be used: theme.json is not valid (summon theme check \(theme.lastPathComponent))")
                continue
            }
            let wallpapers = object["wallpapers"] as? [String] ?? []
            let missing = wallpapers.isEmpty || !wallpapers.contains { fm.fileExists(atPath: theme.appendingPathComponent($0).path) }
            if missing {
                plan.notes.append("Theme \(theme.lastPathComponent) has no wallpaper installed (candidates may be in ~/Summon/Art)")
            }
        }
        return plan
    }

    /// Moves every planned item to the Trash (`trash` is injectable for tests) and records the run.
    @discardableResult
    public static func apply(_ plan: Plan, paths: SummonPaths, now: Date = Date(),
                             trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Int {
        var count = 0
        for item in plan.trash {
            do {
                try trash(URL(fileURLWithPath: item.path))
                count += 1
            } catch {
                continue
            }
        }
        try? TextFile.write(ISO8601DateFormatter().string(from: now) + "\n", to: stampFile(paths))
        return count
    }

    public static func isDue(_ paths: SummonPaths, now: Date = Date()) -> Bool {
        guard let text = TextFile.firstLine(stampFile(paths)), let last = ISO8601DateFormatter().date(from: text) else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    static func stampFile(_ paths: SummonPaths) -> URL {
        paths.state.appendingPathComponent("clean-last")
    }

    static func children(_ url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
            .filter { $0 != ".DS_Store" }
            .map { url.appendingPathComponent($0) }
    }

    static func isDirectory(_ url: URL) -> Bool {
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    /// The newest modification time of a file, or of anything inside a folder.
    static func newest(_ url: URL) -> Date {
        let fm = FileManager.default
        var latest = (try? fm.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
        if isDirectory(url), let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.contentModificationDateKey]) {
            for case let child as URL in walker {
                let date = (try? child.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                if date > latest { latest = date }
            }
        }
        return latest
    }
}
