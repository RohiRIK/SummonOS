import Foundation

/// When a recurring task runs: every day or every weekday at a time, or every N hours.
public struct TaskSchedule: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        case daily, weekdays, interval
    }

    public enum ParseError: Error, Equatable, CustomStringConvertible {
        case missing
        case both
        case badTime(String)
        case badInterval(String)

        public var description: String {
            switch self {
            case .missing: return "Give a schedule: --at HH:MM [--weekdays] or --every <hours>h"
            case .both: return "Use --at or --every, not both"
            case .badTime(let text): return "Not a time: \(text) (use HH:MM, 24-hour)"
            case .badInterval(let text): return "Not an interval: \(text) (use 1h to 24h)"
            }
        }
    }

    public var kind: Kind
    public var hour = 9
    public var minute = 0
    public var everyHours = 1

    public init(kind: Kind, hour: Int = 9, minute: Int = 0, everyHours: Int = 1) {
        self.kind = kind
        self.hour = hour
        self.minute = minute
        self.everyHours = everyHours
    }

    /// `--at 9:00 [--weekdays]` or `--every 2h`.
    public static func parse(at: String?, weekdays: Bool, every: String?) throws -> TaskSchedule {
        switch (at, every) {
        case (nil, nil): throw ParseError.missing
        case (.some, .some): throw ParseError.both
        case (let at?, nil):
            let parts = at.split(separator: ":").map { Int($0) }
            guard parts.count == 2, let hour = parts[0], let minute = parts[1],
                  (0...23).contains(hour), (0...59).contains(minute) else { throw ParseError.badTime(at) }
            return TaskSchedule(kind: weekdays ? .weekdays : .daily, hour: hour, minute: minute)
        case (nil, let every?):
            let number = every.lowercased().hasSuffix("h") ? String(every.dropLast()) : every
            guard let hours = Int(number), (1...24).contains(hours) else { throw ParseError.badInterval(every) }
            return TaskSchedule(kind: .interval, everyHours: hours)
        }
    }

    public var summary: String {
        let time = String(format: "%02d:%02d", hour, minute)
        switch kind {
        case .daily: return "Every day at \(time)"
        case .weekdays: return "Weekdays at \(time)"
        case .interval: return everyHours == 1 ? "Every hour" : "Every \(everyHours) hours"
        }
    }
}

/// A prompt an agent runs on a schedule, unattended, with a checkpoint first.
public struct RecurringTask: Sendable, Equatable, Codable, Identifiable {
    public var id: String
    public var name: String
    public var prompt: String
    /// nil runs the default agent at run time.
    public var agent: String?
    public var schedule: TaskSchedule
    /// Fixed at creation for new tasks; absent in legacy tasks.
    public var execution: AgentExecutionMode? = nil
    public var directory: String? = nil

    public init(id: String, name: String, prompt: String, agent: String?, schedule: TaskSchedule) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.agent = agent
        self.schedule = schedule
    }
}

/// `~/.config/summon/tasks.json`.
public struct TaskStore: Sendable {
    public let paths: SummonPaths

    public init(paths: SummonPaths) {
        self.paths = paths
    }

    public func load() -> [RecurringTask] {
        (try? loadValidated()) ?? []
    }

    /// Use for execution/mutations: a damaged file must never become an empty task list.
    public func loadValidated() throws -> [RecurringTask] {
        let tasks = try StateFile.load([RecurringTask].self, at: paths.tasksFile, default: [])
        guard Set(tasks.map(\.id)).count == tasks.count,
              tasks.allSatisfy({ Self.isSafeID($0.id) && (0...23).contains($0.schedule.hour)
                  && (0...59).contains($0.schedule.minute) && (1...24).contains($0.schedule.everyHours) }) else {
            throw StateFileError.invalid(paths.tasksFile, "invalid task id or schedule")
        }
        return tasks
    }

    public static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 120 && id.allSatisfy { "abcdefghijklmnopqrstuvwxyz0123456789-".contains($0) }
    }

    public func update(_ transform: ([RecurringTask]) throws -> [RecurringTask]) throws {
        let lease = try FileLease.acquireSync(paths.state.appendingPathComponent("locks/tasks.lock"))
        defer { lease.hold() }
        try write(transform(loadValidated()))
    }

    public func save(_ tasks: [RecurringTask]) throws {
        try update { _ in tasks }
    }

    private func write(_ tasks: [RecurringTask]) throws {
        guard tasks.allSatisfy({ Self.isSafeID($0.id) }), Set(tasks.map(\.id)).count == tasks.count else {
            throw StateFileError.invalid(paths.tasksFile, "invalid or duplicate task id")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try TextFile.write(String(decoding: try encoder.encode(tasks), as: UTF8.self) + "\n", to: paths.tasksFile)
    }

    /// A slug of the name (a-z, 0-9, -), unique among saved tasks.
    public func newID(for name: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        let words = name.lowercased().split { !allowed.contains($0) }
        let base = words.isEmpty ? "task" : String(words.joined(separator: "-").prefix(100))
        let taken = Set(load().map(\.id))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base)-\(number)") { number += 1 }
        return "\(base)-\(number)"
    }
}

/// The LaunchAgent that runs one task: `~/Library/LaunchAgents/<label>.plist` calling `summon task run <id>`.
public enum TaskPlist {
    public static func label(_ id: String) -> String {
        "local.macplugins.summon.task.\(id)"
    }

    public static func file(_ id: String, home: URL) -> URL {
        home.appendingPathComponent("Library/LaunchAgents/\(label(id)).plist")
    }

    /// launchd has a bare PATH, so the agent CLIs need the user's PATH captured when the task is added.
    public static func data(for task: RecurringTask, summon: String, path: String, logDir: String) throws -> Data {
        var plist: [String: Any] = [
            "Label": label(task.id),
            "ProgramArguments": [summon, "task", "run", task.id],
            "EnvironmentVariables": ["PATH": path],
            "StandardOutPath": logDir + "/launchd.log",
            "StandardErrorPath": logDir + "/launchd.log",
            "ProcessType": "Background",
        ]
        let schedule = task.schedule
        switch schedule.kind {
        case .daily:
            plist["StartCalendarInterval"] = ["Hour": schedule.hour, "Minute": schedule.minute]
        case .weekdays:
            plist["StartCalendarInterval"] = (1...5).map { ["Weekday": $0, "Hour": schedule.hour, "Minute": schedule.minute] }
        case .interval:
            plist["StartInterval"] = schedule.everyHours * 3600
        }
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }
}

/// `summon task new`: the user describes what they want; the agent asks what is unclear, writes the run prompt and
/// creates the task. The run prompt is what matters: it runs later with nobody to ask.
public enum TaskSetup {
    public static func prompt(description: String?) -> String {
        let wish = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let opening = wish.isEmpty
            ? "I want a recurring task on this Mac. Ask me what should run and when."
            : "I want a recurring task on this Mac: \(wish)"
        return opening + """


            Set it up with the summon-mac skill's "Recurring tasks" section:
            1. Ask only what you cannot infer (when, which agent, what to report).
            2. Write the run prompt: it runs unattended later, with no chat and nobody to ask, so make it complete
               (what to check or do, where, what to leave alone, and a short summary of the result at the end).
            3. Create it: summon task add "<run prompt>" --at HH:MM [--weekdays] | --every <n>h [--agent <id>] --name "<short name>"
            4. Show me summon task list, and how to try it now: summon task run <id>
            """
    }
}
