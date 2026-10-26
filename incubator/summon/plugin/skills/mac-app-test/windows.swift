// swift windows.swift <pid>: one line per on-screen window of that process: "id layer x y width height title".
// CGWindowList gives ids and bounds without Screen Recording; titles stay empty without it.
import CoreGraphics
import Foundation

guard let arg = CommandLine.arguments.dropFirst().first, let pid = Int32(arg) else {
    FileHandle.standardError.write(Data("usage: swift windows.swift <pid>\n".utf8))
    exit(2)
}
let all = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for info in all where (info[kCGWindowOwnerPID as String] as? Int32) == pid {
    let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]
    let values = [info[kCGWindowNumber as String] as? Int ?? 0, info[kCGWindowLayer as String] as? Int ?? 0,
                  Int(bounds["X"] ?? 0), Int(bounds["Y"] ?? 0), Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0)]
    print(values.map(String.init).joined(separator: " "), info[kCGWindowName as String] as? String ?? "")
}
