# NeXTSTEP SwiftUI Components

SwiftUI components interpreting NeXTSTEP 3.3 / OPENSTEP 4.2 industrial 3D computing aesthetics.

Copy the Swift blocks in this file together into a macOS 15+ target. Preserve native
window chrome, focus, keyboard activation, and accessible labels; these are content
components, not replacements for AppKit window management. Colors approximate an era.

## 1. Deep Sculpted 3D Button (`NeXTButton`)

```swift
import SwiftUI

public struct NeXTButtonStyle: ButtonStyle {
    public var isDefault: Bool = false

    public init(isDefault: Bool = false) {
        self.isDefault = isDefault
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold, design: .default))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(Color(white: 0.67))
            .overlay(
                ZStack {
                    // Chiseled borders (inverted on press)
                    let hi = configuration.isPressed ? Color.black : Color.white
                    let lo = configuration.isPressed ? Color.white : Color.black

                    VStack {
                        Rectangle().fill(hi).frame(height: 2)
                        Spacer()
                        Rectangle().fill(lo).frame(height: 2)
                    }
                    HStack {
                        Rectangle().fill(hi).frame(width: 2)
                        Spacer()
                        Rectangle().fill(lo).frame(width: 2)
                    }
                }
            )
            .overlay(
                Group {
                    if isDefault {
                        Rectangle()
                            .stroke(Color.black, lineWidth: 2)
                            .padding(-3)
                    }
                }
            )
    }
}
```

---

## 2. NeXTSTEP In-content Header (`NeXTTitleBar`)

Wire the header callbacks to real actions while retaining native window controls.
The content header does not implement window dragging or full-screen behavior.

```swift
public struct NeXTTitleBar: View {
    public var title: String
    public var onClose: () -> Void
    public var onMiniaturize: () -> Void

    public init(title: String, onClose: @escaping () -> Void, onMiniaturize: @escaping () -> Void) {
        self.title = title
        self.onClose = onClose
        self.onMiniaturize = onMiniaturize
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Miniaturize button
            Button(action: onMiniaturize) {
                Text("▼")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 14, height: 14)
                    .background(Color(white: 0.75))
                    .border(Color.black, width: 1)
            }
            .buttonStyle(.plain)
            .padding(.leading, 6)
            .accessibilityLabel("Minimize")

            Spacer()

            Text(title)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.white)

            Spacer()

            // Close button
            Button(action: onClose) {
                Text("X")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 14, height: 14)
                    .background(Color(white: 0.75))
                    .border(Color.black, width: 1)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 6)
            .accessibilityLabel("Close")
        }
        .frame(height: 22)
        .background(Color(white: 0.15))
        .border(Color.black, width: 1)
    }
}
```

---

## 3. NeXT Dock Application Tile (`NeXTDockTile`)

```swift
public struct NeXTDockTile: View {
    public var iconName: String
    public var label: String
    public var isRunning: Bool
    public var action: () -> Void

    public init(iconName: String, label: String, isRunning: Bool = true, action: @escaping () -> Void) {
        self.iconName = iconName
        self.label = label
        self.isRunning = isRunning
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                // 3D Tile
                VStack(spacing: 4) {
                    Image(systemName: iconName)
                        .font(.system(size: 20))
                        .foregroundStyle(Color.black)
                    Text(label)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                }
                // Reserve a bottom strip for the running badge in both states.
                .padding(.bottom, 14)
                .frame(width: 54, height: 54)
                .background(Color(white: 0.67))
                .overlay(
                    ZStack {
                        VStack {
                            Rectangle().fill(Color.white).frame(height: 2)
                            Spacer()
                            Rectangle().fill(Color.black).frame(height: 2)
                        }
                        HStack {
                            Rectangle().fill(Color.white).frame(width: 2)
                            Spacer()
                            Rectangle().fill(Color.black).frame(width: 2)
                        }
                    }
                )

                // 3-dot running indicator
                if isRunning {
                    HStack(spacing: 2) {
                        Circle().fill(Color.white).frame(width: 3, height: 3)
                        Circle().fill(Color.white).frame(width: 3, height: 3)
                        Circle().fill(Color.white).frame(width: 3, height: 3)
                    }
                    .padding(3)
                    .background(Color.black)
                    .padding(3)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isRunning ? "Running" : "Not running")
    }
}
```
