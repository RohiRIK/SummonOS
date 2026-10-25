import SwiftUI

extension View {
    /// Liquid Glass on macOS 26, a thin material on macOS 15. Only for the control layer (a footer, a floating
    /// control): never on rows, lists or content, and never glass on glass (LiquidGlass skill).
    @ViewBuilder
    public func glassControl(cornerRadius: CGFloat = 8) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.thinMaterial, in: shape)
        }
    }
}
