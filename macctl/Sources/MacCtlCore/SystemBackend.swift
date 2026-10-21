import Foundation

/// Reads and writes settings: `.defaults` keys through CFPreferences (an injected `PreferencesStore`,
/// ADR D1), AppleScript settings through `osascript`, and the desktop picture through an injected
/// `WallpaperControlling` (`NSWorkspace` by default).
///
/// AppleScript text is the fixed script from the catalog; the value goes after `--` as an argv item
/// so osascript never parses it as a flag or as code.
public struct SystemBackend: SettingBackend {
    private let runner: Runner
    private let wallpaper: any WallpaperControlling
    private let preferences: PreferencesBackend

    public init(runner: @escaping Runner, preferences: any PreferencesStore = SystemBackend.livePreferences(),
                wallpaper: any WallpaperControlling = LiveWallpaper()) {
        self.runner = runner
        self.wallpaper = wallpaper
        self.preferences = PreferencesBackend(store: preferences)
    }

    /// CFPreferences on macOS; elsewhere every `.defaults` call fails as unsupported.
    public static func livePreferences() -> any PreferencesStore {
        #if canImport(Darwin)
        CFPreferencesStore()
        #else
        UnavailablePreferencesStore()
        #endif
    }

    public func priorState(_ setting: Setting) async throws -> PriorState {
        if case .defaults = setting.backend { return try preferences.prior(setting) }
        return try await PriorState.explicitOrAbsent(read(setting))
    }

    public func storedValue(_ setting: Setting) async throws -> TypedValue? {
        if case .defaults = setting.backend { return try preferences.stored(setting) }
        return try await read(setting).map(TypedValue.init)
    }

    public func writeExact(_ value: TypedValue, for setting: Setting) async throws {
        if case .defaults = setting.backend { return try preferences.writeExact(value, for: setting) }
        try await write(value.value, for: setting)
    }

    // MARK: SettingBackend

    public func wallpapers(for setting: Setting) async throws -> [DisplayWallpaper]? {
        guard case .wallpaper = setting.backend else { return nil }
        return try await wallpaper.wallpapers()
    }

    public func restoreWallpapers(_ wallpapers: [DisplayWallpaper], for setting: Setting) async throws {
        guard case .wallpaper = setting.backend else {
            throw MacCtlError.unsupported(id: setting.id, reason: "not a wallpaper setting")
        }
        for saved in wallpapers { try validate(.string(saved.path), for: setting) }
        try await wallpaper.restoreWallpapers(wallpapers)
    }

    public func read(_ setting: Setting) async throws -> Value? {
        switch setting.backend {
        case .defaults:
            return try preferences.read(setting)

        case .appleScript(let getScript, _):
            let result = try await runner(Tool.osascript, ["-e", getScript])
            try Self.checkAppleScript(result, command: "osascript (\(setting.id) get)")
            return try Self.parseScriptOutput(result.stdout, type: setting.type, id: setting.id)

        case .wallpaper:
            return try await wallpaper.currentWallpaper().map(Value.string)
        }
    }

    public func write(_ value: Value, for setting: Setting) async throws {
        switch setting.backend {
        case .defaults(_, _, let type):
            let typed = try PreferencesBackend.typed(value, type: type, id: setting.id)
            if case .path = setting.type, case .string(let path) = value {
                try Self.createDirectory(path, id: setting.id)
            }
            try preferences.writeExact(typed, for: setting)

        case .appleScript(_, let setScript):
            // `--` ends osascript's own options: a value such as "-e" or "-rf" stays a value.
            let result = try await runner(Tool.osascript, ["-e", setScript, "--", value.description])
            try Self.checkAppleScript(result, command: "osascript (\(setting.id) set)")

        case .wallpaper:
            try validate(value, for: setting)
            guard case .string(let path) = value else { return }
            try await wallpaper.setWallpaper(ValueType.expandTilde(path))
        }
    }

    /// A wallpaper must be an existing file (not a folder); other settings need no live check.
    public func validate(_ value: Value, for setting: Setting) throws {
        guard case .wallpaper = setting.backend else { return }
        guard case .string(let raw) = value else {
            throw MacCtlError.invalidValue(id: setting.id, value: value.description, reason: "expected a file path")
        }
        let path = ValueType.expandTilde(raw)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            throw MacCtlError.invalidValue(id: setting.id, value: raw, reason: "no such file")
        }
        if isDirectory.boolValue {
            throw MacCtlError.invalidValue(id: setting.id, value: raw, reason: "is a folder; expected an image file")
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
        case .defaults:
            try preferences.delete(setting)

        case .appleScript, .wallpaper:
            guard let systemDefault = setting.systemDefault else {
                throw MacCtlError.unsupported(
                    id: setting.id,
                    reason: "no known system default to restore for this setting"
                )
            }
            try await write(systemDefault, for: setting)
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

/// The `.defaults` backend over a `PreferencesStore`: one exact `(appID, current user, host)` triple
/// per setting, typed values, explicit synchronize. Never edits plist files and never shells out.
struct PreferencesBackend: Sendable {
    let store: any PreferencesStore

    private struct Target {
        let appID: String
        let key: String
        let type: DefaultsType
        let host: PreferenceHost
    }

    private func target(_ setting: Setting) throws -> Target {
        guard case .defaults(let domain, let key, let type) = setting.backend else {
            throw MacCtlError.unsupported(id: setting.id, reason: "not a preferences setting")
        }
        return Target(appID: domain, key: key, type: type, host: setting.scope)
    }

    /// ADR D1 steps 0-3: refuse managed keys, then explicit (exact triple), inherited (layered), absent.
    func prior(_ setting: Setting) throws -> PriorState {
        let t = try target(setting)
        if try store.isForced(t.key, appID: t.appID) { throw MacCtlError.managedSetting(id: setting.id) }
        var shadow: PreferenceHost? = nil
        if t.host == .anyHost, try store.copyValue(t.key, appID: t.appID, host: .currentHost) != nil {
            shadow = .currentHost
        }
        if let exact = try store.copyValue(t.key, appID: t.appID, host: t.host) {
            return PriorState(state: .explicit, value: exact, host: t.host, shadowedBy: shadow)
        }
        if let inherited = try store.copyAppValue(t.key, appID: t.appID) {
            return PriorState(state: .inherited, value: inherited, host: t.host,
                              layer: try store.inheritedLayer(t.key, appID: t.appID, host: t.host), shadowedBy: shadow)
        }
        return PriorState(state: .absent, host: t.host, shadowedBy: shadow)
    }

    func stored(_ setting: Setting) throws -> TypedValue? {
        let t = try target(setting)
        return try store.copyValue(t.key, appID: t.appID, host: t.host)
    }

    /// The stored value as the catalog type; nil when unset. A value of another type that cannot be
    /// read as the catalog type is an error, as with `defaults read` before.
    func read(_ setting: Setting) throws -> Value? {
        let t = try target(setting)
        guard let typed = try stored(setting) else { return nil }
        guard let value = typed.catalogValue(t.type) else {
            throw MacCtlError.invalidValue(id: setting.id, value: typed.value.description,
                                           reason: "stored as \(typed.type.rawValue), expected a \(t.type.rawValue)")
        }
        return value
    }

    /// Writes the exact CF type, synchronizes, and verifies with an exact-triple read-back.
    func writeExact(_ value: TypedValue, for setting: Setting) throws {
        let t = try target(setting)
        try store.setValue(value, key: t.key, appID: t.appID, host: t.host)
        if let points = Failpoint.writePoints { Failpoint.hit(points.0) }
        try store.synchronize(appID: t.appID, host: t.host)
        if let points = Failpoint.writePoints { Failpoint.hit(points.1) }
    }

    /// Deletes only this triple's explicit key, so inheritance resumes (restore of absent/inherited).
    func delete(_ setting: Setting) throws {
        let t = try target(setting)
        try store.setValue(nil, key: t.key, appID: t.appID, host: t.host)
        if let points = Failpoint.writePoints { Failpoint.hit(points.0) }
        try store.synchronize(appID: t.appID, host: t.host)
        if let points = Failpoint.writePoints { Failpoint.hit(points.1) }
    }

    /// The typed value a catalog write stores (`-bool` → CFBoolean, `-int` → SInt64, `-float` → real).
    static func typed(_ value: Value, type: DefaultsType, id: String) throws -> TypedValue {
        switch (type, value) {
        case (.bool, .bool), (.int, .int), (.float, .double), (.float, .int), (.string, .string):
            return TypedValue(writing: value, as: type)
        default:
            throw MacCtlError.invalidValue(id: id, value: value.description,
                                           reason: "expected a \(type.rawValue) value for this setting")
        }
    }
}
