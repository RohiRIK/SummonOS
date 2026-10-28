import ArgumentParser
import Foundation
import MacCtlCore

@main
struct MacCtl: AsyncParsableCommand {
    /// Test seams are checked before any argument parsing, so `MACCTL_FAILPOINT=list` never reads
    /// or writes anything and a misspelled point fails loudly instead of silently passing.
    static func main() async {
        if Failpoint.listRequested {
            print(Failpoint.all.joined(separator: "\n"))
            Foundation.exit(0)
        }
        if let unknown = Failpoint.unknownRequestedPoint {
            FileHandle.standardError.write(Data("macctl: unknown MACCTL_FAILPOINT \(unknown); run with MACCTL_FAILPOINT=list\n".utf8))
            Foundation.exit(64)
        }
        if let unknown = Failpoint.unknownDiskFullSite {
            FileHandle.standardError.write(Data("macctl: unknown MACCTL_TEST_ENOSPC \(unknown); use header or intent\n".utf8))
            Foundation.exit(64)
        }
        await Self.main(nil)
    }

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "macctl",
            abstract: "Read, set, diff, apply and undo macOS settings. Built for AI agents.",
            discussion: """
            Output is JSON when --json is passed or stdout is not a terminal.
            Exit codes: 0 ok, 1 error, 2 needs permission, 3 needs confirmation (--yes), 4 unsupported.
            After an interrupted run, every write refuses with recovery_pending until `macctl recover`.
            """,
            version: "macctl 0.2.3",
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
                RecoverCommand.self,
                DiscoverCommand.self,
            ]
        )
    }
}
