/// The Settings window's sidebar, in order. Every app preference lives under one of these, never in the panel.
public enum SettingsSection: String, Sendable, CaseIterable, Identifiable {
    case general
    case agents
    case apps
    case terminal
    case notifications
    case appearance
    case setup
    case tasks

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .agents: return "Agents"
        case .apps: return "My Apps"
        case .terminal: return "Terminal"
        case .notifications: return "Notifications"
        case .appearance: return "Appearance"
        case .setup: return "Setup"
        case .tasks: return "Tasks"
        }
    }

    /// SF Symbol shown in the sidebar.
    public var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .agents: return "sparkles"
        case .apps: return "square.grid.2x2"
        case .terminal: return "terminal"
        case .notifications: return "bell.badge"
        case .appearance: return "paintpalette"
        case .setup: return "wrench.and.screwdriver"
        case .tasks: return "clock.arrow.circlepath"
        }
    }

    /// The window opens on General.
    public static let initial: SettingsSection = .general
}
