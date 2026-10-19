import CoreGraphics
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
        case "shots":
            guard let name = args.next() else { throw CLIError("Usage: summon project shots <name>") }
            let images = try await ShotCommands.shots(name, context)
            print(images.isEmpty ? "README updated" : images.joined(separator: "\n"))
        default:
            throw CLIError("Usage: summon project new <name> --kind \(kinds) | list [--json] | path <name> | forget <name> | repo <name> [--owner <login>]")
        }
    }

    static var templates: URL {
        URL(fileURLWithPath: PathCommand.installPath()).appendingPathComponent("templates", isDirectory: true)
    }

    /// `summon project new <name> --kind <kind> [--json]`: copies the template to ~/Summon/Apps/<name> and registers it.
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
        // Every new app gets its private repo right away when the owner's standing approval is on (Settings ›
        // General; `summon default repos`). A missing gh or login never undoes the project: it says how to finish.
        var made = project
        if RepoPolicyStore(paths: context.paths).load() == .always {
            do {
                made = try await makeRepo(name, owner: nil, context, standingApproval: true)
            } catch {
                context.warn("summon: \(name) has no GitHub repo yet (\(error)). Finish with: summon project repo \(name)")
            }
        }
        if json {
            try ActivityCommands.printJSON(made)
        } else {
            print(made.path)
            if let repo = made.repo { print(repo) }
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
        let project = try await makeRepo(name, owner: owner, context,
                                         standingApproval: RepoPolicyStore(paths: context.paths).load() == .always)
        print(project.repo ?? "")
    }

    /// Screenshots, then the private repo (CI, first push). With the standing approval the dialog is skipped;
    /// otherwise the user's click in Summon's dialog is the approval. Always `--private`.
    static func makeRepo(_ name: String, owner: String?, _ context: Context, standingApproval: Bool) async throws -> Project {
        guard let gh = context.tools.find("gh") else {
            throw CLIError("GitHub CLI is not installed. Install it with: brew install gh, then gh auth login", code: .missingDependency)
        }
        guard let git = context.git else { throw CLIError("git is not installed.", code: .missingDependency) }
        let service = PrivateRepoService(paths: context.paths, runner: context.runner, ghPath: gh, gitPath: git)
        // Screenshots first, so the repo opens with pictures of the app (a failed capture never blocks the repo).
        do {
            _ = try await ShotCommands.shots(name, context)
        } catch {
            context.warn("screenshots skipped: \(error)")
        }
        let project: Project
        do {
            project = try await service.create(name: name, owner: owner) { request in
                standingApproval ? true : await RepoApprovalDialog.ask(request, runner: context.runner)
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
        return project
    }
}

/// The native approval for a private repo: a macOS dialog someone has to click. No flag or argument
/// answers it, and Return and Escape both cancel.
///
/// It runs in `osascript`, not as an NSAlert in this process: the CLI's async main runs main-actor work off
/// the real main thread, and an NSAlert there was closed by a run loop stop after about two seconds, which
/// ended `summon` with exit 0 and no answer.
enum RepoApprovalDialog {
    static let approveButton = "Create Private Repo"

    static func ask(_ request: RepoRequest, runner: Runner) async -> Bool {
        // No login window session (ssh, a launchd job): there is nobody to ask, so the answer is no.
        guard CGSessionCopyCurrentDictionary() != nil else { return false }
        let message = """
        Summon will create the private repository \(request.fullName) on GitHub from \
        \((request.directory as NSString).abbreviatingWithTildeInPath), add CI that runs scripts/check.sh, and push it \
        as your GitHub account. Nothing is made public.
        """
        let output = try? await runner("/usr/bin/osascript", arguments(
            title: "Create a private GitHub repo for \(request.project)?", message: message, icon: iconPath()))
        return output?.contains("button returned:\(approveButton)") ?? false
    }

    /// Text goes in as argv, never spliced into the script, so a project name cannot change what runs.
    static func arguments(title: String, message: String, icon: String?) -> [String] {
        let iconClause = icon == nil ? "with icon caution" : "with icon (POSIX file (item 3 of argv))"
        return [
            "-e", "on run argv",
            "-e", "activate",
            "-e", "display dialog (item 2 of argv) with title (item 1 of argv) buttons {\"Cancel\", \"\(approveButton)\"} "
                + "default button \"Cancel\" cancel button \"Cancel\" \(iconClause)",
            "-e", "end run",
            title, message,
        ] + (icon.map { [$0] } ?? [])
    }

    private static func iconPath() -> String? {
        let icon = URL(fileURLWithPath: PathCommand.installPath())
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/AppIcon.icns").path
        return FileManager.default.fileExists(atPath: icon) ? icon : nil
    }
}
