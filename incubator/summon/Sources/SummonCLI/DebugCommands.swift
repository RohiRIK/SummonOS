import Foundation
import SummonCore

enum DebugCommands {
    /// `summon debug [--print] [--save] [--since 1h]`. Without flags it saves and prints the path.
    static func debug(_ args: inout Arguments, _ context: Context) async throws {
        let printOnly = args.flag("--print")
        _ = args.flag("--save")
        let window = args.option("--since") ?? "1h"
        guard window.allSatisfy({ $0.isNumber || "smhd".contains($0) }) else {
            throw CLIError("--since takes a window like 30m, 1h or 2d")
        }
        let bundle = DebugBundle(paths: context.paths, runner: context.runner, brewPath: context.brew, macctlPath: context.macctl)
        let text = await bundle.collect(logWindow: window)
        if printOnly {
            print(text)
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let file = context.paths.state.appendingPathComponent("debug-\(formatter.string(from: Date())).txt")
        try DebugBundle.save(text, to: file)
        print(file.path)
    }

    static func hooks(_ args: inout Arguments, _ context: Context) async throws {
        let runner = HookRunner(paths: context.paths, runner: context.runner)
        switch args.next() {
        case "list":
            for event in HookEvent.allCases {
                let scripts = runner.scripts(for: event)
                print("\(event.rawValue): \(scripts.isEmpty ? "none" : scripts.map(\.lastPathComponent).joined(separator: ", "))")
            }
        case "run":
            guard let name = args.next(), let event = HookEvent(rawValue: name) else {
                throw CLIError("Usage: summon hooks run <" + HookEvent.allCases.map(\.rawValue).joined(separator: "|") + "> [args...]")
            }
            let failures = await runner.run(event, arguments: args.items)
            for failure in failures { context.warn(failure) }
            if !failures.isEmpty { throw CLIError("\(failures.count) hook(s) failed") }
        default:
            throw CLIError("Usage: summon hooks list|run <event>")
        }
    }
}

enum MenuCommands {
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        switch args.next() {
        case "summon":
            let id = args.next() ?? ""
            let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-.")
            guard id.allSatisfy({ allowed.contains($0) }) else { throw CLIError("Menu ids use a-z, 0-9, - and .") }
            _ = try await context.runner("/usr/bin/open", ["-g", "summon://menu/\(id)"])
        case "init":
            let force = args.flag("--force")
            let file = context.paths.menuFile
            if FileManager.default.fileExists(atPath: file.path) && !force {
                print("\(file.path) already exists (use --force to replace it).")
                return
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(DefaultMenu.jsonc.utf8).write(to: file, options: .atomic)
            print(file.path)
        case "list":
            let tree = try loadTree(context)
            if args.flag("--json") {
                try context.printJSON(MenuFile(items: tree.items))
                return
            }
            for item in tree.items {
                let depth = item.id.filter { $0 == "." }.count
                let indent = String(repeating: "  ", count: depth)
                print("\(indent)\(item.label)  [\(item.id)]\(item.action == nil ? "" : "  → \(item.action ?? "")")")
            }
        default:
            throw CLIError("Usage: summon menu summon [id] | init [--force] | list [--json]")
        }
    }

    /// The user's menu when it exists and parses; otherwise the bundled default.
    static func loadTree(_ context: Context) throws -> MenuTree {
        let loaded = MenuTree.load(from: context.paths.menuFile)
        if let problem = loaded.problem {
            context.warn(problem)
        }
        return loaded.tree
    }
}
