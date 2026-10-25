import StarterCore
import SwiftUI

/// The Mac's Summon theme as SwiftUI colors. Nil means "keep the system color", which is what you get when
/// Summon has no theme set.
public struct SummonTheme: Equatable, Sendable {
    public var accent: Color?
    private var colors: [String: Color] = [:]

    public static let system = SummonTheme()

    public init(file: SummonThemeFile? = nil) {
        colors = (file?.colors ?? [:]).mapValues { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        accent = colors["accent"]
    }

    public static func current() -> SummonTheme { SummonTheme(file: SummonThemeFile.load()) }

    /// Any color the theme defines: `background`, `foreground`, `accent2`, `muted`, `selection`, ...
    public func color(_ name: String) -> Color? { colors[name] }
}

private struct SummonThemeKey: EnvironmentKey {
    static let defaultValue = SummonTheme.system
}

extension EnvironmentValues {
    /// The theme `.themed()` applied; read it for colors beyond the accent.
    public var summonTheme: SummonTheme {
        get { self[SummonThemeKey.self] }
        set { self[SummonThemeKey.self] = newValue }
    }
}

extension View {
    /// Put on every window root (panel, Settings, main window): tints controls with the Summon theme's accent
    /// and follows `summon theme set` while the app runs. Backgrounds stay the system's.
    public func themed() -> some View {
        modifier(Themed())
    }
}

private struct Themed: ViewModifier {
    @State private var theme = SummonTheme.current()

    func body(content: Content) -> some View {
        content
            .tint(theme.accent)
            .environment(\.summonTheme, theme)
            .task {
                for await _ in SummonThemeFile.changes() {
                    theme = .current()
                }
            }
    }
}
