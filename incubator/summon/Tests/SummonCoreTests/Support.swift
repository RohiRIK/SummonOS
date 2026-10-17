import Foundation
@testable import SummonCore

/// Records every command a fake runner was asked to run.
actor CallLog {
    private(set) var calls: [[String]] = []

    func add(_ call: [String]) {
        calls.append(call)
    }
}

/// A runner that records calls and answers from `responses` (keyed by the tool's last path component).
/// A response of `nil` makes that tool fail.
func fakeRunner(_ log: CallLog, responses: [String: String?] = [:]) -> Runner {
    { path, arguments in
        await log.add([path] + arguments)
        let name = (path as NSString).lastPathComponent
        if let response = responses[name] {
            guard let output = response else {
                throw RunnerError.failed(path: path, status: 1, output: "fake failure")
            }
            return output
        }
        return ""
    }
}

func makeTempHome() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("summon-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func writeFile(_ text: String, to url: URL, executable: Bool = false) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    if executable {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}

let sampleThemeJSON = """
{
  "name": "Summon Night",
  "slug": "summon-night",
  "appearance": "dark",
  "source": "original",
  "colors": {
    "background": "#0B0D17",
    "foreground": "#E6E1F5",
    "accent": "#8B5CF6",
    "accent2": "#22D3EE",
    "muted": "#6B6880",
    "selection": "#2A2440",
    "cursor": "#C4B5FD",
    "border_active": "#8B5CF6",
    "border_inactive": "#2A2440"
  },
  "terminal": [
    "#15172A", "#F7768E", "#9ECE6A", "#E0AF68", "#7AA2F7", "#BB9AF7", "#7DCFFF", "#C0CAF5",
    "#414868", "#FF899D", "#B9F27C", "#FFC777", "#8DB6FF", "#C7A9FF", "#A4DAFF", "#E6E1F5"
  ],
  "font": "JetBrainsMono Nerd Font",
  "wallpapers": ["wallpaper-1.jpg"]
}
"""

/// A crash report in the macOS 12+ `.ips` shape, with documentation-only values.
let sampleCrashIPS = """
{"app_name":"Example","timestamp":"2026-10-17 10:15:00.00 +0000","app_version":"1.2","bug_type":"309","os_version":"macOS 26.0 (26A100)","incident_id":"00000000-0000-4000-8000-000000000000","name":"Example"}
{
  "procName": "Example",
  "pid": 4242,
  "exception": {"type": "EXC_BAD_ACCESS", "signal": "SIGSEGV"},
  "faultingThread": 1,
  "usedImages": [{"name": "Example"}, {"name": "libsystem_kernel.dylib"}],
  "threads": [
    {"frames": [{"imageIndex": 1, "symbol": "mach_msg2_trap"}]},
    {"triggered": true, "frames": [{"imageIndex": 0, "symbol": "Example.crash()"}, {"imageIndex": 1, "symbol": "__pthread_kill"}, {"imageIndex": 5}]}
  ]
}
"""
