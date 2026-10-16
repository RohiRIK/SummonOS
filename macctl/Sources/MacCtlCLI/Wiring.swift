import Foundation
import MacCtlCore

/// The one place the CLI builds the real service. Fix init labels here if Core changes.
func makeService() -> any MacCtlService {
    Engine(
        registry: Registry(Catalog.all),
        backend: SystemBackend(runner: ProcessRunner.live()),
        restarter: KillallRestarter(runner: ProcessRunner.live()),
        probe: SystemPermissionProbe(),
        snapshots: FileSnapshotStore(),
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
