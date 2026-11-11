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
        /// The task whose run lease guards this item: its logs, or its folder after it was removed.
        public var task: String?

        public init(path: String, reason: String, task: String? = nil) {
            self.path = path
            self.reason = reason
            self.task = task
        }
    }

    public struct Plan: Sendable, Equatable, Codable {
        public var trash: [Item] = []
        /// Things to look at, never removed.
        public var notes: [String] = []
    }

    /// What `apply` did. Skipped and failed items stay where they were.
    public struct Applied: Sendable, Equatable {
        public struct Failure: Sendable, Equatable {
            public var path: String
            public var message: String
        }

        public var moved: [Item] = []
        /// Left in place on purpose: the task was running, or the item no longer qualifies.
        public var skipped: [Item] = []
        public var failures: [Failure] = []
    }

    public static func plan(_ paths: SummonPaths, tasks: [RecurringTask], now: Date = Date()) -> Plan {
        var plan = Plan()
        let fm = FileManager.default
        func age(_ url: URL) -> Double { now.timeIntervalSince(newest(url)) / 86_400 }

        // Tasks: logs per task; folders of tasks that no longer exist.
        let known = Set(tasks.map(\.id))
        for folder in children(paths.taskLogs) where isDirectory(folder) {
            do { plan.trash += try taskItems(folder, known: known, paths: paths, now: now) }
            catch { plan.notes.append("Tasks/\(folder.lastPathComponent) was left as is: \(error)") }
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

    /// One task folder's items. Logs rank by modification time (newest first, the name breaking ties), never by
    /// name: run logs are named by UUID. A log an interrupted run's recovery still needs is kept.
    static func taskItems(_ folder: URL, known: Set<String>, paths: SummonPaths, now: Date) throws -> [Item] {
        let task = folder.lastPathComponent
        let pending = try TaskRunJournal(paths: paths, task: task).pending()
        guard known.contains(task) else {
            let age = now.timeIntervalSince(newest(folder)) / 86_400
            return age > removedTaskDays && pending.isEmpty
                ? [Item(path: folder.path, reason: "its task was removed", task: task)] : []
        }
        let recovering = Set(pending.compactMap { marker in
            marker.file.map { URL(fileURLWithPath: $0).lastPathComponent }
        })
        let logs = children(folder)
            .filter { $0.pathExtension == "log" && $0.lastPathComponent != "launchd.log" && !isDirectory($0) }
            .map { (url: $0, modified: modified($0)) }
            .sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.url.lastPathComponent > $1.url.lastPathComponent }
        var items: [Item] = []
        for (index, log) in logs.enumerated() where !recovering.contains(log.url.lastPathComponent) {
            if index >= keepLogs {
                items.append(Item(path: log.url.path, reason: "older than the newest \(keepLogs) runs", task: task))
            } else if now.timeIntervalSince(log.modified) / 86_400 > logDays {
                items.append(Item(path: log.url.path, reason: "older than \(Int(logDays)) days", task: task))
            }
        }
        return items
    }

    /// Moves planned items to the Trash (`trash` is injectable for tests) and stamps the run when nothing failed.
    /// Task items move only under their task's run lease, taken without waiting: a running task is skipped, and
    /// the plan is checked again under the lease, because a run may have started or finished since it was made.
    @discardableResult
    public static func apply(_ plan: Plan, paths: SummonPaths, now: Date = Date(),
                             trash: (URL) throws -> Void = { try FileManager.default.trashItem(at: $0, resultingItemURL: nil) }) -> Applied {
        var applied = Applied()
        func move(_ item: Item) {
            do {
                try trash(URL(fileURLWithPath: item.path))
                applied.moved.append(item)
            } catch {
                applied.failures.append(Applied.Failure(path: item.path, message: String(describing: error)))
            }
        }
        for item in plan.trash where item.task == nil { move(item) }
        let byTask = Dictionary(grouping: plan.trash.filter { $0.task != nil }, by: { $0.task ?? "" })
        var eligibleBusy = false
        for task in byTask.keys.sorted() {
            let items = byTask[task] ?? []
            func skip(_ reason: String) { applied.skipped += items.map { Item(path: $0.path, reason: reason, task: task) } }
            func fail(_ error: any Error) { applied.failures += items.map { Applied.Failure(path: $0.path, message: String(describing: error)) } }
            guard TaskStore.isSafeID(task) else { skip("not a task folder Summon made"); continue }
            let lease: FileLease
            do { lease = try FileLease.acquireSync(TaskRunLease.file(paths, task: task), timeout: 0) }
            catch FileLeaseError.busy { eligibleBusy = true; skip("its task is running"); continue }
            catch { fail(error); continue }
            withExtendedLifetime(lease) {
                do {
                    let known = Set(try TaskStore(paths: paths).loadValidated().map(\.id))
                    let folder = paths.taskLogs.appendingPathComponent(task, isDirectory: true)
                    let current = Set(try taskItems(folder, known: known, paths: paths, now: now).map(\.path))
                    for item in items {
                        if current.contains(item.path) { move(item) }
                        else { applied.skipped.append(Item(path: item.path, reason: "no longer qualifies", task: task)) }
                    }
                } catch {
                    fail(error)
                }
            }
        }
        if applied.failures.isEmpty && !eligibleBusy {
            do { try TextFile.write(ISO8601DateFormatter().string(from: now) + "\n", to: stampFile(paths)) }
            catch { applied.failures.append(Applied.Failure(path: stampFile(paths).path, message: String(describing: error))) }
        }
        return applied
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

    static func modified(_ url: URL) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date) ?? .distantPast
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
