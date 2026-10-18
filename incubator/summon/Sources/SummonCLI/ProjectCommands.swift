import AppKit
import Foundation
import SummonCore

enum ProjectCommands {
    static let kinds = ProjectKind.allCases.map(\.rawValue).joined(separator: "|")

    /// `summon project new|list|path|forget|repo`.
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        switch args.next() {
        case "new": try await new(&args, context)
        case nil, "list": try list(&args, context)
        case "path": try path(&args, context)
        case "forget": try forget(&args, context)
        case "repo": try await repo(&args, context)
        default:
            throw CLIError("Usage: summon project new <name> --kind \(kinds) | list [--json] | path <name> | forget <name> | repo <name> [--owner <login>]")
        }
    }

    static var templates: URL {
        URL(fileURLWithPath: PathCommand.installPath()).appendingPathComponent("templates", isDirectory: true)
    }

    /// `summon project new <name> --kind <kind> [--json]`: copies the template to ~/Summon/<name> and registers it.
    static func new(_ args: inout Arguments, _ context: Context) async throws {
        let json = args.flag("--json")
        let kindName = args.option("--kind")
        guard let name = args.next(), args.isEmpty, let kindName else {
            throw CLIError("Usage: summon project new <name> --kind \(kinds) [--json]")
        }
        guard let kind = ProjectKind(rawValue: kindName.lowercased()) else {
            throw CLIError("Unknown kind: \(kindName)\nKnown: \(kinds.replacingOccurrences(of: "|", with: ", "))")
        }
        let service = ProjectService(paths: context.paths, runner: context.runner, gitPath: context.git)
        let (project, problems) = try await service.create(name: name, kind: kind, templates: templates)
        for problem in problems {
            context.warn("summon: \(problem)")
        }
        ActivityCommands.record(LoggedEvent(kind: EventKind.projectNew, title: "New \(kind.title.lowercased()) \(name)",
                                            refs: ["folder": project.path, "kind": kind.rawValue]), context)
        if json {
            try ActivityCommands.printJSON(project)
        } else {
            print(project.path)
        }
    }

    static func list(_ args: inout Arguments, _ context: Context) throws {
        let projects = try ProjectStore(paths: context.paths).load().projects
        if args.flag("--json") {
            try ActivityCommands.printJSON(projects)
            return
        }
        if projects.isEmpty {
            print("No projects yet. Start one: summon project new <name> --kind \(kinds)")
        }
        for project in projects {
            print([project.name, project.kind.rawValue, project.path, project.repo ?? "no repo"].joined(separator: "\t"))
        }
    }

    static func path(_ args: inout Arguments, _ context: Context) throws {
        guard let name = args.next() else {
            print(context.paths.projects.path)
            return
        }
        guard let project = try ProjectStore(paths: context.paths).load().find(name) else {
            throw CLIError(ProjectError.notRegistered(name).description)
        }
        print(project.path)
    }

    /// Removes a project from the list only; its folder and any repo stay.
    static func forget(_ args: inout Arguments, _ context: Context) throws {
        guard let name = args.next() else { throw CLIError("Usage: summon project forget <name>") }
        let store = ProjectStore(paths: context.paths)
        var registry = try store.load()
        guard let project = registry.remove(name) else { throw CLIError(ProjectError.notRegistered(name).description) }
        try store.save(registry)
        print("Forgot \(name). Its folder is still at \(project.path).")
    }

    /// `summon project repo <name> [--owner <login>]`: a private GitHub repo, only after the user approves it in
    /// a native dialog. Agents run with permission prompts off, so the dialog is the check, and no flag skips it.
    static func repo(_ args: inout Arguments, _ context: Context) async throws {
        let owner = args.option("--owner")
        guard let name = args.next(), args.isEmpty else { throw CLIError("Usage: summon project repo <name> [--owner <login>]") }
        guard let gh = context.tools.find("gh") else {
            throw CLIError("GitHub CLI is not installed. Install it with: brew install gh, then gh auth login", code: .missingDependency)
        }
        guard let git = context.git else { throw CLIError("git is not installed.", code: .missingDependency) }
        let service = PrivateRepoService(paths: context.paths, runner: context.runner, ghPath: gh, gitPath: git)
        let project: Project
        do {
            project = try await service.create(name: name, owner: owner) { request in
                await MainActor.run { RepoApprovalDialog.ask(request) }
            }
        } catch let error as ProjectError {
            if case let .pushFailed(repo, _) = error {
                ActivityCommands.record(LoggedEvent(kind: EventKind.projectRepo, title: "Private repo for \(name) (push failed)",
                                                    refs: ["repo": repo]), context)
            }
            throw CLIError(error.description)
        }
        ActivityCommands.record(LoggedEvent(kind: EventKind.projectRepo, title: "Private repo for \(name)",
                                            refs: ["folder": project.path, "repo": project.repo ?? ""]), context)
        print(project.repo ?? "")
    }
}

/// The native approval for a private repo. It runs in the `summon` process itself, so there is nothing for an
/// agent to pass or pre-answer: someone has to click the button.
enum RepoApprovalDialog {
    @MainActor
    static func ask(_ request: RepoRequest) -> Bool {
        // No login window session (ssh, a launchd job): there is nobody to ask, so the answer is no.
        guard CGSessionCopyCurrentDictionary() != nil else { return false }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.activate()

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Create a private GitHub repo for \(request.project)?"
        alert.informativeText = """
        Summon will create the private repository \(request.fullName) on GitHub from \
        \((request.directory as NSString).abbreviatingWithTildeInPath), add CI that runs scripts/check.sh, and push it \
        as your GitHub account. Nothing is made public.
        """
        let icon = URL(fileURLWithPath: PathCommand.installPath())
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns")
        if let image = NSImage(contentsOf: icon) {
            alert.icon = image
        }
        // Cancel is first, so Return and Escape both cancel; only a click on the second button approves.
        alert.addButton(withTitle: "Cancel")
        let create = alert.addButton(withTitle: "Create Private Repo")
        create.keyEquivalent = ""
        alert.window.level = .floating
        return alert.runModal() == .alertSecondButtonReturn
    }
}
