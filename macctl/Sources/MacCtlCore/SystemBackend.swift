import Foundation

/// Reads and writes settings with the built-in tools: `defaults` and `osascript`.
///
/// Values only ever travel as argv items. AppleScript text is the fixed script from the catalog;
/// the value goes after `--` so osascript never parses it as a flag or as code.
public struct SystemBackend: SettingBackend {
    private let runner: Runner

    public init(runner: @escaping Runner) {
        self.runner = runner
    }

    // MARK: SettingBackend

    public func read(_ setting: Setting) async throws -> Value? {
        switch setting.backend {
        case .defaults(let domain, let key, let type):
            let result = try await runner(Tool.defaults, ["read", Self.domainArgument(domain), key])
            if result.exitCode != 0 {
                if Self.isMissingKey(result) { return nil }
                throw Self.failure("defaults read \(domain) \(key)", result)
            }
            return try Self.parseDefaults(result.stdout, type: type, id: setting.id)

        case .appleScript(let getScript, _):
            let result = try await runner(Tool.osascript, ["-e", getScript])
            try Self.checkAppleScript(result, command: "osascript (\(setting.id) get)")
            return try Self.parseScriptOutput(result.stdout, type: setting.type, id: setting.id)
        }
    }

    public func write(_ value: Value, for setting: Setting) async throws {
        switch setting.backend {
        case .defaults(let domain, let key, let type):
            let (flag, text) = try Self.defaultsArgument(value, type: type, id: setting.id)
            if case .path = setting.type, case .string(let path) = value {
                try Self.createDirectory(path, id: setting.id)
            }
            let result = try await runner(Tool.defaults, ["write", Self.domainArgument(domain), key, flag, text])
            if result.exitCode != 0 {
                throw Self.failure("defaults write \(domain) \(key)", result)
            }

        case .appleScript(_, let setScript):
            // `--` ends osascript's own options: a value such as "-e" or "-rf" stays a value.
            let result = try await runner(Tool.osascript, ["-e", setScript, "--", value.description])
            try Self.checkAppleScript(result, command: "osascript (\(setting.id) set)")
        }
    }

    /// A path setting (screenshot folder) points at a folder that may not exist yet; create it so
    /// the write takes effect instead of failing silently.
    static func createDirectory(_ path: String, id: String) throws {
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        } catch {
            throw MacCtlError.invalidValue(id: id, value: path, reason: "cannot create folder: \(error.localizedDescription)")
        }
    }

    public func reset(_ setting: Setting) async throws {
        switch setting.backend {
        case .defaults(let domain, let key, _):
            let result = try await runner(Tool.defaults, ["delete", Self.domainArgument(domain), key])
            if result.exitCode != 0, !Self.isMissingKey(result) {
                throw Self.failure("defaults delete \(domain) \(key)", result)
            }

        case .appleScript:
            guard let systemDefault = setting.systemDefault else {
                throw MacCtlError.unsupported(
                    id: setting.id,
                    reason: "no known system default to restore for this AppleScript setting"
                )
            }
            try await write(systemDefault, for: setting)
        }
    }

    // MARK: defaults helpers

    static func domainArgument(_ domain: String) -> String {
        domain == Backend.globalDomain ? "-g" : domain
    }

    /// `defaults` reports an unset key ("... does not exist") or an unknown domain ("Domain ... not found").
    static func isMissingKey(_ result: CommandResult) -> Bool {
        let text = result.stderr + result.stdout
        return text.contains("does not exist") || text.contains("not found")
    }

    static func parseDefaults(_ output: String, type: DefaultsType, id: String) throws -> Value {
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .bool:
            if let bool = parseBool(text) { return .bool(bool) }
        case .int:
            if let int = Int(text) { return .int(int) }
            if let double = Double(text), double.rounded() == double, abs(double) < 1e15 {
                return .int(Int(double))
            }
        case .float:
            if let double = Double(text) { return .double(double) }
        case .string:
            return .string(text)
        }
        throw MacCtlError.invalidValue(id: id, value: text, reason: "unexpected `defaults read` output for a \(type.rawValue)")
    }

    /// The `defaults write` type flag and value text for a typed value.
    static func defaultsArgument(_ value: Value, type: DefaultsType, id: String) throws -> (String, String) {
        switch (type, value) {
        case (.bool, .bool(let b)):
            return ("-bool", b ? "TRUE" : "FALSE")
        case (.int, .int(let i)):
            return ("-int", String(i))
        case (.float, .double(let d)):
            return ("-float", String(d))
        case (.float, .int(let i)):
            return ("-float", String(Double(i)))
        case (.string, .string(let s)):
            return ("-string", s)
        default:
            throw MacCtlError.invalidValue(
                id: id, value: value.description,
                reason: "expected a \(type.rawValue) value for this setting"
            )
        }
    }

    // MARK: AppleScript helpers

    static func checkAppleScript(_ result: CommandResult, command: String) throws {
        guard result.exitCode != 0 else { return }
        let text = result.stderr + result.stdout
        if result.exitCode == -128 || text.contains("(-128)") || text.contains("User canceled") {
            throw MacCtlError.commandFailed(
                command: command, exitCode: result.exitCode,
                stderr: "cancelled by the user (-128); nothing was changed by this step"
            )
        }
        throw failure(command, result)
    }

    static func parseScriptOutput(_ output: String, type: ValueType, id: String) throws -> Value {
        // `do shell script` turns \n into \r; trim both.
        let text = output.trimmingCharacters(in: .whitespacesAndNewlines)
        switch type {
        case .bool:
            if let bool = parseBool(text) { return .bool(bool) }
        case .int:
            if let int = Int(text) { return .int(int) }
        case .double:
            if let double = Double(text) { return .double(double) }
        case .string, .enumeration, .path:
            return .string(text)
        }
        throw MacCtlError.invalidValue(id: id, value: text, reason: "unexpected AppleScript output")
    }

    // MARK: shared

    static func parseBool(_ text: String) -> Bool? {
        switch text.lowercased() {
        case "1", "true", "yes": true
        case "0", "false", "no": false
        default: nil
        }
    }

    static func failure(_ command: String, _ result: CommandResult) -> MacCtlError {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return .commandFailed(command: command, exitCode: result.exitCode, stderr: stderr.isEmpty ? stdout : stderr)
    }
}
