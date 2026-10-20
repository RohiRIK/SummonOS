# Linen SwiftUI Components

SwiftUI components interpreting OS X 10.7–10.9 physical skeuomorphic materials.

Copy the Swift blocks in this file together into a macOS 15+ target. Preserve native
window chrome, focus, keyboard activation, and accessible labels; these are content
components, not replacements for AppKit window management. Colors approximate an era.

## 1. Woven Dark Linen Background (`DarkLinenView`)

```swift
import SwiftUI

public struct DarkLinenView: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            // Base dark charcoal
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.17)))

            // Horizontal & vertical cross-hatch fabric weave
            let step: CGFloat = 3
            for y in stride(from: 0, to: size.height, by: step) {
                for x in stride(from: 0, to: size.width, by: step) {
                    let isWeave = (Int(x / step) + Int(y / step)) % 2 == 0
                    let alpha = isWeave ? 0.08 : 0.02
                    let color = Color.white.opacity(alpha)
                    context.fill(Path(CGRect(x: x, y: y, width: step - 0.5, height: step - 0.5)), with: .color(color))
                }
            }
        }
    }
}
```

---

## 2. Stitched Leather Header (`StitchedLeatherBar`)

```swift
public struct StitchedLeatherBar: View {
    public var title: String
    public var subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(spacing: 4) {
            // Top highlight
            Rectangle().fill(Color.white.opacity(0.15)).frame(height: 1)

            // Upper stitch line
            StitchLine()

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .serif))
                        .foregroundStyle(Color(red: 0.95, green: 0.90, blue: 0.85))
                        .shadow(color: Color.black.opacity(0.8), radius: 1, x: 0, y: -1)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, design: .serif))
                            .foregroundStyle(Color(red: 0.80, green: 0.72, blue: 0.65))
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            // Lower stitch line
            StitchLine()

            // Bottom shadow
            Rectangle().fill(Color.black.opacity(0.4)).frame(height: 1.5)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.42, green: 0.22, blue: 0.14),
                    Color(red: 0.28, green: 0.14, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

struct StitchLine: View {
    var body: some View {
        Canvas { context, size in
            var line = Path()
            line.move(to: CGPoint(x: 0, y: size.height / 2))
            line.addLine(to: CGPoint(x: size.width, y: size.height / 2))
            context.stroke(line, with: .color(Color(white: 0.85).opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
        }
        .frame(height: 2)
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }
}
```

---

## 3. Yellow Legal Pad Stationery (`NotesPaperView`)

```swift
public struct NotesPaperView<Content: View>: View {
    public var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            // Yellow legal pad paper background
            Color(red: 0.99, green: 0.96, blue: 0.78)

            // Ruled horizontal lines & red margin
            Canvas { context, size in
                // Red vertical margin rule
                let marginX: CGFloat = 46
                context.stroke(Path { p in
                    p.move(to: CGPoint(x: marginX, y: 0))
                    p.addLine(to: CGPoint(x: marginX, y: size.height))
                }, with: .color(Color(red: 0.92, green: 0.45, blue: 0.45).opacity(0.7)), lineWidth: 1.5)

                // Pale blue horizontal ruled lines
                let lineSpacing: CGFloat = 24
                for y in stride(from: 40, to: size.height, by: lineSpacing) {
                    context.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }, with: .color(Color(red: 0.65, green: 0.78, blue: 0.90).opacity(0.6)), lineWidth: 1)
                }
            }

            // Torn paper top header strip
            VStack {
                Rectangle()
                    .fill(Color(red: 0.55, green: 0.35, blue: 0.15))
                    .frame(height: 12)
                Spacer()
            }

            content()
                .foregroundStyle(Color.black)
                .padding(.leading, 56)
                .padding(.top, 28)
                .padding(.trailing, 20)
        }
    }
}
```
