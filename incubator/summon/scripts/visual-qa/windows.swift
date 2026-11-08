// CI helper for scripts/visual-qa/run.sh (GitHub-hosted macOS runners only; not part of the app).
//   windows <pid>        one line per on-screen window of that process: id layer x y w h
//   windows screen       main display size in points: w h
//   windows luma <png>   mean luma (0-255) of the image's non-transparent pixels, to sanity-check light vs dark
//   windows close <pid> <id>   focus that exact owned window, send real Command-W, and require its dismissal
//   windows about <pid> <id>   press the meaningfully named About Summon button in that Settings window
//   windows click-status <pid>   hit-test the owned extra-menu item, then send real mouse-down/up for timing
//   windows search <pid> <id>   focus Search Summon, type audit with owned key events, require its actual value
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

func cgFrame(_ window: [String: Any]) -> CGRect? {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Double],
          let x = bounds["X"], let y = bounds["Y"],
          let width = bounds["Width"], let height = bounds["Height"] else { return nil }
    return CGRect(x: x, y: y, width: width, height: height)
}

func axFrame(_ window: AXUIElement) -> CGRect? {
    guard let position = attribute(window, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
          let size = attribute(window, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: origin, size: dimensions)
}

func matchesFrame(_ candidate: CGRect?, _ target: CGRect) -> Bool {
    guard let candidate else { return false }
    // Both public APIs use global screen points; tolerate only their integral rounding.
    return abs(candidate.minX - target.minX) <= 1 && abs(candidate.minY - target.minY) <= 1
        && abs(candidate.width - target.width) <= 1 && abs(candidate.height - target.height) <= 1
}

func clickStatusItem(pid: pid_t) -> Never {
    var evidence: [String: Any] = ["operation": "status-item mouse input", "pid": Int(pid), "mouse_sent": false]
    func finish(_ status: String, _ reason: String) -> Never {
        evidence["status"] = status
        evidence["reason"] = reason
        if let data = try? JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]),
           let text = String(data: data, encoding: .utf8) { print(text) }
        exit(status == "passed" ? 0 : status == "blocked" ? 2 : 1)
    }
    let environment = ProcessInfo.processInfo.environment
    guard (environment["GITHUB_ACTIONS"] == "true" && environment["RUNNER_ENVIRONMENT"] == "github-hosted")
            || environment["VQA_ALLOW_LOCAL"] == "1" else {
        finish("blocked", "Mouse profiling requires a disposable runner or explicitly allowed test account")
    }
    guard AXIsProcessTrusted(), CGPreflightPostEventAccess() else {
        finish("blocked", "Accessibility or input-posting permission unavailable")
    }
    let app = AXUIElementCreateApplication(pid)
    _ = AXUIElementSetMessagingTimeout(app, 0.5)
    guard let extras = attribute(app, kAXExtrasMenuBarAttribute), CFGetTypeID(extras) == AXUIElementGetTypeID(),
          let children = attribute(extras as! AXUIElement, kAXChildrenAttribute) as? [AXUIElement] else {
        finish("blocked", "Owned application does not expose an extra menu bar")
    }
    let items = children.filter { (attribute($0, kAXRoleAttribute) as? String) == kAXMenuBarItemRole }
    evidence["status_item_matches"] = items.count
    guard items.count == 1, let item = items.first,
          let frame = axFrame(item), !frame.isEmpty, !frame.isInfinite,
          frame.midX.isFinite, frame.midY.isFinite else {
        finish("blocked", "Owned status item or its public geometry is missing or ambiguous")
    }
    let point = CGPoint(x: frame.midX, y: frame.midY)
    let system = AXUIElementCreateSystemWide()
    _ = AXUIElementSetMessagingTimeout(system, 0.5)
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(system, Float(point.x), Float(point.y), &hit) == .success,
          let hit else { finish("blocked", "Status item could not be hit-tested") }
    var owner: pid_t = 0
    guard AXUIElementGetPid(hit, &owner) == .success, owner == pid else {
        finish("blocked", "Another process covers the owned status item; no mouse event sent")
    }
    var candidate = hit
    var matched = false
    for _ in 0..<8 {
        if CFEqual(candidate, item) { matched = true; break }
        guard let parent = attribute(candidate, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
        candidate = parent as! AXUIElement
    }
    guard matched else { finish("blocked", "Hit-tested element is not the owned status item; no mouse event sent") }
    guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
          let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
        finish("blocked", "Could not create status-item mouse events")
    }
    // PanelOpen starts in the actual mouse-down monitor. AXPress/URL opening cannot measure that interval.
    // Only this hit-tested, owned status-item action uses pointer geometry; keyboard dismissal never does.
    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
    evidence["mouse_sent"] = true
    finish("passed", "Sent mouse-down/up to the owned hit-tested status item; caller must verify panel opening")
}

func namedControls(_ window: AXUIElement, role: String, label: String) -> (matches: [AXUIElement], count: Int)? {
    var pending = [window]
    var matches: [AXUIElement] = []
    var count = 0
    var visited = 0
    let deadline = ProcessInfo.processInfo.systemUptime + 5
    while let element = pending.popLast() {
        visited += 1
        guard visited <= 4096, ProcessInfo.processInfo.systemUptime < deadline else { return nil }
        if (attribute(element, kAXRoleAttribute) as? String) == role {
            count += 1
            if (attribute(element, kAXTitleAttribute) as? String) == label
                || (attribute(element, kAXDescriptionAttribute) as? String) == label { matches.append(element) }
        }
        if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
            pending.append(contentsOf: children)
        }
    }
    return (matches, count)
}

func windowAction(_ action: String, pid: pid_t, id: Int) -> Never {
    let operation = action == "close" ? "Command-W" : action == "search" ? "Panel search input" : "About Summon action"
    var evidence: [String: Any] = ["operation": operation,
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
    guard let frame = cgFrame(info) else {
        finish("blocked", "identity", "Owned CG window geometry unavailable")
    }
    // About and crash panels can share an empty title. Join public title AND geometry uniquely in
    // both owned lists. Geometry establishes identity only: no coordinate clicks or private AX IDs.
    let sameTitle = windows.filter { ($0[kCGWindowName as String] as? String) == title }
    evidence["cg_title_matches"] = sameTitle.count
    let cgMatches = sameTitle.filter { matchesFrame(cgFrame($0), frame) }
    evidence["cg_identity_matches"] = cgMatches.count
    guard cgMatches.count == 1 else {
        finish("blocked", "identity", "Owned CG window title and geometry are ambiguous")
    }
    guard let axWindows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
        finish("blocked", "identity", "Owned application does not expose AX windows")
    }
    let axTitles = axWindows.filter { (attribute($0, kAXTitleAttribute) as? String) == title }
    evidence["ax_title_matches"] = axTitles.count
    let matches = axTitles.filter { matchesFrame(axFrame($0), frame) }
    evidence["ax_identity_matches"] = matches.count
    guard matches.count == 1, let window = matches.first else {
        finish("blocked", "identity", "Owned AX window title and geometry are missing or ambiguous")
    }
    _ = AXUIElementSetMessagingTimeout(window, 0.5)

    if action == "about" {
        guard title == "General" else {
            finish("failed", "action", "About action requires the General Settings window")
        }
        guard let controls = namedControls(window, role: kAXButtonRole, label: "About Summon") else {
            finish("failed", "action", "Settings AX traversal exceeded its bounded deadline")
        }
        evidence["settings_button_count"] = controls.count
        evidence["about_button_matches"] = controls.matches.count
        guard controls.matches.count == 1, let button = controls.matches.first else {
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
    if action == "search" {
        guard let controls = namedControls(window, role: kAXTextFieldRole, label: "Search Summon"),
              controls.matches.count == 1, let field = controls.matches.first else {
            finish("failed", "search", "Expected one accessible Search Summon text field")
        }
        let resetDeadline = ProcessInfo.processInfo.systemUptime + 2
        while (attribute(field, kAXValueAttribute) as? String) != "" && ProcessInfo.processInfo.systemUptime < resetDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard (attribute(field, kAXValueAttribute) as? String) == "" else {
            finish("failed", "search", "Panel query did not reset on opening")
        }
        // URL opens intentionally do not focus search. Model the user's explicit focus, not an AX value write.
        evidence["raise_ax_error"] = AXUIElementPerformAction(window, kAXRaiseAction as CFString).rawValue
        evidence["window_focus_ax_error"] = AXUIElementSetAttributeValue(window, kAXFocusedAttribute as CFString, kCFBooleanTrue).rawValue
        evidence["focus_ax_error"] = AXUIElementSetAttributeValue(field, kAXFocusedAttribute as CFString, kCFBooleanTrue).rawValue
        let focusDeadline = ProcessInfo.processInfo.systemUptime + 2
        while (attribute(field, kAXFocusedAttribute) as? Bool) != true && ProcessInfo.processInfo.systemUptime < focusDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        guard (attribute(field, kAXFocusedAttribute) as? Bool) == true else {
            finish("failed", "search", "Owned search field did not acquire keyboard focus; no key sent")
        }
        for character in "audit".utf16 {
            var unit = character
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                finish("blocked", "keyboard", "Could not create search keyboard events")
            }
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            up.keyboardSetUnicodeString(stringLength: 1, unicodeString: &unit)
            down.postToPid(pid)
            up.postToPid(pid)
        }
        evidence["keyboard_sent"] = true
        let inputDeadline = ProcessInfo.processInfo.systemUptime + 2
        while (attribute(field, kAXValueAttribute) as? String) != "audit" && ProcessInfo.processInfo.systemUptime < inputDeadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
        evidence["search_query_matches"] = (attribute(field, kAXValueAttribute) as? String) == "audit"
        guard evidence["search_query_matches"] as? Bool == true else {
            finish("failed", "search", "Owned field did not contain the typed query")
        }
        finish("passed", "search", "Owned field reset, focused and exposed the actual typed query")
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
case "click-status":
    guard args.count == 2, let pid = Int32(args[1]), pid > 0 else { exit(64) }
    clickStatusItem(pid: pid)
case "close", "about", "search":
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
