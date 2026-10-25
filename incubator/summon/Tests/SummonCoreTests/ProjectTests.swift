import Foundation
import Testing
@testable import SummonCore

/// The templates shipped in this package (`templates/<kind>`), so the tests check the real files.
let shippedTemplates = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("templates", isDirectory: true)

/// Records how often the approval dialog was asked, and answers with `answer`.
actor ApprovalLog {
    private(set) var requests: [RepoRequest] = []
    let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    func ask(_ request: RepoRequest) -> Bool {
        requests.append(request)
        return answer
    }
}

func allFiles(under root: URL) -> [URL] {
    let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])
    return (walker?.allObjects as? [URL] ?? []).filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
}

@Suite("Projects: templates, ~/Summon, private registry, private repos")
struct ProjectTests {
    let date = Date(timeIntervalSince1970: 1_792_324_800)  // 2026-10-18

    @Test func namesAreKebabCase() {
        #expect(ProjectName.isValid("mac-battery"))
        #expect(ProjectName.isValid("app2"))
        #expect(!ProjectName.isValid("Mac-Battery"))
        #expect(!ProjectName.isValid("2app"))
        #expect(!ProjectName.isValid("mac--battery"))
        #expect(!ProjectName.isValid("../escape"))
        #expect(!ProjectName.isValid(""))
        #expect(!ProjectName.isValid("testing"))
        #expect(ProjectName.pascal("mac-battery") == "MacBattery")
    }

    @Test func projectKindsHaveSystemImages() {
        #expect(ProjectKind.menubar.systemImage == "menubar.rectangle")
        #expect(ProjectKind.app.systemImage == "macwindow")
        #expect(ProjectKind.cli.systemImage == "terminal")
        #expect(ProjectKind.screensaver.systemImage == "display")
    }

    @Test func liveHomeFollowsHOME() {
        #expect(SummonPaths.liveHome(environment: ["HOME": "/tmp/ci-home"]).path == "/tmp/ci-home")
        #expect(SummonPaths.liveHome(environment: [:]) == FileManager.default.homeDirectoryForCurrentUser)
        #expect(SummonPaths.liveHome(environment: ["HOME": "relative"]) == FileManager.default.homeDirectoryForCurrentUser)
    }

    @Test func projectsLiveInSummonUnderHome() throws {
        let paths = SummonPaths(home: try makeTempHome())
        #expect(paths.projects.path.hasSuffix("/Summon/Apps"))
        #expect(paths.projectRegistryFile.path.hasSuffix("/.config/summon/projects.json"))
        try ProjectsFolder.ensure(paths)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: paths.projects.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    @Test(arguments: ProjectStarter.allCases)
    func everyTemplateIsComplete(kind: ProjectStarter) throws {
        let template = shippedTemplates.appendingPathComponent(kind.rawValue)
        for file in ["Package.swift", "README.md", "LICENSE", "PROJECT-CONTEXT.md", ".gitignore", "scripts/check.sh"] {
            #expect(FileManager.default.fileExists(atPath: template.appendingPathComponent(file).path), "\(kind) misses \(file)")
        }
        let mode = try FileManager.default.attributesOfItem(atPath: template.appendingPathComponent("scripts/check.sh").path)[.posixPermissions] as? Int
        #expect((mode ?? 0) & 0o111 != 0, "\(kind) check.sh is not executable")
    }

    @Test(arguments: ProjectStarter.allCases)
    func templateBecomesTheNamedProject(kind: ProjectStarter) throws {
        let home = try makeTempHome()
        let destination = home.appendingPathComponent("Summon/mac-battery")
        try ProjectTemplate.instantiate(template: shippedTemplates.appendingPathComponent(kind.rawValue),
                                        to: destination, name: "mac-battery", kind: kind, date: date)
        let files = allFiles(under: destination)
        #expect(!files.isEmpty)
        for file in files {
            let relative = String(file.path.dropFirst(destination.path.count))
            #expect(!relative.contains("Starter") && !relative.contains(kind.placeholder), "path not renamed: \(relative)")
            if file.pathExtension == "icns" { continue } // binary art, copied as is
            let text = try String(contentsOf: file, encoding: .utf8)
            for leftover in ["Starter", kind.placeholder, "{{DATE}}", "{{YEAR}}"] {
                #expect(!text.contains(leftover), "\(relative) still says \(leftover)")
            }
        }
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("Sources/MacBatteryCore").path))
        let license = try String(contentsOf: destination.appendingPathComponent("LICENSE"), encoding: .utf8)
        #expect(license.contains("2026"))
        let context = try String(contentsOf: destination.appendingPathComponent("PROJECT-CONTEXT.md"), encoding: .utf8)
        #expect(context.contains("2026-10-18"))
        let mode = try FileManager.default.attributesOfItem(atPath: destination.appendingPathComponent("scripts/check.sh").path)[.posixPermissions] as? Int
        #expect((mode ?? 0) & 0o111 != 0)
    }

    @Test func newProjectIsCopiedCommittedAndRegistered() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let log = CallLog()
        let service = ProjectService(paths: paths, runner: fakeRunner(log), gitPath: "/usr/bin/git")
        let (project, problems) = try await service.create(name: "mac-battery", kind: .menubar, templates: shippedTemplates, date: date)
        #expect(problems.isEmpty)
        #expect(project.path == paths.projects.appendingPathComponent("mac-battery").path)
        #expect(FileManager.default.fileExists(atPath: project.path + "/Sources/MacBattery/MacBatteryApp.swift"))
        let calls = await log.calls
        #expect(calls.map { Array($0.dropFirst(3).prefix(1)) } == [["init"], ["add"], ["commit"]])
        #expect(try ProjectStore(paths: paths).load().find("mac-battery") == project)

        await #expect(throws: ProjectError.alreadyRegistered("mac-battery")) {
            _ = try await service.create(name: "mac-battery", kind: .app, templates: shippedTemplates)
        }
        await #expect(throws: ProjectError.invalidName("My App")) {
            _ = try await service.create(name: "My App", kind: .app, templates: shippedTemplates)
        }
    }

    @Test func registryRoundTripsAndABrokenFileIsNotOverwritten() throws {
        let paths = SummonPaths(home: try makeTempHome())
        let store = ProjectStore(paths: paths)
        #expect(try store.load().projects.isEmpty)
        var registry = ProjectRegistry()
        registry.upsert(Project(name: "a", kind: .cli, path: "/u/a/Summon/a", created: date))
        try store.save(registry)
        #expect(try store.load() == registry)
        #expect(registry.remove("a") != nil)
        #expect(registry.projects.isEmpty)
        try writeFile("{ not json", to: paths.projectRegistryFile)
        #expect(throws: (any Error).self) { _ = try store.load() }
    }

    /// A registered project with a .git folder, for the repo tests.
    func registeredProject(_ paths: SummonPaths) throws -> Project {
        let project = Project(name: "mac-battery", kind: .menubar, path: paths.projects.appendingPathComponent("mac-battery").path, created: date)
        try FileManager.default.createDirectory(atPath: project.path + "/.git", withIntermediateDirectories: true)
        try ProjectStore(paths: paths).save(ProjectRegistry(projects: [project]))
        return project
    }

    @Test func noRepoWithoutApproval() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let project = try registeredProject(paths)
        let log = CallLog()
        let approvals = ApprovalLog(answer: false)
        let service = PrivateRepoService(paths: paths, runner: fakeRunner(log), ghPath: "/opt/homebrew/bin/gh", gitPath: "/usr/bin/git")
        await #expect(throws: ProjectError.notApproved) {
            _ = try await service.create(name: "mac-battery", owner: nil) { await approvals.ask($0) }
        }
        #expect(await approvals.requests.count == 1)
        let calls = await log.calls
        #expect(!calls.contains { $0[0].hasSuffix("/gh") })
        #expect(calls.allSatisfy { $0.contains("remote") })
        #expect(!FileManager.default.fileExists(atPath: project.path + "/" + ProjectCI.workflowPath))
        #expect(try ProjectStore(paths: paths).load().find("mac-battery")?.repo == nil)
    }

    @Test func approvedRepoIsPrivateWithCI() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        let project = try registeredProject(paths)
        let log = CallLog()
        let approvals = ApprovalLog(answer: true)
        let service = PrivateRepoService(paths: paths, runner: fakeRunner(log), ghPath: "/opt/homebrew/bin/gh", gitPath: "/usr/bin/git")
        let made = try await service.create(name: "mac-battery", owner: "octo") { await approvals.ask($0) }
        #expect(await approvals.requests == [RepoRequest(project: "mac-battery", owner: "octo", directory: project.path)])
        let gh = await log.calls.filter { $0[0].hasSuffix("/gh") }
        #expect(gh == [["/opt/homebrew/bin/gh", "repo", "create", "octo/mac-battery", "--private", "--source", project.path, "--remote", "origin"]])
        #expect(!gh.joined().contains("--public"))
        #expect(await log.calls.last == ["/usr/bin/git", "-C", project.path, "push", "-u", "origin", "HEAD"])
        #expect(FileManager.default.fileExists(atPath: project.path + "/" + ProjectCI.workflowPath))
        #expect(made.repo == "octo/mac-battery")
        #expect(try ProjectStore(paths: paths).load().find("mac-battery")?.repo == "octo/mac-battery")

        await #expect(throws: ProjectError.alreadyHasRepo("octo/mac-battery")) {
            _ = try await service.create(name: "mac-battery", owner: nil) { await approvals.ask($0) }
        }
        #expect(await approvals.requests.count == 1)
    }

    @Test func projectWithARemoteIsRefusedBeforeTheDialog() async throws {
        let paths = SummonPaths(home: try makeTempHome())
        _ = try registeredProject(paths)
        let log = CallLog()
        let approvals = ApprovalLog(answer: true)
        let service = PrivateRepoService(paths: paths, runner: fakeRunner(log, responses: ["git": "origin\n"]),
                                         ghPath: "/opt/homebrew/bin/gh", gitPath: "/usr/bin/git")
        await #expect(throws: ProjectError.hasRemote("origin")) {
            _ = try await service.create(name: "mac-battery", owner: nil) { await approvals.ask($0) }
        }
        #expect(await approvals.requests.isEmpty)
    }

    @Test func registerExistingFolder() async throws {
        let temp = try makeTempHome()
        let paths = SummonPaths(home: temp)
        try ProjectsFolder.ensure(paths)
        let appDir = paths.projects.appendingPathComponent("custom-widget", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\nimport PackageDescription\nlet p = Package(name: \"CustomWidget\", targets: [.executableTarget(name: \"CustomWidget\")])\n",
                       to: appDir.appendingPathComponent("Package.swift"))

        let log = CallLog()
        let service = ProjectService(paths: paths, runner: fakeRunner(log), gitPath: nil)
        let project = try await service.register(name: "custom-widget")
        #expect(project.name == "custom-widget")
        #expect(project.path == appDir.path)
        #expect(try ProjectStore(paths: paths).load().find("custom-widget") != nil)
    }

    @Test func importExternalFolder() async throws {
        let temp = try makeTempHome()
        let paths = SummonPaths(home: temp)
        let external = temp.appendingPathComponent("external-tool")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try writeFile("// swift-tools-version: 6.0\n", to: external.appendingPathComponent("Package.swift"))

        let log = CallLog()
        let service = ProjectService(paths: paths, runner: fakeRunner(log), gitPath: nil)
        let project = try await service.importProject(from: external, name: "imported-tool")
        #expect(project.name == "imported-tool")
        #expect(FileManager.default.fileExists(atPath: paths.projects.appendingPathComponent("imported-tool").path))
        #expect(try ProjectStore(paths: paths).load().find("imported-tool") != nil)
    }
}
