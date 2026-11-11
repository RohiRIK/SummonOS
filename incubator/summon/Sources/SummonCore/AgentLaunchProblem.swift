import CoreServices
import Foundation

/// Why Ask Agent could not open the agent's terminal, said as what to do about it.
public enum AgentLaunchProblem {
    /// macOS refused the Apple Event (`errAEEventNotPermitted`).
    public static let notPermitted: Int32 = -1743
    /// macOS has not asked yet; the first launch shows the Allow dialog (`errAEEventWouldRequireUserConsent`).
    public static let needsConsent: Int32 = -1744

    public static func explain(_ error: Error, terminal: TerminalApp) -> String {
        switch error as? RunnerError {
        case .timedOut?:
            return "\(terminal.name) did not open in time. macOS may be waiting for you to allow Summon to control "
                + "\(terminal.name): look for a dialog, or open \(settingsPath(terminal))."
        case let .failed(_, _, output)?:
            if output.contains(String(notPermitted)) || output.contains("Not authorized to send Apple events") {
                return blocked(terminal)
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? String(describing: error) : trimmed
        default:
            return String(describing: error)
        }
    }

    public static func blocked(_ terminal: TerminalApp) -> String {
        "macOS does not let Summon control \(terminal.name), so Ask Agent cannot open it. Allow it in "
            + "\(settingsPath(terminal)). Summon not listed there? Run `tccutil reset AppleEvents local.macplugins.summon`, "
            + "then Ask Agent again and click Allow."
    }

    static func settingsPath(_ terminal: TerminalApp) -> String {
        "System Settings › Privacy & Security › Automation › Summon › \(terminal.name)"
    }

    /// The app Summon drives over AppleScript; kitty opens through `open` and needs no Automation permission.
    public static func automationTarget(_ terminal: TerminalApp) -> String? {
        switch terminal {
        case .ghostty: return "com.mitchellh.ghostty"
        case .terminal: return "com.apple.Terminal"
        case .kitty: return nil
        }
    }

    /// Whether this process may send Apple Events to `bundleID`, without ever showing the dialog.
    /// 0 allowed, `notPermitted`, `needsConsent`, or another status (for example the app is not running).
    public static func automationStatus(bundleID: String) -> Int32 {
        var target = AEAddressDesc()
        let bytes = Array(bundleID.utf8)
        guard AECreateDesc(typeApplicationBundleID, bytes, bytes.count, &target) == noErr else { return -1 }
        defer { AEDisposeDesc(&target) }
        return AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, false)
    }
}
