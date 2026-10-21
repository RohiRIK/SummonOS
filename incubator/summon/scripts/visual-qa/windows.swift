// CI helper for scripts/visual-qa/run.sh (GitHub macOS runners only; not part of the app).
//   windows <owner>    one line per on-screen window of that process: id layer x y w h
//   windows screen     main display size in points: w h
//   windows click x y  posts a left click at (x, y), top-left origin
// Window bounds and ids come from CGWindowList and need no Screen Recording permission.
import CoreGraphics
import Foundation

let args = CommandLine.arguments.dropFirst()
switch args.first {
case "screen":
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print(Int(bounds.width), Int(bounds.height))
case "click":
    let values = args.dropFirst().compactMap(Double.init)
    guard values.count == 2 else { exit(64) }
    let point = CGPoint(x: values[0], y: values[1])
    for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
        usleep(80_000)
    }
case let owner?:
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in info where (window[kCGWindowOwnerName as String] as? String) == owner {
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print(id, layer, Int(bounds["X"] ?? 0), Int(bounds["Y"] ?? 0), Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0))
    }
default:
    exit(64)
}
