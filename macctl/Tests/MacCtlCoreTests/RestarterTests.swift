import Foundation
import Testing
@testable import MacCtlCore

@Suite("KillallRestarter")
struct RestarterTests {
    @Test func killsEachProcessOnceSortedAndIgnoresLogout() async throws {
        let fake = RecordingRunner()
        let effects: Set<SideEffect> = [
            .restart(process: "SystemUIServer"),
            .restart(process: "Finder"),
            .restart(process: "Dock"),
            .logout,
        ]

        try await KillallRestarter(runner: fake.runner).run(effects)

        #expect(fake.calls == [
            RecordingRunner.Call(executable: Tool.killall, arguments: ["Dock"]),
            RecordingRunner.Call(executable: Tool.killall, arguments: ["Finder"]),
            RecordingRunner.Call(executable: Tool.killall, arguments: ["SystemUIServer"]),
        ])
    }

    @Test func logoutOnlyRunsNothing() async throws {
        let fake = RecordingRunner()
        try await KillallRestarter(runner: fake.runner).run([.logout])
        #expect(fake.calls.isEmpty)
    }

    @Test func processNotRunningIsFine() async throws {
        let fake = RecordingRunner(result: CommandResult(
            exitCode: 1, stdout: "", stderr: "No matching processes belonging to you were found\n"
        ))
        try await KillallRestarter(runner: fake.runner).run([.restart(process: "Dock")])
        #expect(fake.calls.count == 1)
    }

    @Test func otherFailureThrowsAfterTryingEveryProcess() async throws {
        let fake = RecordingRunner { _, arguments in
            arguments == ["Dock"]
                ? CommandResult(exitCode: 2, stdout: "", stderr: "killall: permission denied\n")
                : CommandResult(exitCode: 0, stdout: "")
        }
        do {
            try await KillallRestarter(runner: fake.runner).run([.restart(process: "Dock"), .restart(process: "Finder")])
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            #expect(error == .commandFailed(command: "killall Dock", exitCode: 2, stderr: "killall: permission denied"))
        }
        #expect(fake.calls.map(\.arguments) == [["Dock"], ["Finder"]])
    }
}
