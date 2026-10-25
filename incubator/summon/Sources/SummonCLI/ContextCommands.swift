import Foundation
import SummonCore

enum ContextCommands {
    static let usage = "Usage: summon context [--json | --hook <agent>] [--only a,b] | context fields | context hide|show <field>"

    /// `summon context [--json] [--only a,b]`, `summon context fields`, `summon context hide|show <field>`.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) throws {
        let store = AgentSettingsStore(paths: context.paths)
        switch args.items.first {
        case "fields":
            _ = args.next()
            guard args.isEmpty else { throw CLIError(usage) }
            let hidden = store.load().hiddenContext
            for field in ContextField.allCases {
                print("\(field.rawValue)  \(hidden.contains(field) ? "hidden" : "shown")  \(field.title)")
            }
        case "hide", "show":
            let visible = args.next() == "show"
            guard let name = args.next(), args.isEmpty else { throw CLIError(usage) }
            guard let field = ContextField(rawValue: name) else { throw CLIError(ContextError.unknownField(name).description) }
            var settings = try store.loadValidated()
            settings.setContext(field, visible: visible)
            try store.save(settings)
            print("\(field.rawValue): \(visible ? "shown" : "hidden") to agents")
        default:
            let json = args.flag("--json")
            let hook = args.option("--hook")
            let only = args.option("--only")?.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard args.isEmpty else { throw CLIError(usage) }
            var snapshot = MacContextProbe.live(paths: context.paths, tools: context.tools, hidden: store.load().hiddenContext)
            if let only {
                do { snapshot = try snapshot.only(only) } catch { throw CLIError(String(describing: error)) }
            }
            // A start hook must never block a session: it prints the snapshot in the agent's format and exits 0.
            if let hook { return print(snapshot.hookOutput(for: hook)) }
            guard json else { return print(snapshot.render()) }
            // ISO dates for agents; printJSON keeps the app's reference-date format for other commands.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
        }
    }
}
