import Foundation

/// What the status item shows next to Summon's icon, and what VoiceOver reads for it. The menu bar has no
/// menu-tracking loop to wait for, so the controller can redraw this every second while an agent runs.
public enum MenuBarStatus {
    /// The text after the icon: the running agent's elapsed `mm:ss`, or nil (icon only).
    public static func title(session: LoggedEvent?, enabled: Bool, now: Date = Date()) -> String? {
        guard enabled, let start = session?.time else { return nil }
        return PanelClock.elapsed(from: start, to: now)
    }

    /// The status item's accessibility label (G3). It names the agent and how long it has run, so VoiceOver users
    /// get the same news the elapsed time gives, even with the title turned off.
    public static func accessibilityLabel(agentName: String?, session: LoggedEvent?, now: Date = Date()) -> String {
        guard let start = session?.time else { return "Summon" }
        let minutes = max(0, Int(now.timeIntervalSince(start)) / 60)
        let running = "\(agentName ?? "Agent") running"
        switch minutes {
        case 0: return "Summon, \(running), under a minute"
        case 1: return "Summon, \(running) for 1 minute"
        default: return "Summon, \(running) for \(minutes) minutes"
        }
    }
}

extension PanelOpenGuard {
    /// What VoiceOver announces when the panel opens without a click (hotkey, URL, CLI). A click already moves
    /// VoiceOver to the status item, but a nonactivating panel opened from elsewhere does not move the
    /// VoiceOver cursor, so without this the panel appears in silence.
    public static func announcement(_ source: PanelOpenSource, focusesSearch: Bool) -> String? {
        guard source != .click else { return nil }
        return focusesSearch ? "Summon menu. Type to search." : "Summon menu opened."
    }
}
