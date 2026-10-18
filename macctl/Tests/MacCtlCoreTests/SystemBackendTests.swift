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

    static let missingKey = CommandResult(
        exitCode: 1, stdout: "",
        stderr: "\nThe domain/default pair of (com.apple.dock, autohide) does not exist\n"
    )

    // MARK: defaults read

    @Test func readsBoolFromOneOrZero() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "1\n"))
        let backend = SystemBackend(runner: fake.runner)

        let value = try await backend.read(Self.defaultsSetting())

        #expect(value == .bool(true))
        #expect(fake.calls == [RecordingRunner.Call(executable: Tool.defaults, arguments: ["read", "com.apple.dock", "autohide"])])
    }

    @Test func readsBoolFalse() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "0\n"))
        let value = try await SystemBackend(runner: fake.runner).read(Self.defaultsSetting())
        #expect(value == .bool(false))
    }

    @Test func missingKeyReadsAsNil() async throws {
        let fake = RecordingRunner(result: Self.missingKey)
        let value = try await SystemBackend(runner: fake.runner).read(Self.defaultsSetting())
        #expect(value == nil)
    }

    @Test func readsFloat() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "0.5\n"))
        let setting = Self.defaultsSetting(
            id: "dock.autohide-delay", type: .double(min: 0, max: 5),
            key: "autohide-delay", defaultsType: .float
        )
        let value = try await SystemBackend(runner: fake.runner).read(setting)
        #expect(value == .double(0.5))
    }

    @Test func readsInt() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "48\n"))
        let setting = Self.defaultsSetting(
            id: "dock.tile-size", type: .int(min: 16, max: 128), key: "tilesize", defaultsType: .int
        )
        let value = try await SystemBackend(runner: fake.runner).read(setting)
        #expect(value == .int(48))
    }

    @Test func readsStringTrimmed() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "  Nlsv \n"))
        let setting = Self.defaultsSetting(
            id: "finder.view-style", type: .enumeration(["Nlsv", "icnv"]),
            domain: "com.apple.finder", key: "FXPreferredViewStyle", defaultsType: .string
        )
        let value = try await SystemBackend(runner: fake.runner).read(setting)
        #expect(value == .string("Nlsv"))
    }

    @Test func globalDomainUsesDashG() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "2\n"))
        let setting = Self.defaultsSetting(
            id: "keyboard.key-repeat", type: .int(min: 1, max: 120),
            domain: Backend.globalDomain, key: "KeyRepeat", defaultsType: .int
        )
        _ = try await SystemBackend(runner: fake.runner).read(setting)
        #expect(fake.calls.first?.arguments == ["read", "-g", "KeyRepeat"])
    }

    @Test func otherReadFailureThrowsWithStderr() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 1, stdout: "", stderr: "boom\n"))
        do {
            _ = try await SystemBackend(runner: fake.runner).read(Self.defaultsSetting())
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            #expect(error == .commandFailed(command: "defaults read com.apple.dock autohide", exitCode: 1, stderr: "boom"))
        }
    }

    @Test func failureFallsBackToStdout() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 2, stdout: "reason on stdout\n", stderr: ""))
        do {
            try await SystemBackend(runner: fake.runner).write(.bool(true), for: Self.defaultsSetting())
            Issue.record("expected a throw")
        } catch let error as MacCtlError {
            #expect(error == .commandFailed(command: "defaults write com.apple.dock autohide", exitCode: 2, stderr: "reason on stdout"))
        }
    }

    @Test func unexpectedBoolOutputThrows() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 0, stdout: "maybe\n"))
        await #expect(throws: MacCtlError.self) {
            _ = try await SystemBackend(runner: fake.runner).read(Self.defaultsSetting())
        }
    }

    // MARK: defaults write

    @Test func writesBoolAsTRUEFALSE() async throws {
        let fake = RecordingRunner()
        let backend = SystemBackend(runner: fake.runner)

        try await backend.write(.bool(true), for: Self.defaultsSetting())
        try await backend.write(.bool(false), for: Self.defaultsSetting())

        #expect(fake.calls == [
            RecordingRunner.Call(executable: Tool.defaults, arguments: ["write", "com.apple.dock", "autohide", "-bool", "TRUE"]),
            RecordingRunner.Call(executable: Tool.defaults, arguments: ["write", "com.apple.dock", "autohide", "-bool", "FALSE"]),
        ])
    }

    @Test func writesIntFloatAndString() async throws {
        let fake = RecordingRunner()
        let backend = SystemBackend(runner: fake.runner)
        let size = Self.defaultsSetting(id: "dock.tile-size", type: .int(min: 16, max: 128), key: "tilesize", defaultsType: .int)
        let delay = Self.defaultsSetting(id: "dock.autohide-delay", type: .double(min: 0, max: 5), key: "autohide-delay", defaultsType: .float)
        let style = Self.defaultsSetting(
            id: "finder.view-style", type: .enumeration(["Nlsv", "icnv"]),
            domain: "com.apple.finder", key: "FXPreferredViewStyle", defaultsType: .string
        )

        try await backend.write(.int(48), for: size)
        try await backend.write(.double(0.5), for: delay)
        try await backend.write(.int(1), for: delay)
        try await backend.write(.string("Nlsv"), for: style)

        #expect(fake.calls.map(\.arguments) == [
            ["write", "com.apple.dock", "tilesize", "-int", "48"],
            ["write", "com.apple.dock", "autohide-delay", "-float", "0.5"],
            ["write", "com.apple.dock", "autohide-delay", "-float", "1.0"],
            ["write", "com.apple.finder", "FXPreferredViewStyle", "-string", "Nlsv"],
        ])
    }

    @Test func writeWithWrongValueTypeThrowsWithoutRunning() async throws {
        let fake = RecordingRunner()
        await #expect(throws: MacCtlError.self) {
            try await SystemBackend(runner: fake.runner).write(.string("yes"), for: Self.defaultsSetting())
        }
        #expect(fake.calls.isEmpty)
    }

    // MARK: defaults reset

    @Test func resetDeletesKey() async throws {
        let fake = RecordingRunner()
        try await SystemBackend(runner: fake.runner).reset(Self.defaultsSetting())
        #expect(fake.calls == [RecordingRunner.Call(executable: Tool.defaults, arguments: ["delete", "com.apple.dock", "autohide"])])
    }

    @Test func resetOfMissingKeyIsNotAnError() async throws {
        let fake = RecordingRunner(result: Self.missingKey)
        try await SystemBackend(runner: fake.runner).reset(Self.defaultsSetting())
        #expect(fake.calls.count == 1)
    }

    @Test func resetOtherFailureThrows() async throws {
        let fake = RecordingRunner(result: CommandResult(exitCode: 1, stdout: "", stderr: "Could not write domain"))
        await #expect(throws: MacCtlError.self) {
            try await SystemBackend(runner: fake.runner).reset(Self.defaultsSetting())
        }
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
