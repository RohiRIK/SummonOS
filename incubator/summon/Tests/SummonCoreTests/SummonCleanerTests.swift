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

    @Test func taskLogsKeepTheNewestTwentyAndNothingOverThirtyDays() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let logs = paths.taskLogs.appendingPathComponent("brew")
        for index in 0..<25 { try file(logs.appendingPathComponent(String(format: "2027-01-%02dT00.log", index + 1)), daysOld: 1) }
        try file(logs.appendingPathComponent("2026-11-01T00.log"), daysOld: 40)
        try file(logs.appendingPathComponent("launchd.log"), daysOld: 40)
        let plan = SummonCleaner.plan(paths, tasks: [task("brew")], now: now)
        let names = plan.trash.map { URL(fileURLWithPath: $0.path).lastPathComponent }.sorted()
        #expect(names.count == 6)
        #expect(names.contains("2026-11-01T00.log"))
        #expect(names.contains("2027-01-01T00.log"))
        #expect(!names.contains("launchd.log"))
        #expect(!names.contains("2027-01-25T00.log"))
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
        let count = SummonCleaner.apply(plan, paths: paths, now: now) { url in trashed.append(url.path) }
        #expect(count == 1)
        #expect(trashed == [paths.art.appendingPathComponent("old").path])
        #expect(!SummonCleaner.isDue(paths, now: now.addingTimeInterval(3600)))
        #expect(SummonCleaner.isDue(paths, now: now.addingTimeInterval(25 * 3600)))
    }
}
