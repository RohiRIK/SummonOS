# Classic Platinum SwiftUI Components

SwiftUI components interpreting the System 7 and Mac OS 8/9 Platinum visual language.

Copy the Swift blocks in this file together into a macOS 15+ target. Preserve native
window chrome, focus, keyboard activation, and accessible labels; these are content
components, not replacements for AppKit window management. Colors approximate an era.

## 1. Platinum 3D Beveled Box (`ClassicBevelBox`)

```swift
import SwiftUI

public enum BevelStyle {
    case raised
    case recessed
}

public struct ClassicBevelBox<Content: View>: View {
    public var style: BevelStyle
    public var backgroundColor: Color
    public var content: () -> Content

    public init(
        style: BevelStyle = .raised,
        backgroundColor: Color = Color(white: 0.85),
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.style = style
        self.backgroundColor = backgroundColor
        self.content = content
    }

    public var body: some View {
        content()
            .background(backgroundColor)
            .overlay(
                ZStack {
                    // Top & Left highlight
                    VStack {
                        Rectangle()
                            .fill(style == .raised ? Color.white : Color(white: 0.4))
                            .frame(height: 1.5)
                        Spacer()
                    }
                    HStack {
                        Rectangle()
                            .fill(style == .raised ? Color.white : Color(white: 0.4))
                            .frame(width: 1.5)
                        Spacer()
                    }

                    // Bottom & Right shadow
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(style == .raised ? Color(white: 0.4) : Color.white)
                            .frame(height: 1.5)
                    }
                    HStack {
                        Spacer()
                        Rectangle()
                            .fill(style == .raised ? Color(white: 0.4) : Color.white)
                            .frame(width: 1.5)
                    }
                }
            )
            .border(Color.black, width: 1)
    }
}
```

---

## 2. Classic Platinum Push Button (`ClassicButton`)

```swift
public struct ClassicButtonStyle: ButtonStyle {
    public var isDefault: Bool = false

    public init(isDefault: Bool = false) {
        self.isDefault = isDefault
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 5)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(configuration.isPressed ? Color(white: 0.70) : Color(white: 0.88))

                    // 3D Bevel
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(
                            configuration.isPressed ? Color.black : Color.white,
                            lineWidth: 1
                        )

                    // Outer border
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.black, lineWidth: 1)
                }
            )
            .overlay(
                Group {
                    if isDefault {
                        // Double heavy border for default button
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(Color.black, lineWidth: 2.5)
                            .padding(-3)
                    }
                }
            )
    }
}
```

---

## 3. In-content Pinstripe Header (`ClassicTitleBar`)

Wire close and collapse to real content actions. Keep native window controls visible;
this header does not implement window dragging, zooming, or a window titlebar.

```swift
public struct ClassicTitleBar: View {
    public var title: String
    public var onClose: () -> Void
    public var onCollapse: () -> Void

    public init(title: String, onClose: @escaping () -> Void, onCollapse: @escaping () -> Void) {
        self.title = title
        self.onClose = onClose
        self.onCollapse = onCollapse
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Close Box
            Button(action: onClose) {
                Rectangle()
                    .fill(Color(white: 0.88))
                    .frame(width: 12, height: 12)
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
            .accessibilityLabel("Close")

            // Left horizontal pinstripes
            PinstripeLines()

            // Centered Title Badge
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .padding(.horizontal, 8)
                .background(Color(white: 0.88))

            // Right horizontal pinstripes
            PinstripeLines()

            // WindowShade Collapse Box
            Button(action: onCollapse) {
                Rectangle()
                    .fill(Color(white: 0.88))
                    .frame(width: 12, height: 12)
                    .overlay(
                        VStack(spacing: 2) {
                            Rectangle().fill(Color.black).frame(height: 2)
                            Rectangle().fill(Color.black).frame(height: 2)
                        }
                        .padding(2)
                    )
                    .overlay(Rectangle().stroke(Color.black, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
            .accessibilityLabel("Collapse content")
        }
        .frame(height: 20)
        .background(Color(white: 0.88))
        .border(Color.black, width: 1)
    }
}

struct PinstripeLines: View {
    var body: some View {
        VStack(spacing: 2) {
            ForEach(0..<6) { _ in
                Rectangle()
                    .fill(Color.black)
                    .frame(height: 1)
            }
        }
    }
}
```
