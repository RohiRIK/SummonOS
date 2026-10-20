# Layers and Materials

Liquid Glass forms a navigation and control layer above content. Prefer system
containers so appearance and accessibility adapt with macOS. See Apple's
[Adopting Liquid Glass](https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass)
and [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/).

Use standard content surfaces for lists, forms, and text. Avoid stacking glass on
glass; readability matters more than maximizing translucency. macOS 15 uses
standard materials, while the glass APIs below require macOS 26+.

## A complete window scene

This sample compiles independently with the other Swift blocks in this file.
The hidden title retains native traffic lights. Keep standard toolbar behavior
unless the content design specifically needs a transparent toolbar.

```swift
import SwiftUI

struct ModernActivityScene: Scene {
    var body: some Scene {
        Window("Activity", id: "activity") {
            List(["Ready", "Recent activity"], id: \.self) { item in
                Text(item)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .containerBackground(.thinMaterial, for: .window)
            .frame(minWidth: 420, minHeight: 280)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 460)
    }
}
```

Use `.scrollContentBackground(.hidden)` on a List or Form only when the window
material is intended to show through. It is not a universal requirement for every
ScrollView, and an opaque content pane can be appropriate.

## A gated control modifier

Keep this on a floating control rather than every content card. The capsule shape
is explicit in both paths so the fallback has the same geometry.

```swift
extension View {
    @ViewBuilder
    func modernGlassControl() -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.thinMaterial, in: Capsule())
        }
    }
}
```

Check Reduce Transparency and Increase Contrast using system accessibility
settings; native materials adapt, but foreground contrast and focus still need
visual verification. Do not hard-code an activation policy for all accessory
apps: use the existing app's window coordinator and verify it becomes key.
