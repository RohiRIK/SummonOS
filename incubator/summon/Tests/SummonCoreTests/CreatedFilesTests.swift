import Foundation
import Testing
@testable import SummonCore

@Suite("Undo removes the files a change created")
struct CreatedFilesTests {
    let fm = FileManager.default

    @Test func refListsOnlyWhatIsNew() throws {
        let home = try makeTempHome()
        let old = home.appendingPathComponent("old.txt"), new = home.appendingPathComponent("new/colors.lua")
        try writeFile("x", to: old)
        let before = CreatedFiles.existing([old, new, new.deletingLastPathComponent()])
        try writeFile("y", to: new)
        let ref = try #require(CreatedFiles.ref([old, new, new.deletingLastPathComponent()], before: before))
        #expect(ref.split(separator: "\n").map(String.init) == [home.appendingPathComponent("new").path, new.path])
        #expect(CreatedFiles.ref([old], before: CreatedFiles.existing([old])) == nil)
    }

    @Test func removesCreatedFilesAndFoldersButKeepsTheUsersAdditions() throws {
        let home = try makeTempHome()
        let dir = home.appendingPathComponent(".config/nvim"), file = dir.appendingPathComponent("colors/summon.lua")
        let kept = home.appendingPathComponent(".claude/themes"), keptFile = kept.appendingPathComponent("summon.json")
        try writeFile("lua", to: file)
        try writeFile("{}", to: keptFile)
        try writeFile("mine", to: kept.appendingPathComponent("mine.json"))
        let created = [dir.path, dir.appendingPathComponent("colors").path, file.path, kept.path, keptFile.path, "/etc/hosts"]
        let log = [LoggedEvent(kind: EventKind.themeSet, title: "Theme", refs: ["checkpoint": "c1", CreatedFiles.ref: created.joined(separator: "\n")]),
                   LoggedEvent(kind: EventKind.themeSet, title: "Other", refs: ["checkpoint": "c2", CreatedFiles.ref: home.appendingPathComponent("x").path])]

        let preview = CreatedFiles.removeAll(for: "c1", in: log, home: home, dryRun: true)
        #expect(fm.fileExists(atPath: file.path))
        #expect(!preview.contains("/etc/hosts"))

        let removed = CreatedFiles.removeAll(for: "c1", in: log, home: home, dryRun: false)
        #expect(!fm.fileExists(atPath: dir.path))
        #expect(!fm.fileExists(atPath: keptFile.path))
        // The user's own file kept its folder alive.
        #expect(fm.fileExists(atPath: kept.appendingPathComponent("mine.json").path))
        #expect(!removed.contains(kept.path))
        #expect(fm.fileExists(atPath: "/etc/hosts"))
    }
}
