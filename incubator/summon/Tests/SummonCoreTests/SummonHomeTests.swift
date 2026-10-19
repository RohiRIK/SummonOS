import Foundation
import Testing
@testable import SummonCore

@Suite("~/Summon: one home for everything Summon and its agents make")
struct SummonHomeTests {
    let fm = FileManager.default

    @Test func layoutIsMadeOnceAndKeptOutOfGit() throws {
        let paths = SummonPaths(home: try makeTempHome())
        try SummonHome.ensure(paths)
        try SummonHome.ensure(paths)
        for folder in [paths.apps, paths.art, paths.taskLogs] {
            var isDirectory: ObjCBool = false
            #expect(fm.fileExists(atPath: folder.path, isDirectory: &isDirectory) && isDirectory.boolValue)
        }
        #expect(paths.apps.path.hasSuffix("/Summon/Apps"))
        #expect(try fm.destinationOfSymbolicLink(atPath: paths.summonHome.appendingPathComponent("Themes").path) == paths.themes.path)
        let ignore = try String(contentsOf: paths.summonHome.appendingPathComponent(".gitignore"), encoding: .utf8)
        for line in ["Art/", "Tasks/", "Themes", ".DS_Store", ".build/"] { #expect(ignore.contains(line)) }
    }

    @Test func scatteredWorkMovesIn() throws {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        try writeFile("jpg", to: home.appendingPathComponent("Downloads/summon-art/hearts-valley-wallpaper/1-place.jpg"))
        try writeFile("jpg", to: home.appendingPathComponent("Downloads/summon-wallpapers/catppuccin/1-place.jpg"))
        try writeFile("log", to: paths.state.appendingPathComponent("tasks/brew/2026.log"))
        let old = paths.summonHome.appendingPathComponent("mac-battery", isDirectory: true)
        try writeFile("// swift", to: old.appendingPathComponent("Package.swift"))
        try ProjectStore(paths: paths).save(ProjectRegistry(projects: [
            Project(name: "mac-battery", kind: .menubar, path: old.path, created: Date(timeIntervalSince1970: 1_800_000_000)),
        ]))

        let moved = try SummonHome.migrate(paths)
        #expect(moved.count == 4)
        #expect(fm.fileExists(atPath: paths.art.appendingPathComponent("hearts-valley-wallpaper/1-place.jpg").path))
        #expect(fm.fileExists(atPath: paths.art.appendingPathComponent("wallpaper-catppuccin/1-place.jpg").path))
        #expect(fm.fileExists(atPath: paths.taskLogs.appendingPathComponent("brew/2026.log").path))
        #expect(fm.fileExists(atPath: paths.apps.appendingPathComponent("mac-battery/Package.swift").path))
        #expect(try ProjectStore(paths: paths).load().projects.first?.path == paths.apps.appendingPathComponent("mac-battery").path)
        #expect(!fm.fileExists(atPath: home.appendingPathComponent("Downloads/summon-art").path))
        #expect(try SummonHome.migrate(paths).isEmpty)
    }
}
