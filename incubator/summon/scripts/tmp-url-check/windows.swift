// TEMPORARY (PR #61 URL check). windows <pid>: one line per on-screen window: id layer x y w h name
import CoreGraphics
import Foundation
guard let arg = CommandLine.arguments.dropFirst().first, let owner = Int(arg) else { exit(64) }
let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in info where (w[kCGWindowOwnerPID as String] as? Int) == owner {
    let b = w[kCGWindowBounds as String] as? [String: Double] ?? [:]
    let name = (w[kCGWindowName as String] as? String ?? "").replacingOccurrences(of: " ", with: "_")
    print(w[kCGWindowNumber as String] as? Int ?? 0, w[kCGWindowLayer as String] as? Int ?? 0,
          Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0), name.isEmpty ? "-" : name)
}
