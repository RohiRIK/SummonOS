import AppKit
import ApplicationServices
import Foundation

/// What the person was looking at when they pressed the agent hotkey: the frontmost app and window, the selected
/// text, the browser page, the Finder selection. It becomes the agent's first message, so "fix this" works on
/// whatever is on screen. Fields the person turned off in Settings › Agents are never read.
public struct ScreenContext: Sendable, Equatable {
    public var app: String?
    public var bundleID: String?
    public var windowTitle: String?
    public var selectedText: String?
    public var pageTitle: String?
    public var pageURL: String?
    public var finderSelection: [String] = []

    public init(app: String? = nil, bundleID: String? = nil, windowTitle: String? = nil, selectedText: String? = nil,
                pageTitle: String? = nil, pageURL: String? = nil, finderSelection: [String] = []) {
        self.app = app
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.selectedText = selectedText
        self.pageTitle = pageTitle
        self.pageURL = pageURL
        self.finderSelection = finderSelection
    }

    /// Long selections are cut so the first message stays readable.
    public static let selectionLimit = 2_000

    /// Browsers whose front tab can be read with AppleScript: Safari's dictionary, or Chromium's `active tab`.
    public static let safari = "com.apple.Safari"
    public static let chromium = ["com.google.Chrome", "company.thebrowser.Browser", "com.microsoft.edgemac",
                                  "com.brave.Browser", "net.imput.helium"]

    /// The agent's first message; nil when nothing was captured (the agent then starts as before, with no prompt).
    public func prompt() -> String? {
        guard let app else { return nil }
        var lines = ["## What I'm looking at (Summon captured this when I pressed the hotkey)"]
        lines.append("- App: \(app)" + (bundleID.map { " (\($0))" } ?? "") + (windowTitle.map { ", window \"\($0)\"" } ?? ""))
        if let pageURL { lines.append("- Page: " + (pageTitle.map { "\"\($0)\" " } ?? "") + pageURL) }
        if !finderSelection.isEmpty { lines.append("- Selected in Finder: " + finderSelection.joined(separator: ", ")) }
        if let selectedText {
            let cut = selectedText.count > Self.selectionLimit
            lines.append("- Selected text" + (cut ? " (first \(Self.selectionLimit) characters)" : "") + ":")
            lines.append(contentsOf: String(selectedText.prefix(Self.selectionLimit)).split(separator: "\n", omittingEmptySubsequences: false).map { "  > \($0)" })
        }
        lines.append("")
        lines.append("I will ask my question next. Wait for it; do not act on this yet.")
        return lines.joined(separator: "\n")
    }

    /// The AppleScript that reads the front tab or the Finder selection, when that app is in front.
    public static func script(for bundleID: String?, hidden: [ContextField]) -> String? {
        guard let bundleID else { return nil }
        if bundleID == "com.apple.finder", !hidden.contains(.finderSelection) {
            return """
                tell application "Finder"
                    set out to ""
                    repeat with f in (selection as alias list)
                        set out to out & POSIX path of f & linefeed
                    end repeat
                    return out
                end tell
                """
        }
        guard !hidden.contains(.browserPage) else { return nil }
        if bundleID == safari {
            return #"tell application id "com.apple.Safari" to tell front document to return (name as text) & linefeed & (URL as text)"#
        }
        if chromium.contains(bundleID) {
            return #"tell application id "\#(bundleID)" to tell active tab of front window to return (title as text) & linefeed & (URL as text)"#
        }
        return nil
    }

    /// Fills the page or Finder fields from the script's output (`title\nurl`, or one path per line).
    public mutating func apply(scriptOutput: String) {
        let lines = scriptOutput.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if bundleID == "com.apple.finder" {
            finderSelection = Array(lines.prefix(20))
        } else if let url = lines.last, url.contains("://") {
            pageURL = url
            pageTitle = lines.count > 1 ? lines.first : nil
        }
    }

    /// Reads the screen right now. Accessibility is used only when already granted (never prompts); the browser or
    /// Finder script asks macOS for Automation permission the first time, and a refusal just leaves the field empty.
    @MainActor
    public static func capture(hidden: [ContextField], runner: Runner) async -> ScreenContext {
        guard let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier else { return ScreenContext() }
        var context = ScreenContext(app: front.localizedName, bundleID: front.bundleIdentifier)
        if !hidden.contains(.windowTitle) { context.windowTitle = MacContextProbe.focusedWindowTitle(pid: front.processIdentifier) }
        if !hidden.contains(.selectedText) { context.selectedText = selectedText(pid: front.processIdentifier) }
        if let script = script(for: front.bundleIdentifier, hidden: hidden),
           let output = try? await runner("/usr/bin/osascript", ["-e", script]) {
            context.apply(scriptOutput: output)
        }
        return context
    }

    /// The focused element's selected text through Accessibility; nil without permission or selection.
    static func selectedText(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        var selection: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selection) == .success else { return nil }
        let text = (selection as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}
