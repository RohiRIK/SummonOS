import Foundation

/// Normal uses the chosen harness's own controls; it does not promise a sandbox every harness lacks.
public enum AgentExecutionMode: String, Sendable, Codable, CaseIterable {
    case normal
    case unattended

    public var title: String { self == .normal ? "Agent controls" : "Unattended" }
}

public struct ExecutionPolicyStore: Sendable {
    public let paths: SummonPaths
    public init(paths: SummonPaths) { self.paths = paths }
    public var file: URL { paths.config.appendingPathComponent("defaults/execution") }

    /// Existing installations retain the explicitly configured default agent's previous behavior.
    /// New installations use the harness's normal controls until unattended mode is selected.
    public func load() throws -> AgentExecutionMode {
        do {
            let value = try String(contentsOf: file, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let mode = AgentExecutionMode(rawValue: value) else { throw StateFileError.invalid(file, "unknown execution mode") }
            return mode
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return FileManager.default.fileExists(atPath: paths.defaultAgentFile.path) ? .unattended : .normal
        }
    }

    public func save(_ mode: AgentExecutionMode) throws {
        let lease = try FileLease.acquireSync(paths.state.appendingPathComponent("locks/execution.lock"))
        defer { lease.hold() }
        try TextFile.write(mode.rawValue + "\n", to: file)
    }

    /// Freeze inferred legacy intent before changing other defaults (e.g. first agent selection).
    @discardableResult public func migrate() throws -> AgentExecutionMode {
        let lease = try FileLease.acquireSync(paths.state.appendingPathComponent("locks/execution.lock"))
        defer { lease.hold() }
        let mode = try load()
        if !FileManager.default.fileExists(atPath: file.path) { try TextFile.write(mode.rawValue + "\n", to: file) }
        return mode
    }
}

extension Agent {
    public func argv(prompt: String?, model: String?, execution: AgentExecutionMode) -> [String] {
        guard execution == .normal else { return argv(prompt: prompt, model: model) }
        let base: [String]
        if let prompt, !prompt.isEmpty { base = normalControls(withPrompt) + [prompt] }
        else { base = normalControls(interactive) }
        return withModel(model, arguments: base)
    }

    public func headless(prompt: String, model: String?, execution: AgentExecutionMode) -> [String]? {
        guard execution == .normal else { return headless(prompt: prompt, model: model) }
        guard let headlessPrefix else { return nil }
        return withModel(model, arguments: normalControls(headlessPrefix) + [prompt])
    }

    private func withModel(_ model: String?, arguments: [String]) -> [String] {
        guard let modelFlag, let model = model?.trimmingCharacters(in: .whitespaces), !model.isEmpty else { return arguments }
        return [arguments[0], modelFlag, model] + arguments.dropFirst()
    }

    private func normalControls(_ prefix: [String]) -> [String] {
        // Filter only registry-owned prefixes, before model/request data is appended.
        let bypass = Set(["--dangerously-skip-permissions", "--dangerously-bypass-approvals-and-sandbox",
                          "--auto", "--allow-all", "--yolo", "--trust"])
        var result: [String] = []
        var index = 0
        while index < prefix.count {
            if prefix[index] == "--permission-mode" { index += 2; continue }
            if !bypass.contains(prefix[index]) { result.append(prefix[index]) }
            index += 1
        }
        return result
    }
}
