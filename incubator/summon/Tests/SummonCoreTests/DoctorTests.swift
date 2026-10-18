import Foundation
import Testing
@testable import SummonCore

@Suite("summon doctor")
struct DoctorTests {
    let fm = FileManager.default

    /// A doctor on a temp home whose installed tools are `tools` (looked up by name in /fake/bin).
    func makeDoctor(
        home: URL,
        tools: Set<String> = [],
        onShellPath: Bool = true,
        runner: @escaping Runner = fakeRunner(CallLog()),
        running: Bool = true
    ) throws -> Doctor {
        let share = home.appendingPathComponent("share/summon", isDirectory: true)
        for name in ["summon", "summon-mac"] {
            try writeFile("---\nname: \(name)\n---\n", to: share.appendingPathComponent("skills/\(name)/SKILL.md"))
        }
        try writeFile(sampleThemeJSON, to: share.appendingPathComponent("themes/summon-night/theme.json"))
        for kind in ProjectKind.allCases {
            try writeFile("// swift-tools-version: 6.0\n", to: share.appendingPathComponent("templates/\(kind.rawValue)/Package.swift"))
        }
        let installed = tools
        let locator = ToolLocator(searchPath: ["/fake/bin"]) { path in
            installed.contains((path as NSString).lastPathComponent)
        }
        let shell = ToolLocator(searchPath: onShellPath ? ["/fake/bin"] : []) { path in
            installed.contains((path as NSString).lastPathComponent)
        }
        return Doctor(
            paths: SummonPaths(home: home),
            runner: runner,
            tools: locator,
            shellTools: shell,
            share: share,
            appLocations: [home.appendingPathComponent("Applications/Summon.app")],
            installedTerminals: [.terminal],
            isProcessRunning: { _ in running }
        )
    }

    /// A home set up the way scripts/install.sh leaves it, with Claude Code installed and linked.
    func healthyHome() throws -> URL {
        let home = try makeTempHome()
        let paths = SummonPaths(home: home)
        try fm.createDirectory(at: home.appendingPathComponent("Applications/Summon.app"), withIntermediateDirectories: true)
        try fm.createDirectory(at: home.appendingPathComponent(".config/.git"), withIntermediateDirectories: true)
        let project = paths.projects.appendingPathComponent("mac-battery", isDirectory: true)
        try fm.createDirectory(at: project, withIntermediateDirectories: true)
        try ProjectStore(paths: paths).save(ProjectRegistry(projects: [
            Project(name: "mac-battery", kind: .menubar, path: project.path, created: Date(timeIntervalSince1970: 1_800_000_000)),
        ]))
        try writeFile("claude\n", to: paths.defaultAgentFile)
        try writeFile(DefaultMenu.jsonc, to: paths.menuFile)
        try writeFile(sampleThemeJSON, to: paths.themes.appendingPathComponent("summon-night/theme.json"))
        try writeFile("summon-night\n", to: paths.currentThemeFile)
        try EventLog(paths: paths).append(LoggedEvent(kind: EventKind.themeSet, title: "Theme Summon Night"))
        try AppHealthStore(paths: paths).save(AppHealth(pid: 4242, hotkeys: ["⌃⌥Space": true, "⌃⌥⌘A": true], notifications: "authorized"))
        try writeFile(#"{"plugins": {"summon@local": []}}"#, to: home.appendingPathComponent(".claude/plugins/installed_plugins.json"))
        let share = home.appendingPathComponent("share/summon/skills")
        for name in ["summon", "summon-mac"] {
            let link = home.appendingPathComponent(".claude/skills/\(name)")
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: share.appendingPathComponent(name).path)
        }
        return home
    }

    static let macctlOK = #"{"ok": true, "result": {"checks": [{"name": "automation", "ok": true, "detail": "granted"}]}}"#

    @Test func healthyInstallPassesEveryCheck() async throws {
        let home = try healthyHome()
        let doctor = try makeDoctor(home: home, tools: ["summon", "claude", "macctl", "git"],
                                    runner: fakeRunner(CallLog(), responses: ["macctl": Self.macctlOK]))
        let report = await doctor.run()
        let notPassing = report.checks.filter { $0.status != .pass }
        #expect(notPassing.isEmpty, "\(notPassing)")
        #expect(report.check("skills.links")?.detail.contains("Claude Code") == true)
        #expect(report.check("app.hotkeys")?.status == .pass)
        #expect(report.check("config.themes")?.detail.contains("current summon-night") == true)
    }

    @Test func emptyHomeFailsWithFixes() async throws {
        let home = try makeTempHome()
        let doctor = try makeDoctor(home: home, onShellPath: false)
        let report = await doctor.run()
        #expect(report.status == .fail)
        #expect(report.check("config.folder")?.status == .fail)
        #expect(report.check("macctl")?.status == .fail)
        #expect(report.check("install.app")?.status == .warn)
        #expect(report.check("install.cli")?.status == .warn)
        #expect(report.check("config.agent")?.fix == "summon default agent claude")
        #expect(report.check("app.running")?.status == .warn)
        #expect(report.check("state.events")?.status == .pass)  // no log yet is fine
        #expect(report.check("projects.folder")?.status == .warn)
        #expect(report.check("projects.registry")?.detail == "No projects yet")
        #expect(report.check("install.files")?.status == .pass)
        // Every check that did not pass says how to fix it.
        #expect(report.checks.filter { $0.status != .pass && $0.fix == nil }.isEmpty)
    }

    @Test func defaultAgentNotInstalledFails() async throws {
        let home = try healthyHome()
        let report = try await makeDoctor(home: home, tools: ["macctl"]).run()
        let agent = try #require(report.check("config.agent"))
        #expect(agent.status == .fail)
        #expect(agent.fix == AgentRegistry.find("claude")?.installHint)
    }

    @Test func unknownDefaultAgentFails() async throws {
        let home = try healthyHome()
        try writeFile("nonesuch\n", to: SummonPaths(home: home).defaultAgentFile)
        let report = try await makeDoctor(home: home, tools: ["claude"]).run()
        #expect(report.check("config.agent")?.status == .fail)
    }

    @Test func macctlProblemsAreWarnings() async throws {
        let home = try healthyHome()
        let output = #"{"ok": true, "result": {"checks": [{"name": "automation", "ok": false, "detail": "not granted"}]}}"#
        let report = try await makeDoctor(home: home, tools: ["macctl"], runner: fakeRunner(CallLog(), responses: ["macctl": output])).run()
        let check = try #require(report.check("macctl"))
        #expect(check.status == .warn)
        #expect(check.detail.contains("automation: not granted"))
    }

    @Test func brokenEventLogLinesAreCounted() async throws {
        let home = try healthyHome()
        let file = SummonPaths(home: home).eventLogFile
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("not json\n".utf8))
        try handle.close()
        let report = try await makeDoctor(home: home).run()
        let check = try #require(report.check("state.events"))
        #expect(check.status == .warn)
        #expect(check.detail.hasPrefix("1 of 2 lines"))
    }

    @Test func brokenConfigFilesAreReported() async throws {
        let home = try healthyHome()
        let paths = SummonPaths(home: home)
        try writeFile("{ not a menu", to: paths.menuFile)
        try writeFile(#"{"agents": {"nonesuch": {}, "claude": {"skills": ["summon", "gone"]}}}"#, to: paths.agentSettingsFile)
        try writeFile("missing-theme\n", to: paths.currentThemeFile)
        let report = try await makeDoctor(home: home, tools: ["claude"]).run()
        #expect(report.check("config.menu")?.status == .fail)
        let agents = try #require(report.check("config.agents"))
        #expect(agents.status == .warn)
        #expect(agents.detail.contains("unknown agent \"nonesuch\""))
        #expect(agents.detail.contains("claude: unknown skills gone"))
        #expect(report.check("config.themes")?.fix == "summon theme set summon-night")

        try writeFile("not json", to: paths.agentSettingsFile)
        let again = try await makeDoctor(home: home, tools: ["claude"]).run()
        #expect(again.check("config.agents")?.status == .fail)
    }

    @Test func missingAndStaleSkillLinksWarn() async throws {
        let home = try healthyHome()
        let link = home.appendingPathComponent(".claude/skills/summon")
        try fm.removeItem(at: link)
        try fm.createSymbolicLink(atPath: link.path, withDestinationPath: "/old/Summon.app/Contents/share/summon/skills/summon")
        try fm.removeItem(at: home.appendingPathComponent(".claude/skills/summon-mac"))
        let report = try await makeDoctor(home: home, tools: ["claude"]).run()
        let check = try #require(report.check("skills.links"))
        #expect(check.status == .warn)
        #expect(check.detail.contains("missing ~/.claude/skills/summon-mac"))
        #expect(check.detail.contains("old or missing install: ~/.claude/skills/summon"))
        #expect(check.fix == "summon skills link")
    }

    @Test func usersOwnSkillFolderIsNotAProblem() async throws {
        let home = try healthyHome()
        let link = home.appendingPathComponent(".claude/skills/summon")
        try fm.removeItem(at: link)
        try fm.createDirectory(at: link, withIntermediateDirectories: true)
        let report = try await makeDoctor(home: home, tools: ["claude"]).run()
        #expect(report.check("skills.links")?.status == .pass)
    }

    @Test func appStateDrivesHotkeyAndNotificationChecks() async throws {
        let home = try healthyHome()
        let paths = SummonPaths(home: home)
        try AppHealthStore(paths: paths).save(AppHealth(pid: 4242, hotkeys: ["⌃⌥Space": false, "⌃⌥⌘A": true], notifications: "denied"))
        let report = try await makeDoctor(home: home).run()
        let hotkeys = try #require(report.check("app.hotkeys"))
        #expect(hotkeys.status == .fail)
        #expect(hotkeys.detail.hasPrefix("⌃⌥Space taken"))
        #expect(report.check("app.notifications")?.status == .warn)

        let stopped = try await makeDoctor(home: home, running: false).run()
        #expect(stopped.check("app.running")?.status == .warn)
        #expect(stopped.check("app.hotkeys") == nil)
    }

    @Test func projectsFolderAndRegistry() async throws {
        let home = try healthyHome()
        let paths = SummonPaths(home: home)
        try fm.removeItem(at: paths.projects.appendingPathComponent("mac-battery"))
        let report = try await makeDoctor(home: home).run()
        let registry = try #require(report.check("projects.registry"))
        #expect(registry.status == .warn)
        #expect(registry.detail.contains("folder missing for mac-battery"))
        #expect(report.check("projects.folder")?.status == .pass)

        try writeFile("{ broken", to: paths.projectRegistryFile)
        try fm.removeItem(at: paths.projects)
        let broken = try await makeDoctor(home: home).run()
        #expect(broken.check("projects.registry")?.status == .fail)
        #expect(broken.check("projects.folder")?.status == .warn)
    }

    @Test func missingProjectTemplateWarns() async throws {
        let home = try healthyHome()
        let doctor = try makeDoctor(home: home)
        try fm.removeItem(at: doctor.share.appendingPathComponent("templates/screensaver"))
        let report = await doctor.run()
        let check = try #require(report.check("install.files"))
        #expect(check.status == .warn)
        #expect(check.detail.contains("no project template for screensaver"))
    }

    @Test func reportStatusAndRendering() {
        let report = DoctorReport(checks: [
            DoctorCheck("a", .pass, "fine"),
            DoctorCheck("bb", .warn, "meh", fix: "do x"),
        ])
        #expect(report.status == .warn)
        let text = Doctor.render(report)
        #expect(text.contains("ok    a   fine"))
        #expect(text.contains("warn  bb  meh"))
        #expect(text.contains("fix: do x"))
        #expect(text.hasSuffix("0 failed, 1 warning(s)."))
        #expect(Doctor.render(DoctorReport(checks: [DoctorCheck("a", .pass, "fine")])).hasSuffix("Summon is healthy."))
    }

    @Test func doctorIsInTheCatalog() {
        #expect(CommandCatalog.find("doctor")?.risk == "read")
    }
}
