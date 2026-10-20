# Aqua SwiftUI Components

SwiftUI components interpreting the Mac OS X Aqua visual language.

Copy the Swift blocks in this file together into a macOS 15+ target. Preserve native
window chrome, focus, keyboard activation, and accessible labels; these are content
components, not replacements for AppKit window management. Colors approximate an era.

## 1. Aqua Jelly Pill Button (`AquaButton`)

```swift
import SwiftUI

public enum AquaVariant {
    case blue
    case graphite
    case red
    case green

    var topColor: Color {
        switch self {
        case .blue: return Color(red: 0.35, green: 0.68, blue: 0.98)
        case .graphite: return Color(red: 0.60, green: 0.62, blue: 0.65)
        case .red: return Color(red: 0.95, green: 0.40, blue: 0.35)
        case .green: return Color(red: 0.35, green: 0.85, blue: 0.45)
        }
    }

    var bottomColor: Color {
        switch self {
        case .blue: return Color(red: 0.08, green: 0.38, blue: 0.82)
        case .graphite: return Color(red: 0.32, green: 0.34, blue: 0.37)
        case .red: return Color(red: 0.75, green: 0.15, blue: 0.12)
        case .green: return Color(red: 0.12, green: 0.55, blue: 0.20)
        }
    }

    var borderColor: Color {
        switch self {
        case .blue: return Color(red: 0.05, green: 0.25, blue: 0.60)
        case .graphite: return Color(red: 0.25, green: 0.26, blue: 0.28)
        case .red: return Color(red: 0.55, green: 0.10, blue: 0.08)
        case .green: return Color(red: 0.08, green: 0.40, blue: 0.15)
        }
    }
}

public struct AquaButtonStyle: ButtonStyle {
    public var variant: AquaVariant = .blue
    public var isDefault: Bool = false

    public init(variant: AquaVariant = .blue, isDefault: Bool = false) {
        self.variant = variant
        self.isDefault = isDefault
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold, design: .default))
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(0.4), radius: 1, x: 0, y: 1)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    // Base gradient
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: configuration.isPressed
                                    ? [variant.bottomColor, variant.topColor]
                                    : [variant.topColor, variant.bottomColor],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )

                    // Gloss reflection (top highlight oval)
                    VStack {
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.75), Color.white.opacity(0.15)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(height: 11)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                        Spacer()
                    }

                    // Outer border
                    Capsule()
                        .stroke(variant.borderColor, lineWidth: 1)

                    // Pulsing default glow ring if default
                    if isDefault {
                        Capsule()
                            .stroke(variant.topColor.opacity(0.6), lineWidth: 2)
                            .blur(radius: 1.5)
                    }
                }
            )
            .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1.5)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
    }
}
```

---

## 2. Candy-Stripe Animated Progress Bar (`AquaProgressBar`)

```swift
public struct AquaProgressBar: View {
    public var value: Double // 0.0 ... 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var fraction: Double { value.isFinite ? max(0, min(1, value)) : 0 }

    public init(value: Double) {
        self.value = value
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(white: 0.88))
                    .overlay(Capsule().stroke(Color(white: 0.65), lineWidth: 1))

                TimelineView(.animation(minimumInterval: 1.0 / 30,
                                        paused: reduceMotion || fraction <= 0 || fraction >= 1)) { timeline in
                    let phase: CGFloat = reduceMotion ? 0 : CGFloat(
                        timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
                    ) * 24
                    ZStack(alignment: .top) {
                        CandyStripeShape(phase: phase)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.15, green: 0.55, blue: 0.95),
                                         Color(red: 0.05, green: 0.35, blue: 0.80)],
                                startPoint: .top, endPoint: .bottom
                            ))

                        Capsule()
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.8), Color.white.opacity(0.1)],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .frame(height: geometry.size.height * 0.45)
                            .padding(.horizontal, 2)
                            .padding(.top, 1)
                    }
                    .frame(width: max(0, geometry.size.width) * fraction)
                    .clipShape(Capsule())
                }
            }
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Progress")
        .accessibilityValue(fraction.formatted(.percent.precision(.fractionLength(0))))
    }
}

struct CandyStripeShape: Shape {
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let stripeWidth: CGFloat = 12
        let total = rect.width + rect.height + stripeWidth * 2

        var x = -rect.height + (phase.truncatingRemainder(dividingBy: stripeWidth * 2))
        while x < total {
            path.move(to: CGPoint(x: x, y: rect.height))
            path.addLine(to: CGPoint(x: x + rect.height, y: 0))
            path.addLine(to: CGPoint(x: x + rect.height + stripeWidth, y: 0))
            path.addLine(to: CGPoint(x: x + stripeWidth, y: rect.height))
            path.closeSubpath()
            x += stripeWidth * 2
        }
        return path
    }
}
```

---

## 3. Aqua-inspired Pinstripes Background (`AquaPinstripeView`)

```swift
public struct AquaPinstripeView: View {
    public init() {}

    public var body: some View {
        Canvas { context, size in
            let stripeWidth: CGFloat = 2
            var x: CGFloat = 0
            var alternate = false
            while x < size.width {
                let rect = CGRect(x: x, y: 0, width: stripeWidth, height: size.height)
                let color = alternate ? Color(white: 0.94) : Color(white: 0.98)
                context.fill(Path(rect), with: .color(color))
                x += stripeWidth
                alternate.toggle()
            }
        }
    }
}
```

---

## 4. Brushed Metal Texture (`AquaBrushedMetalView`)

```swift
public struct AquaBrushedMetalView: View {
    public init() {}

    public var body: some View {
        LinearGradient(
            stops: [
                .init(color: Color(white: 0.82), location: 0.0),
                .init(color: Color(white: 0.76), location: 0.05),
                .init(color: Color(white: 0.78), location: 0.5),
                .init(color: Color(white: 0.72), location: 0.95),
                .init(color: Color(white: 0.65), location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(
            // Subtle horizontal striations
            Canvas { context, size in
                for y in stride(from: 0, to: size.height, by: 3) {
                    let rect = CGRect(x: 0, y: y, width: size.width, height: 1)
                    let opacity = (y.truncatingRemainder(dividingBy: 6) == 0) ? 0.08 : 0.03
                    context.fill(Path(rect), with: .color(Color.black.opacity(opacity)))
                }
            }
        )
    }
}
```
