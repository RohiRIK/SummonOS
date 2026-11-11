import SwiftUI

extension SummonModel {
    /// Resolve from observed state, so both a theme switch and an edited active palette update live views.
    var themeAccent: Color {
        guard let theme = themes.first(where: { $0.slug == currentThemeSlug }),
              let color = Color(hex: theme.colors.accent) else { return .accentColor }
        return color
    }
}

extension View {
    func summonTheme(_ model: SummonModel) -> some View {
        modifier(SummonThemeTint(model: model))
    }
}

private struct SummonThemeTint: ViewModifier {
    let model: SummonModel

    func body(content: Content) -> some View {
        content.tint(model.themeAccent)
    }
}
