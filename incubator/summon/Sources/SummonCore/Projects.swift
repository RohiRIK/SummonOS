import Foundation

/// The four kinds of project Summon can start, one template each (`templates/<kind>` in the app's shared files).
public enum ProjectKind: String, CaseIterable, Codable, Sendable {
    case menubar
    case app
    case cli
    case screensaver

    public var title: String {
        switch self {
        case .menubar: "Menu Bar App"
        case .app: "Window App"
        case .cli: "Command-Line Tool"
        case .screensaver: "Screensaver"
        }
    }

    public var systemImage: String {
        switch self {
        case .menubar: "menubar.rectangle"
        case .app: "macwindow"
        case .cli: "terminal"
        case .screensaver: "display"
        }
    }

    /// The kebab-case name the template is written with; replaced by the project's name.
    public var placeholder: String { "\(rawValue)-starter" }
}

/// One project in Summon's private registry.
public struct Project: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public var name: String
    public var kind: ProjectKind
    public var path: String
    public var created: Date
    /// The private GitHub repo's URL, once `summon project repo` made one.
    public var repo: String?

    public init(name: String, kind: ProjectKind, path: String, created: Date, repo: String? = nil) {
        self.name = name
        self.kind = kind
        self.path = path
        self.created = created
        self.repo = repo
    }
}

/// `~/.config/summon/projects.json`. Private to this Mac: never written to plugins.json or any repo.
public struct ProjectRegistry: Codable, Sendable, Equatable {
    public var projects: [Project] = []

    public init(projects: [Project] = []) {
        self.projects = projects
    }

    public func find(_ name: String) -> Project? {
        projects.first { $0.name == name }
    }

    public mutating func upsert(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.name == project.name }) {
            projects[index] = project
        } else {
            projects.append(project)
        }
    }

    @discardableResult
    public mutating func remove(_ name: String) -> Project? {
        guard let index = projects.firstIndex(where: { $0.name == name }) else { return nil }
        return projects.remove(at: index)
    }
}

public struct ProjectStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    /// A missing file is an empty registry. A broken one is an error, so a save never wipes the user's list.
    public func load() throws -> ProjectRegistry {
        guard let data = try? Data(contentsOf: paths.projectRegistryFile) else { return ProjectRegistry() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ProjectRegistry.self, from: data)
    }

    public func save(_ registry: ProjectRegistry) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try TextFile.write(String(decoding: try encoder.encode(registry), as: UTF8.self) + "\n", to: paths.projectRegistryFile)
    }
}

/// `~/Summon`, made on install, on every app launch and before every agent launch.
public enum ProjectsFolder {
    public static func ensure(_ paths: SummonPaths) throws {
        try FileManager.default.createDirectory(at: paths.projects, withIntermediateDirectories: true)
    }
}

public enum ProjectName {
    /// Names that would turn into a module Swift already has (`Testing` → `TestingCore` is fine, `Testing` is not).
    static let reserved: Set<String> = ["Foundation", "SwiftUI", "AppKit", "Testing", "ScreenSaver", "Observation", "Swift", "Dispatch"]

    /// kebab-case, starting with a letter, at most 50 characters: it becomes a folder, a repo and a bundle id.
    public static func isValid(_ name: String) -> Bool {
        guard name.count <= 50, name.range(of: #"^[a-z][a-z0-9]*(-[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            return false
        }
        return !reserved.contains(pascal(name))
    }

    /// `mac-battery` → `MacBattery`, the Swift module and type prefix.
    public static func pascal(_ name: String) -> String {
        name.split(separator: "-").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
    }
}

/// Copies a template folder into a new project, renaming `Starter` and `<kind>-starter` and filling in the date.
public enum ProjectTemplate {
    public static let pascalPlaceholder = "Starter"
    static let skipped: Set<String> = [".build", ".swiftpm", "build", ".DS_Store"]

    public static func instantiate(template: URL, to destination: URL, name: String, kind: ProjectKind, date: Date) throws {
        let fileManager = FileManager.default
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let day = formatter.string(from: date)
        let replacements: [(String, String)] = [
            (kind.placeholder, name),
            (pascalPlaceholder, ProjectName.pascal(name)),
            ("{{DATE}}", day),
            ("{{YEAR}}", String(day.prefix(4))),
        ]
        func rename(_ text: String) -> String {
            replacements.reduce(text) { $0.replacingOccurrences(of: $1.0, with: $1.1) }
        }

        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let root = template.standardizedFileURL.resolvingSymlinksInPath().path
        guard let walker = fileManager.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isDirectoryKey]) else {
            throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: template.path])
        }
        for case let source as URL in walker {
            if skipped.contains(source.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            let fullPath = source.resolvingSymlinksInPath().path
            guard fullPath.hasPrefix(root + "/") else { continue }
            let relative = String(fullPath.dropFirst(root.count + 1))
            let target = destination.appendingPathComponent(rename(relative))
            if (try source.resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: source)
            if let text = String(data: data, encoding: .utf8) {
                try Data(rename(text).utf8).write(to: target)
            } else {
                try data.write(to: target)
            }
            // Keep scripts executable.
            if let mode = try fileManager.attributesOfItem(atPath: source.path)[.posixPermissions] {
                try fileManager.setAttributes([.posixPermissions: mode], ofItemAtPath: target.path)
            }
        }
    }
}

public enum ProjectError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidName(String)
    case alreadyExists(String)
    case alreadyRegistered(String)
    case noTemplate(String)
    case notRegistered(String)
    case notAGitRepo(String)
    case alreadyHasRepo(String)
    case hasRemote(String)
    case notApproved
    case pushFailed(repo: String, output: String)

    public var description: String {
        switch self {
        case let .invalidName(name):
            "Project names are kebab-case, start with a letter and are at most 50 characters (like mac-battery): \(name)"
        case let .alreadyExists(path): "\(path) already exists."
        case let .alreadyRegistered(name): "\(name) is already a Summon project (summon project list)."
        case let .noTemplate(path): "No template at \(path). Reinstall Summon or set SUMMON_PATH."
        case let .notRegistered(name): "\(name) is not a Summon project (summon project list)."
        case let .notAGitRepo(path): "\(path) is not a git repository."
        case let .alreadyHasRepo(repo): "This project already has a repo: \(repo)"
        case let .hasRemote(remotes): "This project already has a git remote (\(remotes)); Summon only creates a repo for a project without one."
        case .notApproved: "Not approved in the Summon dialog. No repo was created."
        case let .pushFailed(repo, output):
            "Created the private repo \(repo), but the push failed: \(output)\n"
                + "If GitHub refused the workflow file, run `gh auth refresh -s workflow`, then `git push -u origin HEAD` in the project."
        }
    }
}

/// Creates projects from templates and records them in the private registry.
public struct ProjectService: Sendable {
    public let paths: SummonPaths
    public let runner: Runner
    public let gitPath: String?

    public init(paths: SummonPaths, runner: @escaping Runner, gitPath: String?) {
        self.paths = paths
        self.runner = runner
        self.gitPath = gitPath
    }

    /// Copies `templates/<kind>` to `~/Summon/Apps/<name>`, makes it a git repo with a first commit, and registers it.
    /// Returns the project and any git problems (the project is usable without them).
    public func create(name: String, kind: ProjectKind, templates: URL, date: Date = Date()) async throws -> (Project, [String]) {
        guard ProjectName.isValid(name) else { throw ProjectError.invalidName(name) }
        let store = ProjectStore(paths: paths)
        var registry = try store.load()
        guard registry.find(name) == nil else { throw ProjectError.alreadyRegistered(name) }
        let template = templates.appendingPathComponent(kind.rawValue, isDirectory: true)
        guard FileManager.default.fileExists(atPath: template.appendingPathComponent("Package.swift").path) else {
            throw ProjectError.noTemplate(template.path)
        }
        try ProjectsFolder.ensure(paths)
        let destination = paths.projects.appendingPathComponent(name, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw ProjectError.alreadyExists(destination.path) }

        try ProjectTemplate.instantiate(template: template, to: destination, name: name, kind: kind, date: date)

        var problems: [String] = []
        if let git = gitPath {
            let dir = destination.path
            do {
                _ = try await runner(git, ["-C", dir, "init", "-q", "-b", "main"])
                _ = try await runner(git, ["-C", dir, "add", "-A"])
                _ = try await runner(git, ["-C", dir, "commit", "-q", "-m", "chore: start from the Summon \(kind.rawValue) template"])
            } catch {
                problems.append("git: \(error)")
            }
        } else {
            problems.append("git is not installed, so the project is not a git repository yet.")
        }

        let project = Project(name: name, kind: kind, path: destination.path, created: date)
        registry.upsert(project)
        try store.save(registry)
        return (project, problems)
    }

    /// Registers an existing app directory in `~/Summon/Apps/<name>` into the private registry.
    public func register(name: String, kind: ProjectKind? = nil, date: Date = Date()) async throws -> Project {
        guard ProjectName.isValid(name) else { throw ProjectError.invalidName(name) }
        let store = ProjectStore(paths: paths)
        var registry = try store.load()
        let destination = paths.projects.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: destination.path) else {
            throw ProjectError.notRegistered("Folder does not exist at \(destination.path)")
        }

        let resolvedKind = kind ?? detectKind(in: destination)

        var repoUrl: String? = nil
        if let git = gitPath {
            if let output = try? await runner(git, ["-C", destination.path, "remote", "get-url", "origin"]) {
                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { repoUrl = trimmed }
            }
        }

        let project = Project(name: name, kind: resolvedKind, path: destination.path, created: date, repo: repoUrl)
        registry.upsert(project)
        try store.save(registry)
        return project
    }

    /// Imports an external app directory into `~/Summon/Apps/<name>` and registers it.
    public func importProject(from source: URL, name: String? = nil, kind: ProjectKind? = nil, date: Date = Date()) async throws -> Project {
        let appName = name ?? source.lastPathComponent
        guard ProjectName.isValid(appName) else { throw ProjectError.invalidName(appName) }
        try ProjectsFolder.ensure(paths)
        let destination = paths.projects.appendingPathComponent(appName, isDirectory: true)

        if destination.standardizedFileURL.path != source.standardizedFileURL.path && !FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.copyItem(at: source, to: destination)
        }

        return try await register(name: appName, kind: kind, date: date)
    }

    public func detectKind(in folder: URL) -> ProjectKind {
        let pkg = folder.appendingPathComponent("Package.swift")
        if let content = try? String(contentsOf: pkg, encoding: .utf8) {
            if content.contains("ScreenSaver") { return .screensaver }
            if content.contains("executableTarget") && !content.contains("MenuBarExtra") { return .cli }
        }
        let sources = folder.appendingPathComponent("Sources")
        if let files = try? FileManager.default.subpathsOfDirectory(atPath: sources.path) {
            for file in files {
                if file.hasSuffix(".swift"), let code = try? String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8) {
                    if code.contains("MenuBarExtra") || code.contains("NSStatusItem") { return .menubar }
                    if code.contains("ScreenSaverView") { return .screensaver }
                    if code.contains("WindowGroup") { return .app }
                }
            }
        }
        return .menubar
    }
}

/// What the approval dialog shows, and what gets created if the user approves.
public struct RepoRequest: Sendable, Equatable {
    public let project: String
    public let owner: String?
    public let directory: String

    public init(project: String, owner: String?, directory: String) {
        self.project = project
        self.owner = owner
        self.directory = directory
    }

    public var fullName: String { owner.map { "\($0)/\(project)" } ?? project }
}

/// The CI a project gets with its private repo (none before: without a repo there is nothing to run it).
public enum ProjectCI {
    public static let workflowPath = ".github/workflows/check.yml"
    public static let workflow = """
    # Runs the project's own gate on a macOS runner. Added by `summon project repo` with the private repo.
    name: Check

    on:
      push:
      workflow_dispatch:

    jobs:
      check:
        runs-on: macos-26
        timeout-minutes: 30
        steps:
          - uses: actions/checkout@v4
          - run: scripts/check.sh

    """
}

/// Creates a project's private GitHub repo. The approver (a native Summon dialog in the CLI) runs before
/// anything is written; there is no flag that skips it and no way to make a public repo here.
public struct PrivateRepoService: Sendable {
    public typealias Approver = @Sendable (RepoRequest) async -> Bool

    public let paths: SummonPaths
    public let runner: Runner
    public let ghPath: String
    public let gitPath: String

    public init(paths: SummonPaths, runner: @escaping Runner, ghPath: String, gitPath: String) {
        self.paths = paths
        self.runner = runner
        self.ghPath = ghPath
        self.gitPath = gitPath
    }

    /// The one `gh` call that makes the repo. Always `--private`.
    public static func createArguments(_ request: RepoRequest) -> [String] {
        ["repo", "create", request.fullName, "--private", "--source", request.directory, "--remote", "origin"]
    }

    public func create(name: String, owner: String?, approve: Approver) async throws -> Project {
        let store = ProjectStore(paths: paths)
        var registry = try store.load()
        guard var project = registry.find(name) else { throw ProjectError.notRegistered(name) }
        if let repo = project.repo { throw ProjectError.alreadyHasRepo(repo) }
        let dir = project.path
        guard FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent(".git")) else {
            throw ProjectError.notAGitRepo(dir)
        }
        let remotes = try await runner(gitPath, ["-C", dir, "remote"]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard remotes.isEmpty else { throw ProjectError.hasRemote(remotes) }

        let request = RepoRequest(project: name, owner: owner, directory: dir)
        guard await approve(request) else { throw ProjectError.notApproved }

        // CI arrives with the repo. Commit everything only when the project has no commit yet.
        let workflow = URL(fileURLWithPath: dir).appendingPathComponent(ProjectCI.workflowPath)
        if !FileManager.default.fileExists(atPath: workflow.path) {
            try TextFile.write(ProjectCI.workflow, to: workflow)
        }
        let hasCommit = (try? await runner(gitPath, ["-C", dir, "rev-parse", "--verify", "-q", "HEAD"])) != nil
        _ = try await runner(gitPath, ["-C", dir, "add"] + (hasCommit ? [ProjectCI.workflowPath] : ["-A"]))
        let staged = (try? await runner(gitPath, ["-C", dir, "diff", "--cached", "--quiet"])) == nil
        if staged {
            _ = try await runner(gitPath, ["-C", dir, "commit", "-q", "-m", hasCommit ? "ci: run scripts/check.sh on push" : "chore: first commit"])
        }

        _ = try await runner(ghPath, Self.createArguments(request))
        let url = (try? await runner(gitPath, ["-C", dir, "remote", "get-url", "origin"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        project.repo = (url?.isEmpty ?? true) ? request.fullName : url
        registry.upsert(project)
        try store.save(registry)

        do {
            _ = try await runner(gitPath, ["-C", dir, "push", "-u", "origin", "HEAD"])
        } catch {
            throw ProjectError.pushFailed(repo: project.repo ?? request.fullName, output: "\(error)")
        }
        return project
    }
}

/// Whether a new project gets its private GitHub repo right away (`always`, the owner's standing approval in Settings)
/// or only after the approval dialog (`ask`). Repos are private either way; Summon never makes a public one.
public enum RepoPolicy: String, Sendable, CaseIterable {
    case always, ask
}

/// `~/.config/summon/defaults/repos`; missing means `always` (owner, 2026-10-19).
public struct RepoPolicyStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    var file: URL { paths.config.appendingPathComponent("defaults/repos") }

    public func load() -> RepoPolicy {
        TextFile.firstLine(file).flatMap(RepoPolicy.init(rawValue:)) ?? .always
    }

    public func save(_ policy: RepoPolicy) throws {
        try TextFile.write(policy.rawValue + "\n", to: file)
    }
}
