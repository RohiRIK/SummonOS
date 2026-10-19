import Foundation
import SummonCore

/// Exit codes shared by every subcommand.
enum ExitCode: Int32 {
    case ok = 0
    case error = 1
    case missingDependency = 2
    case unsupported = 4
}

struct CLIError: Error {
    let message: String
    let code: ExitCode

    init(_ message: String, code: ExitCode = .error) {
        self.message = message
        self.code = code
    }
}

@main
struct SummonCommand {
    @MainActor
    static func main() async {
        var args = Arguments(Array(CommandLine.arguments.dropFirst()))
        let context = Context.live()
        do {
            try await dispatch(&args, context)
            exit(ExitCode.ok.rawValue)
        } catch let error as CLIError {
            // An empty message means the command already printed why (`summon doctor` with a failed check).
            if !error.message.isEmpty {
                FileHandle.standardError.write(Data((error.message + "\n").utf8))
            }
            exit(error.code.rawValue)
        } catch {
            FileHandle.standardError.write(Data("summon: \(error)\n".utf8))
            exit(ExitCode.error.rawValue)
        }
    }

    @MainActor
    static func dispatch(_ args: inout Arguments, _ context: Context) async throws {
        guard let command = args.next() else {
            print(CommandCatalog.helpText())
            return
        }
        switch command {
        case "agent":
            try await AgentCommands.agent(&args, context)
        case "default":
            switch args.next() {
            case "agent": try AgentCommands.defaultAgent(&args, context)
            case "terminal": try AgentCommands.defaultTerminal(&args, context)
            default: throw CLIError("Usage: summon default agent [name] | summon default terminal [name]")
            }
        case "agents":
            if args.items.first == "set" {
                _ = args.next()
                try AgentCommands.set(&args, context)
            } else if args.items.first == "status" {
                _ = args.next()
                try AgentProbeCommands.status(&args, context)
            } else if args.items.first == "login" {
                _ = args.next()
                try await AgentProbeCommands.login(&args, context)
            } else {
                try AgentCommands.list(&args, context)
            }
        case "checkpoint":
            try await AgentCommands.checkpoint(&args, context)
        case "undo-session":
            try await AgentCommands.undoSession(&args, context)
        case "events":
            try ActivityCommands.events(&args, context)
        case "event":
            try ActivityCommands.eventAdd(&args, context)
        case "status":
            try await ActivityCommands.status(&args, context)
        case "doctor":
            try await DoctorCommand.run(&args, context)
        case "crash":
            try await CrashCommands.run(&args, context)
        case "theme":
            try await ThemeCommands.run(&args, context)
        case "debug":
            try await DebugCommands.debug(&args, context)
        case "hooks":
            try await DebugCommands.hooks(&args, context)
        case "menu":
            try await MenuCommands.run(&args, context)
        case "icon":
            try IconCommands.run(&args, context)
        case "task", "tasks":
            try await TaskCommands.run(&args, context)
        case "project":
            try await ProjectCommands.run(&args, context)
        case "path":
            print(PathCommand.installPath())
        case "skills":
            try SkillCommands.run(&args, context)
        case "commands":
            if args.flag("--json") {
                print(try CommandCatalog.json())
            } else {
                for info in CommandCatalog.all {
                    print("summon \(info.route) \(info.args)".trimmingCharacters(in: .whitespaces))
                    print("    \(info.summary)")
                }
            }
        case "help", "--help", "-h":
            print(CommandCatalog.helpText())
        default:
            throw CLIError("Unknown command: \(command)\n\n" + CommandCatalog.helpText())
        }
    }
}

/// What every subcommand needs, built once.
struct Context: Sendable {
    let paths: SummonPaths
    let runner: Runner
    let tools: ToolLocator

    static func live() -> Context {
        Context(paths: .live, runner: Shell.live, tools: .live())
    }

    var macctl: String? { tools.find("macctl") }
    var git: String? { tools.find("git") }
    var brew: String? { tools.find("brew") }

    func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }

    func warn(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
