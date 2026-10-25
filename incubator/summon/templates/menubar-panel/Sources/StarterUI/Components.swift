import SwiftUI

// Menu building blocks modeled on the system Wi-Fi / Control Center menus: full-width rows, a 6 pt rounded
// hover highlight, an 8 pt text inset, no cards or borders. The panel is 300-320 pt wide with 6 pt padding.

/// A clickable menu row. Dimmed and inert under `.disabled(true)`.
struct MenuRow<Content: View>: View {
    var action: (@MainActor () -> Void)?
    @ViewBuilder var content: Content
    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) { content }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .foregroundStyle(isEnabled ? .primary : .tertiary)
            .background {
                if hovering && isEnabled && action != nil {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.quaternary)
                }
            }
            .contentShape(.rect)
            .onHover { hovering = $0 }
            .onTapGesture { if isEnabled { action?() } }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(action != nil ? .isButton : [])
    }
}

/// A command row ("Settings…") with its key hint at the trailing edge, like a menu item.
struct CommandRow: View {
    let title: String
    var key: String?
    let action: @MainActor () -> Void

    var body: some View {
        MenuRow(action: action) {
            Text(title)
            Spacer()
            if let key { Text(key).foregroundStyle(.tertiary) }
        }
        .help(key.map { "\(title) (\($0))" } ?? title)
    }
}

/// A Control Center module for live data: an accent circle icon, a title and a value line on a `.quinary` tile.
/// A standard fill, not glass: it is content.
struct ModuleTile: View {
    let symbol: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Circle().fill(.tint))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold))
                Text(value)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.quinary, in: .rect(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

struct MenuSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 2)
            .accessibilityAddTraits(.isHeader)
    }
}

struct MenuDivider: View {
    var body: some View {
        Divider().padding(.horizontal, 8).padding(.vertical, 5)
    }
}
