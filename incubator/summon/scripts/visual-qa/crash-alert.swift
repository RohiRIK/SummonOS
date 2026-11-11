// Inspect the exact fixture alert, or dismiss it through its actual accessible Dismiss button.
// This is an owned-window action, not VoiceOver speech/navigation evidence.
//   crash-alert inspect|dismiss <pid> <CG-window-id>
import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func frame(_ element: AXUIElement) -> CGRect? {
    guard let position = attribute(element, kAXPositionAttribute), CFGetTypeID(position) == AXValueGetTypeID(),
          let size = attribute(element, kAXSizeAttribute), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero
    var dimensions = CGSize.zero
    guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
          AXValueGetValue(size as! AXValue, .cgSize, &dimensions) else { return nil }
    return CGRect(origin: origin, size: dimensions)
}

func ownedWindows(_ pid: pid_t) -> [[String: Any]] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return windows.filter { ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid) }
}

let args = CommandLine.arguments
guard args.count == 4, ["inspect", "dismiss"].contains(args[1]),
      let pid = Int32(args[2]), pid > 0, let id = Int(args[3]), id > 0 else { exit(64) }
var evidence: [String: Any] = ["pid": Int(pid), "window_id": id, "operation": "crash alert " + args[1], "press_sent": false]
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
    finish("blocked", "Crash alert interaction requires a disposable runner or explicitly allowed test account")
}
guard AXIsProcessTrusted() else { finish("blocked", "Accessibility permission unavailable") }
guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
    finish("failed", "Owned application exited before dismissal")
}
let visible = ownedWindows(pid)
guard let target = visible.first(where: { ($0[kCGWindowNumber as String] as? Int) == id }),
      let bounds = target[kCGWindowBounds as String] as? [String: Double],
      let x = bounds["X"], let y = bounds["Y"], let width = bounds["Width"], let height = bounds["Height"] else {
    finish("failed", "Requested alert is no longer visible in the owned process")
}
func matches(_ candidate: CGRect?) -> Bool {
    guard let candidate else { return false }
    return abs(candidate.minX - x) <= 1 && abs(candidate.minY - y) <= 1
        && abs(candidate.width - width) <= 1 && abs(candidate.height - height) <= 1
}
let app = AXUIElementCreateApplication(pid)
_ = AXUIElementSetMessagingTimeout(app, 0.25)
guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
    finish("blocked", "Owned AX windows unavailable")
}
let matchingWindows = windows.filter { matches(frame($0)) }
guard matchingWindows.count == 1, let window = matchingWindows.first else {
    finish("blocked", "Owned alert geometry is missing or ambiguous in AX")
}
var pending = [window]
var buttons: [AXUIElement] = []
var titleSeen = false
var summarySeen = false
var visited = 0
let deadline = ProcessInfo.processInfo.systemUptime + 5
while let element = pending.popLast() {
    visited += 1
    guard visited <= 4096, ProcessInfo.processInfo.systemUptime < deadline else {
        finish("failed", "Alert AX traversal exceeded its bounded deadline")
    }
    let strings = [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute]
        .compactMap { attribute(element, $0) as? String }
    titleSeen = titleSeen || strings.contains("Summon Audit Crash 12 crashed")
    summarySeen = summarySeen || strings.contains("12 more new reports in the Summon panel")
    if (attribute(element, kAXRoleAttribute) as? String) == kAXButtonRole, strings.contains("Dismiss") {
        buttons.append(element)
    }
    if let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] {
        pending.append(contentsOf: children)
    }
}
evidence["fixture_title_matches"] = titleSeen
evidence["fixture_summary_matches"] = summarySeen
evidence["dismiss_button_matches"] = buttons.count
guard titleSeen, summarySeen, buttons.count == 1, let button = buttons.first,
      (attribute(button, kAXEnabledAttribute) as? Bool) == true else {
    finish("failed", "Expected fixture alert and one enabled Dismiss button were not exposed")
}
if args[1] == "inspect" {
    finish("passed", "Exact fixture alert title, summary and enabled Dismiss button exposed")
}
let result = AXUIElementPerformAction(button, kAXPressAction as CFString)
evidence["press_ax_error"] = result.rawValue
guard result == .success else { finish("failed", "Native alert Dismiss action failed") }
evidence["press_sent"] = true
let closeDeadline = ProcessInfo.processInfo.systemUptime + 4
repeat {
    guard !running.isTerminated else { finish("failed", "Application exited instead of dismissing the alert") }
    if !ownedWindows(pid).contains(where: { ($0[kCGWindowNumber as String] as? Int) == id }) {
        finish("passed", "Exact fixture alert disappeared after its Dismiss button action")
    }
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
} while ProcessInfo.processInfo.systemUptime < closeDeadline
finish("failed", "Exact fixture alert remained visible after Dismiss")
