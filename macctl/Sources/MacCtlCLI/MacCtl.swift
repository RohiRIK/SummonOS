import ArgumentParser
import Foundation
import MacCtlCore

@main
struct MacCtl: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "macctl",
            abstract: "Read, set, diff, apply and undo macOS settings. Built for AI agents.",
            discussion: """
            Output is JSON when --json is passed or stdout is not a terminal.
            Exit codes: 0 ok, 1 error, 2 needs permission, 3 needs confirmation (--yes), 4 unsupported.
            """,
            version: "0.1.0",
            subcommands: [
                DoctorCommand.self,
                ListCommand.self,
                DescribeCommand.self,
                GetCommand.self,
                SetCommand.self,
                DiffCommand.self,
                ApplyCommand.self,
                SnapshotCommand.self,
                UndoCommand.self,
            ]
        )
    }
}
