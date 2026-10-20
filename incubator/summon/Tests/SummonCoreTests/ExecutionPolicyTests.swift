import Foundation
import Testing
@testable import SummonCore

@Suite("Execution policy and private state")
struct ExecutionPolicyTests {
    @Test func newAndExistingInstallsKeepDistinctDefaults() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let store = ExecutionPolicyStore(paths: paths)
        #expect(try store.load() == .normal)
        // First agent selection freezes the new install's default before creating that preference.
        try store.migrate()
        try DefaultAgentStore(paths: paths).save(#require(AgentRegistry.find("claude")))
        #expect(try store.load() == .normal)
        try FileManager.default.removeItem(at: store.file)
        #expect(try store.load() == .unattended)
        try store.migrate()
        try FileManager.default.removeItem(at: paths.defaultAgentFile)
        #expect(try store.load() == .unattended)
        let before = try FileManager.default.attributesOfItem(atPath: store.file.path)[.systemFileNumber] as? NSNumber
        try store.migrate()
        #expect((try FileManager.default.attributesOfItem(atPath: store.file.path)[.systemFileNumber] as? NSNumber) == before)
        let mode = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }

    @Test func normalModeDoesNotFilterPromptOrModelData() throws {
        for agent in AgentRegistry.all {
            let argv = agent.argv(prompt: "--dangerously-skip-permissions", model: "--auto", execution: .normal)
            #expect(argv.last == "--dangerously-skip-permissions")
            if agent.modelFlag != nil { #expect(argv[2] == "--auto") }
            let interactive = agent.argv(prompt: nil, model: nil, execution: .normal)
            #expect(!interactive.contains("--dangerously-skip-permissions"))
            #expect(!interactive.contains("--dangerously-bypass-approvals-and-sandbox"))
            #expect(!interactive.contains("--permission-mode"))
            #expect(!interactive.contains("--allow-all"))
            #expect(agent.argv(prompt: "p", model: nil, execution: .unattended) == agent.argv(prompt: "p"))
            if let argv = agent.headless(prompt: "--auto", model: nil, execution: .normal) {
                #expect(argv.last == "--auto")
            }
        }
    }

    @Test func invalidPolicyAndAgentSettingsRemainRecoverable() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = SummonPaths(home: home)
        let policy = ExecutionPolicyStore(paths: paths)
        try writeFile("unknown", to: policy.file)
        #expect(throws: (any Error).self) { try policy.migrate() }
        #expect(try String(contentsOf: policy.file, encoding: .utf8) == "unknown")
        try writeFile("{broken", to: paths.agentSettingsFile)
        #expect(throws: (any Error).self) { try AgentSettingsStore(paths: paths).save(.init()) }
        #expect(try String(contentsOf: paths.agentSettingsFile, encoding: .utf8) == "{broken")
    }

    @Test func concurrentEventWritersKeepCompleteRecords() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let log = EventLog(paths: SummonPaths(home: home))
        try await withThrowingTaskGroup(of: Void.self) { group in
            for writer in 0..<12 {
                group.addTask {
                    for entry in 0..<10 { try log.append(.init(kind: "fixture", title: "\(writer)-\(entry)")) }
                }
            }
            try await group.waitForAll()
        }
        #expect(log.read().count == 120)
        #expect(Set(log.read().map(\.title)).count == 120)
    }
}
