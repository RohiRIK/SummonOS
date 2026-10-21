import Foundation
import Testing
@testable import MacCtlCore

@Suite("SystemBackend")
struct SystemBackendTests {
    // MARK: fixtures

    static func defaultsSetting(
        id: String = "dock.autohide",
        type: ValueType = .bool,
        domain: String = "com.apple.dock",
        key: String = "autohide",
        defaultsType: DefaultsType = .bool
    ) -> Setting {
        Setting(
            id: id, summary: "test setting", type: type,
            backend: .defaults(domain: domain, key: key, type: defaultsType)
        )
    }

    static let getScript = "tell application \"System Events\" to get dark mode of appearance preferences"
    static let setScript = """
        on run argv
            tell application "System Events" to set dark mode of appearance preferences to ((item 1 of argv) is "true")
        end run
        """

    static func scriptSetting(type: ValueType = .bool, systemDefault: Value? = nil) -> Setting {
        Setting(
            id: "appearance.dark-mode", summary: "test setting", type: type,
            permissions: [.automation(bundleID: "com.apple.systemevents")],
            backend: .appleScript(get: getScript, set: setScript),
            systemDefault: systemDefault
        )
    }

    /// A backend whose `.defaults` keys live in memory; the runner must never be called for them.
    static func preferencesBackend() -> (SystemBackend, MemoryPreferencesStore, RecordingRunner) {
        let prefs = MemoryPreferencesStore()
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: ""))
        return (SystemBackend(runner: fake.runner, preferences: prefs), prefs, fake)
    }

    // MARK: defaults (CFPreferences)

    @Test func readsBoolFromExactTripleWithoutRunningTools() async throws {
        let (backend, prefs, fake) = Self.preferencesBackend()
        prefs.seed("autohide", TypedValue(type: .bool, value: .bool(true)), appID: "com.apple.dock")
        #expect(try await backend.read(Self.defaultsSetting()) == .bool(true))
        #expect(fake.calls.isEmpty)
    }

    @Test func intStoredUnderBoolSettingReadsAsBool() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        prefs.seed("autohide", TypedValue(type: .int, value: .int(0)), appID: "com.apple.dock")
        #expect(try await backend.read(Self.defaultsSetting()) == .bool(false))
    }

    @Test func realStoredUnderIntSettingReadsAsInt() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        let setting = Self.defaultsSetting(id: "dock.tilesize", type: .int(min: 16, max: 128), key: "tilesize", defaultsType: .int)
        prefs.seed("tilesize", TypedValue(type: .float, value: .double(64)), appID: "com.apple.dock")
        #expect(try await backend.read(setting) == .int(64))
        // The exact prior keeps the real type (QA R-a).
        #expect(try await backend.priorState(setting).value == TypedValue(type: .float, value: .double(64)))
    }

    @Test func missingKeyReadsAsNilAndAbsent() async throws {
        let (backend, _, _) = Self.preferencesBackend()
        #expect(try await backend.read(Self.defaultsSetting()) == nil)
        #expect(try await backend.priorState(Self.defaultsSetting()).state == .absent)
    }

    @Test func unreadableStoredTypeThrows() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        prefs.seed("autohide", TypedValue(type: .string, value: .string("maybe")), appID: "com.apple.dock")
        await #expect(throws: MacCtlError.self) { try await backend.read(Self.defaultsSetting()) }
    }

    @Test func globalDomainValueIsInheritedNotExplicit() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        prefs.seed("autohide", TypedValue(type: .bool, value: .bool(true)), appID: Backend.globalDomain)
        let prior = try await backend.priorState(Self.defaultsSetting())
        #expect(prior.state == .inherited)
        #expect(prior.layer == "global")
        #expect(try await backend.read(Self.defaultsSetting()) == nil)
    }

    @Test func forcedKeyIsRefused() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        prefs.force("autohide", TypedValue(type: .bool, value: .bool(true)), appID: "com.apple.dock")
        await #expect(throws: MacCtlError.managedSetting(id: "dock.autohide")) {
            try await backend.priorState(Self.defaultsSetting())
        }
    }

    @Test func currentHostValueShadowsAnyHostTarget() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        prefs.seed("autohide", TypedValue(type: .bool, value: .bool(false)), appID: "com.apple.dock", host: .currentHost)
        let prior = try await backend.priorState(Self.defaultsSetting())
        #expect(prior.shadowedBy == .currentHost)
        #expect(prior.state == .inherited)
        #expect(prior.layer == "otherHost")
    }

    @Test func writesExactCFTypes() async throws {
        let (backend, prefs, fake) = Self.preferencesBackend()
        let size = Self.defaultsSetting(id: "dock.tile-size", type: .int(min: 16, max: 128), key: "tilesize", defaultsType: .int)
        let delay = Self.defaultsSetting(id: "dock.autohide-delay", type: .double(min: 0, max: 5), key: "autohide-delay", defaultsType: .float)
        try await backend.write(.bool(true), for: Self.defaultsSetting())
        try await backend.write(.int(40), for: size)
        try await backend.write(.int(1), for: delay)
        #expect(try prefs.copyValue("autohide", appID: "com.apple.dock", host: .anyHost) == TypedValue(type: .bool, value: .bool(true)))
        #expect(try prefs.copyValue("tilesize", appID: "com.apple.dock", host: .anyHost) == TypedValue(type: .int, value: .int(40)))
        #expect(try prefs.copyValue("autohide-delay", appID: "com.apple.dock", host: .anyHost) == TypedValue(type: .float, value: .double(1)))
        #expect(prefs.syncs == 3)
        #expect(fake.calls.isEmpty)
    }

    @Test func writeWithWrongValueTypeThrowsWithoutWriting() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        await #expect(throws: MacCtlError.self) { try await backend.write(.string("yes"), for: Self.defaultsSetting()) }
        #expect(prefs.writes == 0)
    }

    @Test func resetDeletesOnlyTheExactTriple() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        prefs.seed("autohide", TypedValue(type: .bool, value: .bool(true)), appID: "com.apple.dock")
        prefs.seed("autohide", TypedValue(type: .bool, value: .bool(false)), appID: "com.apple.dock", host: .currentHost)
        try await backend.reset(Self.defaultsSetting())
        #expect(try prefs.copyValue("autohide", appID: "com.apple.dock", host: .anyHost) == nil)
        #expect(try prefs.copyValue("autohide", appID: "com.apple.dock", host: .currentHost) != nil)
    }

    @Test func writeExactRestoresOriginalType() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        try await backend.writeExact(TypedValue(type: .int, value: .int(1)), for: Self.defaultsSetting())
        #expect(try prefs.copyValue("autohide", appID: "com.apple.dock", host: .anyHost) == TypedValue(type: .int, value: .int(1)))
    }

    @Test func currentHostScopeWritesCurrentHost() async throws {
        let (backend, prefs, _) = Self.preferencesBackend()
        let setting = Setting(id: "t.host", summary: "", type: .bool,
                              backend: .defaults(domain: "com.apple.dock", key: "k", type: .bool), scope: .currentHost)
        try await backend.write(.bool(true), for: setting)
        #expect(try prefs.copyValue("k", appID: "com.apple.dock", host: .currentHost) != nil)
        #expect(try prefs.copyValue("k", appID: "com.apple.dock", host: .anyHost) == nil)
    }

    // MARK: AppleScript

    @Test func appleScriptReadMapsBoolAndTrimsCarriageReturns() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "true\r\n"))
        let value = try await SystemBackend(runner: fake.runner).read(Self.scriptSetting())
        #expect(value == .bool(true))
        #expect(fake.calls == [RecordingRunner.Call(executable: Tool.osascript, arguments: ["-e", Self.getScript])])
    }

    @Test func appleScriptReadMapsOtherTypes() async throws {
        let intFake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "42\n"))
        let int = try await SystemBackend(runner: intFake.runner).read(Self.scriptSetting(type: .int(min: nil, max: nil)))
        #expect(int == .int(42))

        let stringFake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "Graphite\r"))
        let string = try await SystemBackend(runner: stringFake.runner).read(Self.scriptSetting(type: .string))
        #expect(string == .string("Graphite"))
    }

    @Test func appleScriptWritePassesValueAfterDoubleDash() async throws {
        let fake = RecordingRunner()
        try await SystemBackend(runner: fake.runner).write(.bool(false), for: Self.scriptSetting())
        #expect(fake.calls == [RecordingRunner.Call(executable: Tool.osascript, arguments: ["-e", Self.setScript, "--", "false"])])
    }

    @Test(arguments: [
        "\"; do shell script \"rm -rf ~\"",
        "-e",
        "-rf ~ \" & (do shell script \"id\") & \"",
    ])
    func injectionStaysOneArgvItemAfterDoubleDash(_ evil: String) async throws {
        let fake = RecordingRunner()
        let setting = Self.scriptSetting(type: .string)

        try await SystemBackend(runner: fake.runner).write(.string(evil), for: setting)

        let call = try #require(fake.calls.first)
        #expect(fake.calls.count == 1)
        #expect(call.executable == Tool.osascript)
        #expect(call.arguments == ["-e", Self.setScript, "--", evil])
        // The script text is the fixed catalog text, untouched by the value.
        #expect(call.arguments[1] == Self.setScript)
        #expect(!call.arguments[1].contains(evil))
    }

    @Test func userCancelIsAClearError() async throws {
        let fake = RecordingRunner(result: CommandResult(
            exitCode: 1, stdout: "", stderr: "0:42: execution error: User canceled. (-128)\n"
        ))
        do {
            try await SystemBackend(runner: fake.runner).write(.bool(true), for: Self.scriptSetting())
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            guard case .commandFailed(let command, _, let stderr) = error else {
                Issue.record("expected commandFailed, got \(error)")
                return
            }
            #expect(command.contains("appearance.dark-mode"))
            #expect(stderr.contains("cancelled by the user"))
        }
    }

    @Test func appleScriptFailureCarriesStderr() async throws {
        let fake = RecordingRunner(result: CommandResult(
            exitCode: 1, stdout: "", stderr: "execution error: Not authorized to send Apple events to System Events. (-1743)\n"
        ))
        do {
            _ = try await SystemBackend(runner: fake.runner).read(Self.scriptSetting())
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            guard case .commandFailed(_, let code, let stderr) = error else {
                Issue.record("expected commandFailed, got \(error)")
                return
            }
            #expect(code == 1)
            #expect(stderr.contains("-1743"))
        }
    }

    @Test func appleScriptResetWritesSystemDefault() async throws {
        let fake = RecordingRunner()
        try await SystemBackend(runner: fake.runner).reset(Self.scriptSetting(systemDefault: .bool(false)))
        #expect(fake.calls.map(\.arguments) == [["-e", Self.setScript, "--", "false"]])
    }

    @Test func appleScriptResetWithoutDefaultIsUnsupported() async throws {
        let fake = RecordingRunner()
        do {
            try await SystemBackend(runner: fake.runner).reset(Self.scriptSetting())
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            #expect(error.code == "unsupported")
        }
        #expect(fake.calls.isEmpty)
    }

    // MARK: permission probe (pure parts only)

    @Test func automationStatusMapping() {
        #expect(SystemPermissionProbe.automationCheck(status: 0, bundleID: "com.apple.systemevents").granted)
        let notRunning = SystemPermissionProbe.automationCheck(status: -600, bundleID: "com.apple.systemevents")
        // Not running or not asked yet must not block: the first Apple Event shows the prompt.
        #expect(notRunning.granted)
        #expect(notRunning.detail.contains("not running"))
        #expect(SystemPermissionProbe.automationCheck(status: -1744, bundleID: "x").granted)
        #expect(!SystemPermissionProbe.automationCheck(status: -1743, bundleID: "x").granted)
    }

    @Test func settingsURLs() {
        let probe = SystemPermissionProbe()
        #expect(probe.settingsURL(for: .accessibility) == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        #expect(probe.settingsURL(for: .fullDiskAccess) == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        #expect(probe.settingsURL(for: .automation(bundleID: "com.apple.systemevents")) == "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
    }
}
