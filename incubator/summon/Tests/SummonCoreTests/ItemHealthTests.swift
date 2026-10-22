import Foundation
import Testing
@testable import SummonCore

@Suite("Item Health Checks (Apps and Themes)")
struct ItemHealthTests {
    let fm = FileManager.default

    @Test func healthyProjectPasses() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/my-widget")
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: projectFolder.appendingPathComponent("Package.swift"))
        try fm.createDirectory(at: projectFolder.appendingPathComponent("build/my-widget.app"), withIntermediateDirectories: true)

        let project = Project(name: "my-widget", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(health.isHealthy)
        #expect(health.badge == "Healthy")
        #expect(health.level == .healthy)
    }

    @Test func missingFolderReportsError() throws {
        let project = Project(name: "ghost-app", kind: .menubar, path: "/non/existent/path/ghost-app", created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(!health.isHealthy)
        #expect(health.level == .error)
        #expect(health.badge == "Folder Missing")
        #expect(health.fixPrompt?.contains("ghost-app") == true)
    }

    @Test func missingPackageSwiftReportsError() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/broken-pkg")
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)

        let project = Project(name: "broken-pkg", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(!health.isHealthy)
        #expect(health.level == .error)
        #expect(health.badge == "Missing Package.swift")
    }

    @Test func unbuiltProjectReportsWarning() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/unbuilt-app")
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: projectFolder.appendingPathComponent("Package.swift"))

        let project = Project(name: "unbuilt-app", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(!health.isHealthy)
        #expect(health.level == .warning)
        #expect(health.badge == "Needs Build")
    }

    @Test func crashedAppReportsError() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/crashy")
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: projectFolder.appendingPathComponent("Package.swift"))
        try fm.createDirectory(at: projectFolder.appendingPathComponent(".build"), withIntermediateDirectories: true)

        let crashText = """
        {"app_name":"crashy","bug_type":"309","timestamp":"2026-10-17 11:00:00.00 +0000"}
        Exception Type: EXC_BAD_ACCESS
        Termination Signal: Segmentation fault: 11
        """
        let crash = try CrashReport.parse(crashText, file: "/fake/crashy.ips")

        let project = Project(name: "crashy", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project, recentCrashes: [crash])

        #expect(!health.isHealthy)
        #expect(health.level == .error)
        #expect(health.badge == "Crashed")
        #expect(health.fixPrompt?.contains("diagnose-crash-mac") == true)
    }

    @Test func themeWithoutWallpaperReportsWarning() throws {
        let temp = try makeTempHome()
        let themesDir = temp.appendingPathComponent(".config/summon/themes")
        let themeDir = themesDir.appendingPathComponent("no-wall")
        try fm.createDirectory(at: themeDir, withIntermediateDirectories: true)

        let theme = Theme(
            name: "No Wall",
            slug: "no-wall",
            appearance: "dark",
            colors: Theme.Colors(
                background: "#101010",
                foreground: "#e0e0e0",
                accent: "#6080ff",
                accent2: "#ff6080",
                muted: "#808080",
                selection: "#303040",
                cursor: "#e0e0e0",
                borderActive: "#6080ff",
                borderInactive: "#404040"
            ),
            terminal: (0..<16).map { _ in "#202020" },
            font: "JetBrainsMono Nerd Font",
            wallpapers: []
        )

        let data = try JSONEncoder().encode(theme)
        try data.write(to: themeDir.appendingPathComponent("theme.json"))

        let health = AppHealthChecker.check(theme: theme, themesFolder: themesDir)
        #expect(!health.isHealthy)
        #expect(health.level == .warning)
        #expect(health.badge == "No Wallpaper")
        #expect(health.fixPrompt?.contains("summon-art") == true)
    }

    @Test func themeWithMissingImageReportsError() throws {
        let temp = try makeTempHome()
        let themesDir = temp.appendingPathComponent(".config/summon/themes")
        let themeDir = themesDir.appendingPathComponent("lost-img")
        try fm.createDirectory(at: themeDir, withIntermediateDirectories: true)

        let theme = Theme(
            name: "Lost Image",
            slug: "lost-img",
            appearance: "dark",
            colors: Theme.Colors(
                background: "#101010",
                foreground: "#e0e0e0",
                accent: "#6080ff",
                accent2: "#ff6080",
                muted: "#808080",
                selection: "#303040",
                cursor: "#e0e0e0",
                borderActive: "#6080ff",
                borderInactive: "#404040"
            ),
            terminal: (0..<16).map { _ in "#202020" },
            font: "JetBrainsMono Nerd Font",
            wallpapers: ["deleted-wallpaper.jpg"]
        )

        let data = try JSONEncoder().encode(theme)
        try data.write(to: themeDir.appendingPathComponent("theme.json"))

        let health = AppHealthChecker.check(theme: theme, themesFolder: themesDir)
        #expect(!health.isHealthy)
        #expect(health.level == .error)
        #expect(health.badge == "Missing Image")
        #expect(health.detail.contains("deleted-wallpaper.jpg"))
    }
}
