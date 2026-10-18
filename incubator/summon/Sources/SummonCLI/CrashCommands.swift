import Foundation
import SummonCore

enum CrashCommands {
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        let watcher = CrashWatcher(paths: context.paths)
        switch args.next() {
        case "list":
            let json = args.flag("--json")
            let limit = args.option("--limit").flatMap { Int($0) } ?? 20
            let reports = watcher.reports(since: nil, limit: limit)
            if json {
                try context.printJSON(reports)
            } else if reports.isEmpty {
                print("No crash, hang or panic reports (muted programs are skipped).")
            } else {
                for report in reports {
                    let when = report.timestamp ?? "unknown time"
                    let detail = [report.exceptionType, report.signal].compactMap { $0 }.joined(separator: " ")
                    print("\(when)  \(report.kind.rawValue.padding(toLength: 5, withPad: " ", startingAt: 0))  \(report.program)  \(detail)")
                    print("    \(report.file)")
                }
            }
        case "show":
            let json = args.flag("--json")
            guard let file = args.next() else { throw CLIError("Usage: summon crash show <file.ips> [--json]") }
            let report = try load(file)
            if json {
                try context.printJSON(report)
            } else {
                print(DiagnosePrompt.make(for: report, skillPath: skillPath(context)))
                if !report.topFrames.isEmpty {
                    print("\nTop frames of the crashed thread:")
                    for frame in report.topFrames { print("  \(frame)") }
                }
            }
        case "diagnose":
            let report: CrashReport
            if args.flag("--latest") {
                guard let latest = watcher.reports(since: nil, limit: 1).first else {
                    throw CLIError("No crash reports to diagnose.")
                }
                report = latest
            } else {
                guard let file = args.next() else { throw CLIError("Usage: summon crash diagnose <file.ips> | --latest") }
                report = try load(file)
            }
            let prompt = DiagnosePrompt.make(for: report, skillPath: skillPath(context))
            try await AgentCommands.launch(prompt: prompt, inline: false, checkpoint: true, context)
        case "mute":
            guard let program = args.next() else {
                let names = watcher.muted().sorted()
                print(names.isEmpty ? "Nothing is muted." : names.joined(separator: "\n"))
                return
            }
            let off = args.next() == "off"
            try watcher.setMuted(program, muted: !off)
            print(off ? "Crash notifications for \(CrashWatcher.muteKey(program)) are back on." : "Muted crash notifications for \(CrashWatcher.muteKey(program)).")
        default:
            throw CLIError("Usage: summon crash list|show|diagnose|mute")
        }
    }

    static func load(_ file: String) throws -> CrashReport {
        let path = (file as NSString).expandingTildeInPath
        guard let data = FileManager.default.contents(atPath: path) else { throw CLIError("Cannot read \(path)") }
        return try CrashReport.parse(String(decoding: data, as: UTF8.self), file: path)
    }

    /// The shipped copy, the one `summon skills link` points every agent at.
    static func skillPath(_ context: Context) -> String {
        SkillCommands.source.appendingPathComponent("diagnose-crash-mac/SKILL.md").path
    }
}
