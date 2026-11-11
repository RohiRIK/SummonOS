import Foundation
import Testing
@testable import SummonCore

@Suite("Ask Agent launch problems")
struct AgentLaunchProblemTests {
    @Test func refusedAppleEventSaysWhereToAllowIt() {
        let error = RunnerError.failed(path: "/usr/bin/osascript", status: 1,
                                       output: "execution error: Not authorized to send Apple events to Ghostty. (-1743)")
        let message = AgentLaunchProblem.explain(error, terminal: .ghostty)
        #expect(message.contains("Privacy & Security › Automation › Summon › Ghostty"))
        #expect(message.contains("tccutil reset AppleEvents local.macplugins.summon"))
    }

    @Test func timeoutPointsAtAWaitingDialog() {
        let error = RunnerError.timedOut(path: "/path/summon", seconds: 60, output: "")
        #expect(AgentLaunchProblem.explain(error, terminal: .terminal).contains("did not open in time"))
    }

    @Test func otherFailuresKeepTheCommandsOwnMessage() {
        let error = RunnerError.failed(path: "/path/summon", status: 1, output: "Claude Code is not installed.\n")
        #expect(AgentLaunchProblem.explain(error, terminal: .ghostty) == "Claude Code is not installed.")
    }

    @Test func kittyNeedsNoAutomation() {
        #expect(AgentLaunchProblem.automationTarget(.kitty) == nil)
        #expect(AgentLaunchProblem.automationTarget(.ghostty) == "com.mitchellh.ghostty")
    }
}
