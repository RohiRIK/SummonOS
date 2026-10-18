import Foundation
import SummonCore

enum DoctorCommand {
    /// `summon doctor [--json]`. Exits 1 when any check fails; warnings alone exit 0.
    static func run(_ args: inout Arguments, _ context: Context) async throws {
        let json = args.flag("--json")
        guard args.isEmpty else { throw CLIError("Usage: summon doctor [--json]") }
        let environment = ProcessInfo.processInfo.environment
        let shellPath = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = context.paths.home
        let doctor = Doctor(
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
        let report = await doctor.run()
        if json {
            struct Output: Encodable {
                let status: DoctorCheck.Status
                let checks: [DoctorCheck]
            }
            try context.printJSON(Output(status: report.status, checks: report.checks))
        } else {
            print(Doctor.render(report))
        }
        if report.status == .fail {
            throw CLIError("", code: .error)
        }
    }
}
