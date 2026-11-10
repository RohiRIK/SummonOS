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
        let resFolder = projectFolder.appendingPathComponent("Resources")
        try fm.createDirectory(at: resFolder, withIntermediateDirectories: true)
        try writeFile("fake icns", to: resFolder.appendingPathComponent("AppIcon.icns"))
        let shotsFolder = projectFolder.appendingPathComponent("docs/screenshots")
        try fm.createDirectory(at: shotsFolder, withIntermediateDirectories: true)
        try writeFile("fake png", to: shotsFolder.appendingPathComponent("panel-dark.png"))

        let project = Project(name: "my-widget", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(health.isHealthy)
        #expect(health.level == .healthy)
    }

    @Test func optionalProjectArtworkIsAdvisory() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/no-art")
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: projectFolder.appendingPathComponent("Package.swift"))
        try fm.createDirectory(at: projectFolder.appendingPathComponent("build/no-art.app"), withIntermediateDirectories: true)

        let project = Project(name: "no-art", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(!health.isHealthy)
        #expect(health.level == .advisory)
        #expect(!health.needsRepair)
        #expect(health.fixPrompt == nil)
    }

    @Test func builtToolNeedsNoIconOrScreenshots() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/my-tool")
        try fm.createDirectory(at: projectFolder.appendingPathComponent(".build/release"), withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: projectFolder.appendingPathComponent("Package.swift"))

        let executable = projectFolder.appendingPathComponent(".build/release/my-tool")
        try writeFile("#!/bin/sh\nexit 0\n", to: executable)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let project = Project(name: "my-tool", kind: .cli, path: projectFolder.path, created: Date())
        #expect(AppHealthChecker.check(project: project, buildCache: temp.appendingPathComponent("cache")).isHealthy)
    }

    @Test func optionalProjectScreenshotsAreAdvisory() throws {
        let temp = try makeTempHome()
        let projectFolder = temp.appendingPathComponent("Apps/has-icon-only")
        try fm.createDirectory(at: projectFolder, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: projectFolder.appendingPathComponent("Package.swift"))
        try fm.createDirectory(at: projectFolder.appendingPathComponent("build/has-icon-only.app"), withIntermediateDirectories: true)
        let resFolder = projectFolder.appendingPathComponent("Resources")
        try fm.createDirectory(at: resFolder, withIntermediateDirectories: true)
        try writeFile("fake icns", to: resFolder.appendingPathComponent("AppIcon.icns"))

        let project = Project(name: "has-icon-only", kind: .menubar, path: projectFolder.path, created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(!health.isHealthy)
        #expect(health.level == .advisory)
        #expect(!health.needsRepair)
        #expect(health.fixPrompt == nil)
    }

    @Test func missingFolderReportsError() throws {
        let project = Project(name: "ghost-app", kind: .menubar, path: "/non/existent/path/ghost-app", created: Date())
        let health = AppHealthChecker.check(project: project)

        #expect(!health.isHealthy)
        #expect(health.level == .error)
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
        #expect(health.needsRepair)
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
        #expect(health.fixPrompt?.contains("diagnose-crash-mac") == true)
    }

    @Test func themeWithoutOptionalWallpaperDoesNotNeedRepair() throws {
        let temp = try makeTempHome()
        let themesDir = temp.appendingPathComponent(".config/summon/themes")
        let themeDir = themesDir.appendingPathComponent("no-wall")
        try fm.createDirectory(at: themeDir, withIntermediateDirectories: true)

        var theme = try Theme.decode(Data(sampleThemeJSON.utf8))
        theme.slug = "no-wall"
        theme.wallpapers = []

        let data = try JSONEncoder().encode(theme)
        try data.write(to: themeDir.appendingPathComponent("theme.json"))

        let health = AppHealthChecker.check(theme: theme, themesFolder: themesDir)
        #expect(!health.isHealthy)
        #expect(health.level == .advisory)
        #expect(!health.needsRepair)
        #expect(health.fixPrompt == nil)
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
        #expect(health.needsRepair)
        #expect(health.fixPrompt != nil)
    }

    @Test func artJobEmptyReportsWarning() throws {
        let job = ArtJob(name: "icon-test", path: "/fake/path", images: [], kind: .icon)
        let health = AppHealthChecker.check(artJob: job)
        #expect(!health.isHealthy)
        #expect(health.level == .warning)
    }

    @Test func artJobIconMissingIcnsReportsWarning() throws {
        let job = ArtJob(name: "icon-test", path: "/fake/path", images: ["icon-v1.png", "icon-v2.png"], kind: .icon)
        let health = AppHealthChecker.check(artJob: job)
        #expect(!health.isHealthy)
        #expect(health.level == .warning)
        #expect(health.fixPrompt?.contains("AppIcon.icns") == true)
    }

    @Test func artJobHealthyPasses() throws {
        let iconJob = ArtJob(name: "icon-test", path: "/fake/path", images: ["icon-v1.png", "AppIcon.icns"], kind: .icon)
        let iconHealth = AppHealthChecker.check(artJob: iconJob)
        #expect(iconHealth.isHealthy)

        let wallJob = ArtJob(name: "wallpaper-lake", path: "/fake/path", images: ["lake-sunrise.jpg"], kind: .wallpaper)
        let wallHealth = AppHealthChecker.check(artJob: wallJob)
        #expect(wallHealth.isHealthy)
    }
    @Test(arguments: [ProjectKind.menubar, .app, .screensaver])
    func pascalCaseBundlesAreRecognized(kind: ProjectKind) throws {
        let temp = try makeTempHome()
        let folder = temp.appendingPathComponent("example-app")
        let ext = kind == .screensaver ? "saver" : "app"
        try fm.createDirectory(at: folder.appendingPathComponent("build/ExampleApp.\(ext)"), withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: folder.appendingPathComponent("Package.swift"))
        let project = Project(name: "example-app", kind: kind, path: folder.path, created: Date())
        #expect(!AppHealthChecker.check(project: project).needsRepair)
    }

    @Test func cliBuildCacheRequiresAnExecutableNotJustADirectory() throws {
        let temp = try makeTempHome()
        let folder = temp.appendingPathComponent("cached-tool")
        let cache = temp.appendingPathComponent("cache")
        try fm.createDirectory(at: folder.appendingPathComponent(".build"), withIntermediateDirectories: true)
        try fm.createDirectory(at: cache.appendingPathComponent("release"), withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: folder.appendingPathComponent("Package.swift"))
        let project = Project(name: "cached-tool", kind: .cli, path: folder.path, created: Date())
        #expect(AppHealthChecker.check(project: project, buildCache: cache).needsRepair)
        let executable = cache.appendingPathComponent("release/cached-tool")
        try writeFile("#!/bin/sh\nexit 0\n", to: executable)
        #expect(AppHealthChecker.check(project: project, buildCache: cache).needsRepair)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        #expect(AppHealthChecker.check(project: project, buildCache: cache).isHealthy)
    }

    @Test func absentOptionalWallpaperDoesNotHideReadabilityFindings() throws {
        let temp = try makeTempHome()
        var theme = try Theme.decode(Data(sampleThemeJSON.utf8))
        theme.wallpapers = []
        theme.colors.foreground = theme.colors.background
        let folder = temp.appendingPathComponent(theme.slug)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(theme).write(to: folder.appendingPathComponent("theme.json"))
        let health = AppHealthChecker.check(theme: theme, themesFolder: temp)
        #expect(health.level == .advisory)
        #expect(!health.needsRepair)
        #expect(health.fixPrompt == nil)
        // The numerical finding remains available for review rather than disappearing behind artwork status.
        let contrast = try #require(ThemeLint.problems(theme).first { $0.kind == .contrast && $0.severity == .error })
        #expect(health.detail.contains(contrast.message))
    }


    @Test func scanArtJobsDiscoversDirectories() throws {
        let temp = try makeTempHome()
        let artFolder = temp.appendingPathComponent("Art")
        try fm.createDirectory(at: artFolder.appendingPathComponent("icon-app"), withIntermediateDirectories: true)
        try writeFile("img", to: artFolder.appendingPathComponent("icon-app/c1.png"))
        try fm.createDirectory(at: artFolder.appendingPathComponent("wallpaper-mountains"), withIntermediateDirectories: true)
        try writeFile("img", to: artFolder.appendingPathComponent("wallpaper-mountains/wall.jpg"))
        // ignored directory:
        try fm.createDirectory(at: artFolder.appendingPathComponent("antigravity-originals"), withIntermediateDirectories: true)

        let jobs = AppHealthChecker.scanArtJobs(artFolder: artFolder)
        #expect(jobs.count == 2)
        #expect(jobs.contains { $0.name == "icon-app" && $0.kind == .icon })
        #expect(jobs.contains { $0.name == "wallpaper-mountains" && $0.kind == .wallpaper })
    }
}
