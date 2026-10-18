import Foundation
import SummonCore

enum ActivityCommands {
    /// `summon events [--json] [--limit N] [--kind settings|agent|checkpoint|theme|problem]`.
    static func events(_ args: inout Arguments, _ context: Context) throws {
        let json = args.flag("--json")
        let limitText = args.option("--limit")
        let kindText = args.option("--kind")
        guard args.isEmpty else { throw CLIError("Usage: summon events [--json] [--limit N] [--kind settings|agent|checkpoint|theme|problem]") }
        let limit = try limitText.map { text -> Int in
            guard let value = Int(text), value > 0 else { throw CLIError("--limit takes a positive number") }
            return value
        } ?? 20
        let category = try kindText.map { text -> ActivityEvent.Category in
            guard let value = ActivityEvent.Category(rawValue: text) else {
                throw CLIError("Unknown kind \(text). Kinds: " + ActivityEvent.Category.allCases.map(\.rawValue).joined(separator: ", "))
            }
            return value
        }

        var events = ActivitySources.load(paths: context.paths).events
        if let category {
            events = events.filter { $0.category == category }
        }
        events = Array(events.prefix(limit))
        if json {
            try printJSON(events)
            return
        }
        if events.isEmpty {
            print("No activity yet.")
            return
        }
        for event in events {
            let time = event.date.formatted(date: .abbreviated, time: .shortened)
            let tag = event.category.rawValue.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("\(time)  \(tag) \(event.title)")
            if let detail = event.detail { print("    \(detail)") }
        }
    }

    /// `summon status [--json]`.
    static func status(_ args: inout Arguments, _ context: Context) async throws {
        let json = args.flag("--json")
        guard args.isEmpty else { throw CLIError("Usage: summon status [--json]") }
        let sources = ActivitySources.load(paths: context.paths)
        let agent = DefaultAgentStore(paths: context.paths).load()
        var problems: [String] = []
        if let macctl = context.macctl {
            do {
                problems = StatusProbe.doctorProblems(fromJSON: try await context.runner(macctl, ["doctor", "--json"]))
            } catch {
                problems = ["doctor failed: \(error)"]
            }
        }
        let status = StatusProbe.build(
            agent: agent,
            agentInstalled: agent.map { context.tools.find($0.command) != nil } ?? false,
            log: sources.log,
            macctlInstalled: context.macctl != nil,
            macctlProblems: problems,
            snapshots: sources.snapshots,
            checkpoints: sources.checkpoints,
            configIsRepo: sources.configIsRepo,
            crashes: sources.crashes,
            crashDates: sources.crashDates
        )
        if json {
            try printJSON(status)
            return
        }
        print(render(status))
    }

    static func render(_ status: SummonStatus) -> String {
        var lines: [String] = []
        let agentName = status.agent.name ?? "none chosen"
        if status.agent.running, let since = status.agent.since {
            let folder = status.agent.folder.map { " in \($0)" } ?? ""
            lines.append("Agent:       \(agentName), running since \(since.formatted(date: .omitted, time: .shortened))\(folder)")
        } else {
            lines.append("Agent:       \(agentName)\(status.agent.installed ? ", idle" : "")")
        }
        lines.append("macctl:      " + (status.macctl.installed ? (status.macctl.problems.isEmpty ? "ok" : "needs attention") : "not installed"))
        if let change = status.lastChange {
            lines.append("Last change: \(change.title) (\(change.date.formatted(.relative(presentation: .named))), snapshot \(change.refs["snapshot"] ?? "?"))")
        } else {
            lines.append("Last change: none")
        }
        if let checkpoint = status.lastCheckpoint {
            lines.append("Checkpoint:  \(checkpoint.id) \"\(checkpoint.label)\"")
        } else {
            lines.append("Checkpoint:  none yet")
        }
        lines.append("Problems:    \(status.recentProblems) in the last day")
        if !status.warnings.isEmpty {
            lines.append("")
            lines.append(contentsOf: status.warnings.map { "! " + $0 })
        }
        return lines.joined(separator: "\n")
    }

    /// `summon event add <kind> <title...> [--detail text] [--ref key=value]...`, for hooks and scripts.
    static func eventAdd(_ args: inout Arguments, _ context: Context) throws {
        let usage = "Usage: summon event add <kind> <title...> [--detail text] [--ref key=value]..."
        guard args.next() == "add" else { throw CLIError(usage) }
        let detail = args.option("--detail")
        var refs: [String: String] = [:]
        while let ref = args.option("--ref") {
            guard let equals = ref.firstIndex(of: "="), equals != ref.startIndex else { throw CLIError("--ref takes key=value") }
            refs[String(ref[..<equals])] = String(ref[ref.index(after: equals)...])
        }
        guard let kind = args.next(), !args.isEmpty else { throw CLIError(usage) }
        let title = args.items.joined(separator: " ")
        try EventLog(paths: context.paths).append(LoggedEvent(kind: kind, title: title, detail: detail, refs: refs))
    }

    /// Records an event, never failing the command that did the work.
    static func record(_ event: LoggedEvent, _ context: Context) {
        do {
            try EventLog(paths: context.paths).append(event)
        } catch {
            context.warn("summon: could not record activity: \(error)")
        }
    }

    /// ISO 8601 dates, unlike `Context.printJSON`, so agents can parse them.
    static func printJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        print(String(decoding: try encoder.encode(value), as: UTF8.self))
    }
}
