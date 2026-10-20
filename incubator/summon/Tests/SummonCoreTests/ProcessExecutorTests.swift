import Darwin
import Foundation
import Testing
@testable import SummonCore

@Suite("Bounded child process execution")
struct ProcessExecutorTests {
    @Test func passesArgumentsAsDataAndCapturesBothStreams() async throws {
        let payload = "$(touch never-created); `echo surprise` \"quoted\" \\ value"
        let result = try await ProcessExecutor.run("/bin/sh", ["-c", "printf '%s' \"$1\"; printf ':stderr' >&2", "fixture", payload])
        #expect(result.status == 0)
        #expect(result.output == payload + ":stderr")
        #expect(!result.truncated)
    }

    @Test func appliesWorkingDirectoryEnvironmentAndNullInput() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var options = ProcessOptions()
        options.directory = home
        options.environment = ["SUMMON_FIXTURE": "literal value"]
        options.includeStandardError = false
        let script = "if read value; then exit 9; fi; test \"$PWD\" -ef \"$1\" || exit 8; printf '%s' \"$SUMMON_FIXTURE\"; printf 'ignored' >&2"
        let result = try await ProcessExecutor.run("/bin/sh", ["-c", script, "fixture", home.path], options: options)
        #expect(result.status == 0)
        #expect(result.output == "literal value")
    }

    @Test func capsRetainedOutputWithoutBlockingNoisyChildren() async throws {
        var options = ProcessOptions()
        options.maxOutputBytes = 2_048
        let result = try await ProcessExecutor.run("/usr/bin/head", ["-c", "2097152", "/dev/zero"], options: options)
        #expect(result.status == 0)
        #expect(result.truncated)
        #expect(result.output.utf8.count == 2_048)
    }

    @Test func checkedRunnerRejectsFailedAndIncompleteOutput() throws {
        #expect(throws: RunnerError.failed(path: "/bin/sh", status: 7, output: "failed")) {
            try Shell.runSync("/bin/sh", ["-c", "printf failed; exit 7"])
        }
        var options = ProcessOptions()
        options.maxOutputBytes = 3
        #expect(throws: RunnerError.outputLimit(path: "/usr/bin/printf", limit: 3)) {
            try Shell.runSync("/usr/bin/printf", ["1234"], options: options)
        }
    }

    @Test func deadlineKillsTermIgnoringParentAndItsChild() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let childFile = home.appendingPathComponent("child-pid")
        var options = ProcessOptions()
        options.timeout = 0.2
        options.terminationGrace = 0.05
        let began = ContinuousClock.now
        await #expect(throws: RunnerError.self) {
            try await ProcessExecutor.run("/bin/sh", ["-c", "trap '' TERM; /bin/sleep 30 & printf '%s' \"$!\" > \"$1\"; wait", "fixture", childFile.path], options: options)
        }
        #expect(began.duration(to: .now) < .seconds(5))
        try assertChildStopped(childFile)
    }

    @Test func cancellationStopsRunningProcessGroup() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let childFile = home.appendingPathComponent("child-pid")
        var options = ProcessOptions()
        options.terminationGrace = 0.05
        let operation = Task {
            try await ProcessExecutor.run("/bin/sh", ["-c", "trap '' TERM; /bin/sleep 30 & printf '%s' \"$!\" > \"$1\"; wait", "fixture", childFile.path], options: options)
        }
        defer { operation.cancel() }
        // Synchronize on the child's ready signal, with a deadline for a broken launch.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (try? String(contentsOf: childFile, encoding: .utf8)).flatMap(Int32.init) == nil,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(FileManager.default.fileExists(atPath: childFile.path))
        let began = ContinuousClock.now
        operation.cancel()
        await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(began.duration(to: .now) < .seconds(5))
        try assertChildStopped(childFile)
    }

    @Test func returnsWhenExitedParentLeavesAnOpenOutputPipe() async throws {
        var options = ProcessOptions()
        options.terminateDescendantsOnExit = true
        options.timeout = 5
        let began = ContinuousClock.now
        let result = try await ProcessExecutor.run("/bin/sh", ["-c", "/bin/sleep 30 & printf complete"], options: options)
        #expect(result.status == 0)
        #expect(result.output == "complete")
        #expect(began.duration(to: .now) < .seconds(5))
    }

    @Test func privateLogsAreBoundedAndNeverOverwriteExistingFiles() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let file = home.appendingPathComponent("run.log")
        var options = ProcessOptions()
        options.logFile = file
        options.maxLogBytes = 128
        _ = try await ProcessExecutor.run("/usr/bin/head", ["-c", "8192", "/dev/zero"], options: options)
        let data = try Data(contentsOf: file)
        #expect(data.count < 256) // The cap plus a bounded truncation notice.
        #expect(String(decoding: data, as: UTF8.self).contains("log output truncated"))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        await #expect(throws: (any Error).self) {
            try await ProcessExecutor.run("/usr/bin/printf", ["replacement"], options: options)
        }
        #expect(try Data(contentsOf: file) == data)
    }

    @Test func unrelatedFileDescriptorsAreNotInherited() async throws {
        let descriptor = open("/dev/null", O_RDONLY)
        #expect(descriptor >= 0)
        defer { close(descriptor) }
        let result = try await ProcessExecutor.run("/bin/sh", ["-c", "test ! -e /dev/fd/\"$1\"", "fixture", String(descriptor)])
        #expect(result.status == 0)
    }

    private func assertChildStopped(_ file: URL) throws {
        let child = try #require(Int32(String(contentsOf: file, encoding: .utf8)))
        defer { kill(child, SIGKILL) }
        var options = ProcessOptions()
        options.timeout = 2
        let result = try ProcessExecutor.runSync("/bin/ps", ["-o", "stat=", "-p", String(child)], options: options)
        // A killed orphan can briefly remain a zombie until launchd reaps it.
        #expect(result.status != 0 || result.output.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("Z"))
    }
}
