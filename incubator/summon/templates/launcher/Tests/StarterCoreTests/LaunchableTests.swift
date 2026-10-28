import Foundation
import StarterCore
import Testing

@Suite struct FuzzyMatchTests {
    let items = ["Safari", "System Settings", "Notes", "Font Book", "Messages"].map { Launchable(title: $0, path: "/Applications/\($0).app") }

    @Test func prefixBeatsWordStartBeatsMiddle() {
        #expect(FuzzyMatch.rank(items, query: "s").first?.title == "Safari")
        #expect(FuzzyMatch.rank(items, query: "set").first?.title == "System Settings")
        #expect(FuzzyMatch.rank(items, query: "bo").first?.title == "Font Book")
    }

    @Test func everyCharacterMustAppearInOrder() {
        #expect(FuzzyMatch.score("sfr", in: "Safari") != nil)
        #expect(FuzzyMatch.score("rfs", in: "Safari") == nil)
        #expect(FuzzyMatch.rank(items, query: "zzz").isEmpty)
    }

    @Test func emptyQueryShowsNothing() {
        #expect(FuzzyMatch.rank(items, query: "").isEmpty)
        #expect(FuzzyMatch.rank(items, query: "   ").isEmpty)
    }

    @Test func caseDoesNotMatter() {
        #expect(FuzzyMatch.rank(items, query: "NOTES").first?.title == "Notes")
    }
}

@Suite struct AppCatalogTests {
    @Test func findsAppsOneLevelDeepWithoutDuplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("one")
        let second = root.appendingPathComponent("two")
        for path in ["Zed.app", "Alpha.app", "Utilities/Terminal.app", "notes.txt", "Utilities/Deep/Hidden.app"] {
            try FileManager.default.createDirectory(at: first.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(at: second.appendingPathComponent("Alpha.app"), withIntermediateDirectories: true)

        let titles = AppCatalog.scan([first, second]).map(\.title)
        #expect(titles == ["Alpha", "Terminal", "Zed"])
    }

    @Test func stampChangesWhenAnAppIsAdded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let before = AppCatalog.stamp([root])
        #expect(before == AppCatalog.stamp([root]))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("New.app"), withIntermediateDirectories: true)
        #expect(before != AppCatalog.stamp([root]))
    }

    @Test func missingFolderIsEmpty() {
        #expect(AppCatalog.scan([URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")]).isEmpty)
    }
}
