import Foundation
import SummonCore

enum DoctorCommand {
    static func makeDoctor(_ context: Context) -> Doctor {
        let environment = ProcessInfo.processInfo.environment
        let shellPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = context.paths.home
        return Doctor(
            paths: context.paths,
            runner: context.runner,
            tools: context.tools,
            shellTools: ToolLocator(searchPath: shellPath, isExecutable: context.tools.isExecutable),
            share: URL(fileURLWithPath: PathCommand.installPath(environment: environment), isDirectory: true),
            appLocations: [
                home.appendingPathComponent("Applications/Summon.app", isDirectory: true),
                URL(fileURLWithPath: "/Applications/Summon.app", isDirectory: true),
            ],
            installedTerminals: TerminalApp.installed,
            isProcessRunning: { pid in pid > 0 && kill(pid, 0) == 0 }
        )
    }

    /// `summon doctor [--json] [--fix]`. Exits 1 when any check fails; warnings alone exit 0.
    @MainActor
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        if args.flag("--fix") {
            try await fix(&args, context)
            return
        }
        let json = args.flag("--json")
        guard args.isEmpty else { throw CLIError("Usage: summon doctor [--json] [--fix]") }
        let doctor = makeDoctor(context)
        let report = await doctor.run()
        if json {
            struct Output: Encodable {
                let version: String
                let status: DoctorCheck.Status
                let checks: [DoctorCheck]
            }
            try context.printJSON(Output(version: SummonVersion.current, status: report.status, checks: report.checks))
        } else {
            print(Doctor.render(report))
        }
        if report.status == .fail {
            throw CLIError("", code: .error)
        }
    }

    /// `summon fix [--inline]`: runs diagnostics, finds warnings, failures, or crashes, and delegates resolution to the default agent.
    @MainActor
    static func fix(_ args: inout Arguments, _ context: Context) async throws {
        let inline = args.flag("--inline")
        guard args.isEmpty else { throw CLIError("Usage: summon fix [--inline]") }

        let doctor = makeDoctor(context)
        let report = await doctor.run()
        let issues = report.issues

        let watcher = CrashWatcher(paths: context.paths)
        let crashes = watcher.reports(since: nil, limit: 3)

        if issues.isEmpty && crashes.isEmpty {
            print("✓ All checks passed! No issues found on this Mac.")
            return
        }

        var parts: [String] = []
        if !issues.isEmpty {
            parts.append("\(issues.count) diagnostic issue\(issues.count == 1 ? "" : "s")")
        }
        if !crashes.isEmpty {
            parts.append("\(crashes.count) recent crash report\(crashes.count == 1 ? "" : "s")")
        }
        print("Summon detected \(parts.joined(separator: " and ")). Launching default agent to fix...")

        let skill = SkillCommands.source.appendingPathComponent("summon-mac/SKILL.md").path
        let prompt = FixPrompt.make(for: issues, crashes: crashes, skillPath: skill)
        try await AgentCommands.launch(prompt: prompt, inline: inline, checkpoint: true, context)
    }
}
