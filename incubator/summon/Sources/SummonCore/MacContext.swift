import Foundation

/// One read-only snapshot of this Mac for agents (`summon context`): hardware, power, storage, network, displays,
/// apps, appearance, permissions, agents and recent problems. Every section is optional so `--only` can trim it
/// and a section that could not be read is simply absent.
public struct MacContext: Sendable, Equatable, Codable {
    public struct System: Sendable, Equatable, Codable {
        public var model: String
        public var chip: String
        public var memoryGB: Int
        public var macOS: String
        public var hostname: String?
        public var uptimeHours: Double
    }

    public struct Power: Sendable, Equatable, Codable {
        /// Percent; nil on a Mac without a battery.
        public var battery: Int?
        public var charging: Bool?
        public var onAC: Bool
        public var lowPowerMode: Bool
        /// nominal, fair, serious or critical.
        public var thermal: String
    }

    public struct Volume: Sendable, Equatable, Codable {
        public var name: String
        public var path: String?
        public var freeGB: Int
        public var totalGB: Int
    }

    public struct Network: Sendable, Equatable, Codable {
        public var online: Bool
        public var primaryInterface: String?
        public var vpn: Bool
    }

    public struct Display: Sendable, Equatable, Codable {
        /// Size in points.
        public var width: Int
        public var height: Int
        public var scale: Int
        public var main: Bool
    }

    public struct Apps: Sendable, Equatable, Codable {
        public var frontmost: String?
        public var frontmostBundleID: String?
        /// Needs Accessibility for the process that asks.
        public var windowTitle: String?
        public var running: [String]?
    }

    public struct Appearance: Sendable, Equatable, Codable {
        public var dark: Bool
        public var accent: String
        public var wallpaper: String?
    }

    /// What the process asking (the agent's terminal) is allowed to do.
    public struct Permissions: Sendable, Equatable, Codable {
        public var accessibility: Bool
        public var screenRecording: Bool
        public var fullDiskAccess: Bool
    }

    public struct Agents: Sendable, Equatable, Codable {
        public var defaultAgent: String?
        public var installed: [String]
    }

    public var generated: Date
    public var system: System?
    public var power: Power?
    public var storage: [Volume]?
    public var network: Network?
    public var displays: [Display]?
    public var apps: Apps?
    public var appearance: Appearance?
    public var permissions: Permissions?
    public var agents: Agents?
    /// Crash, hang and panic reports in the last 24 hours (muted programs skipped).
    public var recentCrashes: Int?
    /// Fields the person turned off in Settings › Agents, so agents know they are hidden, not missing.
    public var hidden: [String]

    public static let sections = ["system", "power", "storage", "network", "displays", "apps", "appearance",
                                  "permissions", "agents", "crashes"]

    /// Keeps only the named sections; unknown names throw so a typo is not silently an empty snapshot.
    public func only(_ names: [String]) throws -> MacContext {
        if let unknown = names.first(where: { !Self.sections.contains($0) }) {
            throw ContextError.unknownSection(unknown)
        }
        var trimmed = MacContext(generated: generated, hidden: hidden)
        for name in names {
            switch name {
            case "system": trimmed.system = system
            case "power": trimmed.power = power
            case "storage": trimmed.storage = storage
            case "network": trimmed.network = network
            case "displays": trimmed.displays = displays
            case "apps": trimmed.apps = apps
            case "appearance": trimmed.appearance = appearance
            case "permissions": trimmed.permissions = permissions
            case "agents": trimmed.agents = agents
            default: trimmed.recentCrashes = recentCrashes
            }
        }
        return trimmed
    }

    /// Removes the fields the person turned off. Applied once, before anything leaves the probe.
    public func hiding(_ fields: [ContextField]) -> MacContext {
        var result = self
        for field in fields {
            switch field {
            case .hostname: result.system?.hostname = nil
            case .windowTitle: result.apps?.windowTitle = nil
            case .runningApps: result.apps?.running = nil
            case .paths:
                result.appearance?.wallpaper = nil
                result.storage = result.storage?.map { var volume = $0; volume.path = nil; return volume }
            case .selectedText, .browserPage, .finderSelection:
                break
            }
        }
        result.hidden = fields.filter(\.inSnapshot).map(\.rawValue).sorted()
        return result
    }

    /// Short Markdown for a prompt or a SessionStart hook: one line per section, about 15 lines.
    public func render() -> String {
        var lines = ["## This Mac (summon context, \(Self.stamp.string(from: generated)))"]
        if let system {
            var parts = [system.model, system.chip, "\(system.memoryGB) GB RAM", "macOS \(system.macOS)"]
            if let name = system.hostname { parts.append("name \"\(name)\"") }
            parts.append(String(format: "up %.1f h", system.uptimeHours))
            lines.append("- Mac: " + parts.joined(separator: ", "))
        }
        if let power {
            var parts: [String] = []
            if let battery = power.battery {
                parts.append("battery \(battery)%" + (power.charging == true ? ", charging" : power.onAC ? ", on power" : ", on battery"))
            } else {
                parts.append("no battery, on power")
            }
            parts.append("thermal \(power.thermal)")
            if power.lowPowerMode { parts.append("Low Power Mode on") }
            lines.append("- Power: " + parts.joined(separator: ", "))
        }
        if let storage, !storage.isEmpty {
            lines.append("- Storage: " + storage.map { volume in
                "\(volume.name) \(volume.freeGB) of \(volume.totalGB) GB free" + (volume.path.map { " (\($0))" } ?? "")
            }.joined(separator: "; "))
        }
        if let network {
            let link = network.online ? "online" + (network.primaryInterface.map { " via \($0)" } ?? "") : "offline"
            lines.append("- Network: \(link), VPN \(network.vpn ? "on" : "off")")
        }
        if let displays, !displays.isEmpty {
            lines.append("- Displays: \(displays.count) (" + displays.map { display in
                "\(display.width)x\(display.height) @\(display.scale)x" + (display.main ? " main" : "")
            }.joined(separator: ", ") + ")")
        }
        if let apps {
            if let frontmost = apps.frontmost {
                lines.append("- Frontmost: \(frontmost)" + (apps.frontmostBundleID.map { " (\($0))" } ?? "")
                    + (apps.windowTitle.map { ", window \"\($0)\"" } ?? ""))
            }
            if let running = apps.running {
                lines.append("- Running apps (\(running.count)): " + running.joined(separator: ", "))
            }
        }
        if let appearance {
            lines.append("- Appearance: \(appearance.dark ? "dark" : "light"), accent \(appearance.accent)"
                + (appearance.wallpaper.map { ", wallpaper \($0)" } ?? ""))
        }
        if let permissions {
            func yes(_ value: Bool) -> String { value ? "yes" : "no" }
            lines.append("- Permissions (this process): Accessibility \(yes(permissions.accessibility)), "
                + "Screen Recording \(yes(permissions.screenRecording)), Full Disk Access \(yes(permissions.fullDiskAccess))")
        }
        if let agents {
            lines.append("- Agents: default \(agents.defaultAgent ?? "none"); installed "
                + (agents.installed.isEmpty ? "none" : agents.installed.joined(separator: ", ")))
        }
        if let recentCrashes {
            lines.append("- Problems: " + (recentCrashes == 0 ? "no crashes or hangs in the last day"
                : "\(recentCrashes) crash\(recentCrashes == 1 ? "" : "es") or hang\(recentCrashes == 1 ? "" : "s") in the last day (summon crash list)"))
        }
        if !hidden.isEmpty {
            lines.append("- Hidden by the user: " + hidden.joined(separator: ", "))
        }
        lines.append("Settings: macctl list / macctl get <id>. Undo: summon checkpoint list. Everything: summon commands --json.")
        return lines.joined(separator: "\n")
    }

    /// What `summon context --hook <agent>` prints: plain text where the agent adds a start hook's stdout to the
    /// session (Claude Code, Codex), and the JSON shape Cursor and the Antigravity CLI read.
    public func hookOutput(for agent: String) -> String {
        let text = render()
        switch agent {
        case "cursor": return MCPServer.encode(.object(["additional_context": .string(text)]))
        case "agy": return MCPServer.encode(.object(["injectSteps": .array([.object(["systemMessage": .object(["systemMessage": .string(text)])])])]))
        default: return text
        }
    }

    /// `AppleAccentColor` from the global domain; absent means the multicolor default.
    public static func accentName(_ value: Int?) -> String {
        switch value {
        case -1: "graphite"
        case 0: "red"
        case 1: "orange"
        case 2: "yellow"
        case 3: "green"
        case 4: "blue"
        case 5: "purple"
        case 6: "pink"
        default: "multicolor"
        }
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}

/// Context fields the person can turn off in Settings › Agents. Everything is on by default (owner's choice).
public enum ContextField: String, Sendable, CaseIterable, Codable {
    case hostname
    case windowTitle = "window-title"
    case runningApps = "running-apps"
    case paths
    /// The hotkey's capture (`ScreenContext`), not part of `summon context`.
    case selectedText = "selected-text"
    case browserPage = "browser-page"
    case finderSelection = "finder-selection"

    /// Part of `summon context`; the rest belong to the agent hotkey's capture.
    public var inSnapshot: Bool { ![.selectedText, .browserPage, .finderSelection].contains(self) }

    public var title: String {
        switch self {
        case .hostname: "Computer name"
        case .windowTitle: "Frontmost window title"
        case .runningApps: "Running apps"
        case .paths: "File paths (wallpaper, volumes)"
        case .selectedText: "Selected text (agent hotkey)"
        case .browserPage: "Browser page title and URL (agent hotkey)"
        case .finderSelection: "Finder selection (agent hotkey)"
        }
    }
}

public enum ContextError: Error, Equatable, CustomStringConvertible {
    case unknownSection(String)
    case unknownField(String)

    public var description: String {
        switch self {
        case .unknownSection(let name):
            "Unknown section: \(name). Sections: \(MacContext.sections.joined(separator: ", "))"
        case .unknownField(let name):
            "Unknown field: \(name). Fields: \(ContextField.allCases.map(\.rawValue).joined(separator: ", "))"
        }
    }
}
