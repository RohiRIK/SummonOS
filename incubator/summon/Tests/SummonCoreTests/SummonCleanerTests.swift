import Foundation
import Testing
@testable import SummonCore

@Suite("Keeping ~/Summon tidy")
struct SummonCleanerTests {
    let fm = FileManager.default
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func file(_ url: URL, daysOld: Double) throws {
        try writeFile("x", to: url)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-daysOld * 86_400)], ofItemAtPath: url.path)
    }

    func task(_ id: String) -> RecurringTask {
        RecurringTask(id: id, name: id, prompt: "p", agent: nil, schedule: TaskSchedule(kind: .daily))
    }

    func log(_ folder: URL, hoursOld: Double) throws -> URL {
        let url = folder.appendingPathComponent(UUID().uuidString + ".log")
        try writeFile("x", to: url)
        try fm.setAttributes([.modificationDate: now.addingTimeInterval(-hoursOld * 3600)], ofItemAtPath: url.path)
        return url
    }

    /// Run logs are named by UUID, whose order says nothing about when they ran: retention follows file times.
    @Test func taskLogsKeepTheActualNewestTwentyAndNothingOverThirtyDays() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let logs = paths.taskLogs.appendingPathComponent("brew")
        let byAge = try (0..<25).map { try log(logs, hoursOld: Double($0)) }
        let expired = try log(logs, hoursOld: 40 * 24)
        try file(logs.appendingPathComponent("launchd.log"), daysOld: 40)
        let plan = SummonCleaner.plan(paths, tasks: [task("brew")], now: now)
        let trashed = Set(plan.trash.map(\.path))
        #expect(trashed == Set((byAge.suffix(5) + [expired]).map(\.path)))
        #expect(plan.trash.allSatisfy { $0.task == "brew" })
    }

    @Test func equalTimesBreakTiesByNameDeterministically() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let logs = paths.taskLogs.appendingPathComponent("brew")
        for _ in 0..<19 { _ = try log(logs, hoursOld: 1) }
        let tied = try [log(logs, hoursOld: 2), log(logs, hoursOld: 2)]
        let plan = SummonCleaner.plan(paths, tasks: [task("brew")], now: now)
        let loser = tied.map(\.lastPathComponent).min()
        #expect(plan.trash.map(\.path) == tied.filter { $0.lastPathComponent == loser }.map(\.path))
        #expect(SummonCleaner.plan(paths, tasks: [task("brew")], now: now) == plan)
    }

    @Test func aLogAnInterruptedRunStillNeedsIsNeverPlanned() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let logs = paths.taskLogs.appendingPathComponent("brew")
        for hours in 0..<20 { _ = try log(logs, hoursOld: Double(hours)) }
        let interrupted = try log(logs, hoursOld: 50 * 24)
        let run = interrupted.deletingPathExtension().lastPathComponent
        try TaskRunJournal(paths: paths, task: "brew").begin(TaskRunMarker(run: run, task: "brew", name: "brew", file: interrupted.path))
        #expect(SummonCleaner.plan(paths, tasks: [task("brew")], now: now).trash.isEmpty)
    }

    @Test func removedTaskPendingRunRetainsFolderAndLogThroughRevalidation() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let folder = paths.taskLogs.appendingPathComponent("gone")
        let pendingLog = try log(folder, hoursOld: 9 * 24)
        let plan = SummonCleaner.plan(paths, tasks: [], now: now)
        #expect(plan.trash.map(\.path) == [folder.path])
        let run = pendingLog.deletingPathExtension().lastPathComponent
        try TaskRunJournal(paths: paths, task: "gone").begin(TaskRunMarker(run: run, task: "gone", name: "Gone", file: pendingLog.path))
        var moved: [String] = []
        let applied = SummonCleaner.apply(plan, paths: paths, now: now) { moved.append($0.path) }
        #expect(moved.isEmpty)
        #expect(applied.skipped.map(\.path) == [folder.path])
        #expect(fm.fileExists(atPath: pendingLog.path))
        #expect(SummonCleaner.plan(paths, tasks: [], now: now).trash.isEmpty)
    }

    @Test func applySkipsATaskWhoseRunHoldsItsLease() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try TaskStore(paths: paths).save([task("brew")])
        let logs = paths.taskLogs.appendingPathComponent("brew")
        for hours in 0..<22 { _ = try log(logs, hoursOld: Double(hours)) }
        try file(paths.taskLogs.appendingPathComponent("gone/old.log"), daysOld: 8)
        let plan = SummonCleaner.plan(paths, tasks: [task("brew")], now: now)
        #expect(plan.trash.count == 3)
        var running: FileLease? = try FileLease.acquireSync(TaskRunLease.file(paths, task: "brew"), timeout: 0)
        var manual: FileLease? = try FileLease.acquireSync(TaskRunLease.file(paths, task: "gone"), timeout: 0)
        var trashed: [String] = []
        let applied = withExtendedLifetime((running, manual)) {
            SummonCleaner.apply(plan, paths: paths, now: now) { trashed.append($0.path) }
        }
        #expect(trashed.isEmpty)
        #expect(applied.moved.isEmpty)
        #expect(applied.failures.isEmpty)
        #expect(Set(applied.skipped.map(\.path)) == Set(plan.trash.map(\.path)))
        #expect(applied.skipped.allSatisfy { $0.reason.contains("running") })
        running = nil
        manual = nil
        // Once the runs finish, the same plan applies.
        let later = SummonCleaner.apply(plan, paths: paths, now: now) { trashed.append($0.path) }
        #expect(later.moved.count == 3)
    }

    @Test func eligibleBusyTaskKeepsAutomaticCleaningDue() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try TaskStore(paths: paths).save([task("brew")])
        let folder = paths.taskLogs.appendingPathComponent("brew")
        for hours in 0..<21 { _ = try log(folder, hoursOld: Double(hours)) }
        let plan = SummonCleaner.plan(paths, tasks: [task("brew")], now: now)
        let lease = try FileLease.acquireSync(TaskRunLease.file(paths, task: "brew"), timeout: 0)
        let applied = withExtendedLifetime(lease) { SummonCleaner.apply(plan, paths: paths, now: now) { _ in } }
        #expect(applied.skipped.count == 1)
        #expect(applied.failures.isEmpty)
        #expect(SummonCleaner.isDue(paths, now: now.addingTimeInterval(3600)))
    }

    @Test func applyRevalidatesUnderTheLease() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try TaskStore(paths: paths).save([task("brew")])
        let logs = paths.taskLogs.appendingPathComponent("brew")
        let byAge = try (0..<21).map { try log(logs, hoursOld: Double($0)) }
        let plan = SummonCleaner.plan(paths, tasks: [task("brew")], now: now)
        #expect(plan.trash.map(\.path) == [byAge[20].path])
        // A run wrote to that log after planning: it is now the newest and must stay.
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: byAge[20].path)
        var trashed: [String] = []
        let applied = SummonCleaner.apply(plan, paths: paths, now: now) { trashed.append($0.path) }
        #expect(trashed.isEmpty)
        #expect(applied.skipped.map(\.path) == [byAge[20].path])
        #expect(fm.fileExists(atPath: byAge[20].path))
        #expect(!SummonCleaner.isDue(paths, now: now.addingTimeInterval(3600)))
    }

    @Test func failedMovesAreReportedAndLeaveCleaningDue() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try file(paths.art.appendingPathComponent("old/1.jpg"), daysOld: 40)
        let plan = SummonCleaner.plan(paths, tasks: [], now: now)
        let applied = SummonCleaner.apply(plan, paths: paths, now: now) { _ in throw CocoaError(.fileWriteNoPermission) }
        #expect(applied.moved.isEmpty)
        #expect(applied.failures.map(\.path) == [paths.art.appendingPathComponent("old").path])
        #expect(SummonCleaner.isDue(paths, now: now.addingTimeInterval(3600)))
    }

    @Test func removedTasksArtAndOriginalsAge() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try file(paths.taskLogs.appendingPathComponent("gone/2026.log"), daysOld: 8)
        try file(paths.taskLogs.appendingPathComponent("recent-gone/2026.log"), daysOld: 2)
        try file(paths.art.appendingPathComponent("old-wallpaper/1-place.jpg"), daysOld: 31)
        try file(paths.art.appendingPathComponent("new-wallpaper/1-place.jpg"), daysOld: 3)
        try file(paths.art.appendingPathComponent("antigravity-originals/abc/a.jpg"), daysOld: 15)
        try file(paths.art.appendingPathComponent("antigravity-originals/def/b.jpg"), daysOld: 5)
        try file(paths.apps.appendingPathComponent("stray/Package.swift"), daysOld: 400)
        let plan = SummonCleaner.plan(paths, tasks: [], now: now)
        let trashed = Set(plan.trash.map { URL(fileURLWithPath: $0.path).lastPathComponent })
        #expect(trashed == ["gone", "old-wallpaper", "abc"])
        #expect(plan.notes.contains { $0.contains("Apps/stray") })
    }

    @Test func brokenAndUnfinishedThemesAreReported() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try writeFile(#"{"name":"Hearts Valley","colors":{"accent":"oklch(0.15 0.12 240)"}} // agent wrote this"#,
                      to: paths.themes.appendingPathComponent("hearts-valley/theme.json"))
        try writeFile(sampleThemeJSON, to: paths.themes.appendingPathComponent("summon-night/theme.json"))
        let notes = SummonCleaner.plan(paths, tasks: [], now: now).notes
        #expect(notes.contains { $0.contains("hearts-valley") && $0.contains("not valid") })
        #expect(notes.contains { $0.contains("summon-night") && $0.contains("no wallpaper") })
    }

    @Test func applyMovesToTheTrashAndRecordsTheRun() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try file(paths.art.appendingPathComponent("old/1.jpg"), daysOld: 40)
        #expect(SummonCleaner.isDue(paths, now: now))
        let plan = SummonCleaner.plan(paths, tasks: [], now: now)
        var trashed: [String] = []
        let applied = SummonCleaner.apply(plan, paths: paths, now: now) { url in trashed.append(url.path) }
        #expect(applied.moved.count == 1)
        #expect(trashed == [paths.art.appendingPathComponent("old").path])
        #expect(!SummonCleaner.isDue(paths, now: now.addingTimeInterval(3600)))
        #expect(SummonCleaner.isDue(paths, now: now.addingTimeInterval(25 * 3600)))
    }
}
