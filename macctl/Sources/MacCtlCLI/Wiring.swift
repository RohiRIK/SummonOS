import Foundation
import MacCtlCore

/// The one place the CLI builds the service. Fix init labels here if Core changes.
///
/// With `MACCTL_TEST_MODE=1` (see `TestMode`) the catalog, snapshot directory and optionally the
/// preferences store are replaced, and restarts never run. A partial or unsafe test configuration
/// exits 64 before anything is read or written.
func makeService() -> any MacCtlService {
    let test: TestMode.Configuration?
    do {
        test = try TestMode.configuration(ProcessInfo.processInfo.environment)
    } catch {
        FileHandle.standardError.write(Data("macctl: \(error)\n".utf8))
        exit(64)
    }
    guard let test else {
        return Engine(
            registry: Registry(Catalog.all),
            backend: SystemBackend(runner: ProcessRunner.live()),
            restarter: KillallRestarter(runner: ProcessRunner.live()),
            probe: SystemPermissionProbe(),
            snapshots: FileSnapshotStore(),
            osVersion: { macOSProductVersion() }
        )
    }
    let preferences: any PreferencesStore = test.fakeDefaults.map { PlistFilePreferencesStore(directory: $0) }
        ?? SystemBackend.livePreferences()
    return Engine(
        registry: Registry(test.settings),
        backend: SystemBackend(runner: ProcessRunner.live(), preferences: preferences),
        restarter: TestModeRestarter(),
        probe: SystemPermissionProbe(),
        snapshots: FileSnapshotStore(directory: test.snapshotDirectory),
        osVersion: { macOSProductVersion() }
    )
}

/// `sw_vers -productVersion` (for example `26.0` or `15.6.1`); falls back to ProcessInfo.
func macOSProductVersion() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: Tool.swVers)
    process.arguments = ["-productVersion"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if process.terminationStatus == 0, !text.isEmpty { return text }
    } catch {
        // Fall through to ProcessInfo.
    }
    let v = ProcessInfo.processInfo.operatingSystemVersion
    return v.patchVersion == 0
        ? "\(v.majorVersion).\(v.minorVersion)"
        : "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
}
