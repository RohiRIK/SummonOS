// CI helper for scripts/visual-qa/run.sh (GitHub-hosted macOS runners only; not part of the app).
//   windows <pid>        one line per on-screen window of that process: id layer x y w h
//   windows screen       main display size in points: w h
//   windows luma <png>   mean luma (0-255) of the image's non-transparent pixels, to sanity-check light vs dark
//   windows close <pid> <id>   focus that exact owned window, send real Command-W, and require its dismissal
//   windows about <pid> <id>   press the meaningfully named About Summon button in that Settings window
// Actions emit bounded JSON diagnostics, never window titles, text contents, paths or unrelated process data.
// Window bounds and ids come from CGWindowList and need no Screen Recording permission.
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import ImageIO

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func ownedWindows(_ pid: pid_t) -> [[String: Any]] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
}

func windowAction(_ action: String, pid: pid_t, id: Int) -> Never {
    var evidence: [String: Any] = ["operation": action == "close" ? "Command-W" : "About Summon action",
                                   "pid": Int(pid), "window_id": id, "keyboard_sent": false]
    func finish(_ status: String, _ stage: String, _ reason: String) -> Never {
        evidence["status"] = status
        evidence["stage"] = stage
        evidence["reason"] = reason
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        exit(status == "passed" ? 0 : status == "blocked" ? 2 : 1)
    }
    let trusted = AXIsProcessTrusted()
    evidence["accessibility_trusted"] = trusted
    evidence["screen_recording_access"] = CGPreflightScreenCaptureAccess()
    guard trusted else {
        finish("blocked", "permission", "Accessibility access unavailable to owned-window helper")
    }
    let app = AXUIElementCreateApplication(pid)
    _ = AXUIElementSetMessagingTimeout(app, 0.5)
    let windows = ownedWindows(pid)
    evidence["owned_visible_window_count"] = windows.count
    guard let info = windows.first(where: { ($0[kCGWindowNumber as String] as? Int) == id }) else {
        finish("failed", "identity", "Requested window is not visible in the owned process")
    }
    guard let title = info[kCGWindowName as String] as? String else {
        finish("blocked", "identity", "Window title metadata unavailable; Screen Recording access is required")
    }
    // Public APIs expose a CG window ID and an AX title, but no public AX window-number attribute.
    // Join by title only when unique in BOTH owned lists; never guess with front-window order or coordinates.
    let sameTitle = windows.filter { ($0[kCGWindowName as String] as? String) == title }
    evidence["cg_title_matches"] = sameTitle.count
    guard sameTitle.count == 1 else {
        finish("blocked", "identity", "Owned CG window title is ambiguous")
    }
    guard let axWindows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
        finish("blocked", "identity", "Owned application does not expose AX windows")
    }
    let matches = axWindows.filter { (attribute($0, kAXTitleAttribute) as? String) == title }
    evidence["ax_title_matches"] = matches.count
    guard matches.count == 1, let window = matches.first else {
        finish("blocked", "identity", "Owned AX window title is missing or ambiguous")
    }
    _ = AXUIElementSetMessagingTimeout(window, 0.5)

    if action == "about" {
        guard title == "General" else {
            finish("failed", "action", "About action requires the General Settings window")
        }
        var pending = [window]
        var buttons: [AXUIElement] = []
        var buttonCount = 0
        var visited = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while let element = pending.popLast() {
            visited += 1
            guard visited <= 4096, ProcessInfo.processInfo.systemUptime < deadline else {
                finish("failed", "action", "Settings AX traversal exceeded its bounded deadline")
            }
            if (attribute(element, kAXRoleAttribute) as? String) == kAXButtonRole {
                buttonCount += 1
                let name = attribute(element, kAXTitleAttribute) as? String
                let description = attribute(element, kAXDescriptionAttribute) as? String
                if name == "About Summon" || description == "About Summon" { buttons.append(element) }
            }
            if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children)
            }
        }
        evidence["settings_button_count"] = buttonCount
        evidence["about_button_matches"] = buttons.count
        guard buttons.count == 1, let button = buttons.first else {
            finish("failed", "action", "Expected one button actually named About Summon")
        }
        // Materialize the properties, not AppleScript object specifiers. Only fixed expected labels are emitted.
        evidence["button_title_is_about"] = (attribute(button, kAXTitleAttribute) as? String) == "About Summon"
        evidence["button_description_is_about"] = (attribute(button, kAXDescriptionAttribute) as? String) == "About Summon"
        guard (attribute(button, kAXEnabledAttribute) as? Bool) == true else {
            finish("failed", "action", "About Summon button is disabled")
        }
        let pressed = AXUIElementPerformAction(button, kAXPressAction as CFString)
        evidence["press_ax_error"] = pressed.rawValue
        guard pressed == .success else { finish("failed", "action", "Native About button press failed") }
        finish("passed", "action", "Pressed the accessible Settings About Summon button")
    }

    evidence["post_event_access"] = CGPreflightPostEventAccess()
    guard CGPreflightPostEventAccess() else {
        finish("blocked", "permission", "Keyboard event posting access unavailable")
    }
    guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
        finish("failed", "activation", "Owned application exited before keyboard dismissal")
    }
    evidence["activation_policy"] = running.activationPolicy.rawValue
    evidence["activation_requested"] = running.activate(options: [])
    evidence["raise_ax_error"] = AXUIElementPerformAction(window, kAXRaiseAction as CFString).rawValue
    evidence["focus_ax_error"] = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue).rawValue
    func focused() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
        let focusedWindow = attribute(app, kAXFocusedWindowAttribute)
        let matches = focusedWindow.map { CFEqual($0, window) } ?? false
        evidence["frontmost_pid_matches"] = frontmost
        evidence["focused_window_matches"] = matches
        return frontmost && matches
    }
    let focusDeadline = ProcessInfo.processInfo.systemUptime + 4
    while !focused() && ProcessInfo.processInfo.systemUptime < focusDeadline {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05)) // poll actual focus, not a readiness sleep
    }
    guard focused() else {
        finish("failed", "activation", "Owned target did not acquire application and keyboard focus; no key sent")
    }
    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: true),
          let up = CGEvent(keyboardEventSource: nil, virtualKey: 13, keyDown: false) else {
        finish("blocked", "keyboard", "Could not create Command-W keyboard events")
    }
    down.flags = .maskCommand
    up.flags = .maskCommand
    // Keep delivery owned even if another application steals activation after the focus observation.
    down.postToPid(pid)
    up.postToPid(pid)
    evidence["keyboard_sent"] = true
    let closeDeadline = ProcessInfo.processInfo.systemUptime + 4
    repeat {
        guard !running.isTerminated, NSRunningApplication(processIdentifier: pid) != nil else {
            finish("failed", "dismissal", "Owned application exited instead of only closing the target window")
        }
        if !ownedWindows(pid).contains(where: { ($0[kCGWindowNumber as String] as? Int) == id }) {
            finish("passed", "dismissal", "Exact owned window disappeared after Command-W")
        }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    } while ProcessInfo.processInfo.systemUptime < closeDeadline
    finish("failed", "dismissal", "Exact owned window remained visible after Command-W")
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "close", "about":
    guard args.count == 3, let pid = Int32(args[1]), pid > 0, let id = Int(args[2]), id > 0 else { exit(64) }
    windowAction(args[0], pid: pid, id: id)
case "screen":
    let bounds = CGDisplayBounds(CGMainDisplayID())
    print(Int(bounds.width), Int(bounds.height))
case "luma":
    guard args.count == 2,
          let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { exit(1) }
    // Downscale into a small RGBA buffer; transparent pixels (window corners) are left out of the mean.
    let side = 64
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                      bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return true
    }
    guard drawn else { exit(1) }
    var total = 0.0, weight = 0.0
    for i in stride(from: 0, to: pixels.count, by: 4) {
        let alpha = Double(pixels[i + 3]) / 255
        guard alpha > 0.5 else { continue }
        // Un-premultiply, then Rec. 601 luma.
        let r = Double(pixels[i]) / alpha, g = Double(pixels[i + 1]) / alpha, b = Double(pixels[i + 2]) / alpha
        total += 0.299 * r + 0.587 * g + 0.114 * b
        weight += 1
    }
    guard weight > 0 else { exit(1) }
    print(Int((total / weight).rounded()))
case let pid?:
    guard let owner = Int(pid) else { exit(64) }
    let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in info where (window[kCGWindowOwnerPID as String] as? Int) == owner {
        let id = window[kCGWindowNumber as String] as? Int ?? 0
        let layer = window[kCGWindowLayer as String] as? Int ?? 0
        let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print(id, layer, Int(bounds["X"] ?? 0), Int(bounds["Y"] ?? 0), Int(bounds["Width"] ?? 0), Int(bounds["Height"] ?? 0))
    }
default:
    exit(64)
}
