# Yosemite SwiftUI Components

SwiftUI components interpreting OS X 10.10–10.15 flat translucency and vibrancy.

Copy the Swift blocks in this file together into a macOS 15+ target. Preserve native
window chrome, focus, keyboard activation, and accessible labels; these are content
components, not replacements for AppKit window management. Colors approximate an era.

## 1. Yosemite Flat Button (`YosemiteButton`)

```swift
import SwiftUI
import AppKit

public struct YosemiteButtonStyle: ButtonStyle {
    public var isProminent: Bool = false

    public init(isProminent: Bool = false) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .regular))
            .foregroundStyle(isProminent ? Color.white : Color.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(
                        isProminent
                            ? Color(red: 0.0, green: 0.48, blue: 1.0)
                            : (configuration.isPressed ? Color.gray.opacity(0.2) : Color(nsColor: .controlBackgroundColor))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(
                        isProminent ? Color.clear : Color.black.opacity(0.18),
                        lineWidth: 1
                    )
            )
            .shadow(color: Color.black.opacity(0.06), radius: 1, x: 0, y: 1)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
    }
}
```

---

## 2. Yosemite Frosted Vibrancy Sidebar (`YosemiteVibrancySidebar`)

```swift
public struct YosemiteVibrancySidebar<Content: View>: View {
    public var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        ZStack {
            VisualEffectBlur(material: .sidebar, blendingMode: .behindWindow)

            content()
        }
    }
}

// AppKit Bridge for authentic NSVisualEffectView vibrancy
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .followsWindowActiveState
    }
}
```
