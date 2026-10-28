import StarterCore
import SwiftUI

/// The HUD: a dark glass pill with a state mark, the elapsed time in monospaced digits (so it never jitters) and
/// two or three icon buttons. Start/Pause is always visible; Reset and Hide fade to 30% until the pointer is over
/// the HUD. Drag it anywhere and let go: it glides to the nearest corner. Right-click for opacity, size and corner.
public struct HUDView: View {
    private let model: StarterModel
    private let hide: @MainActor () -> Void
    @AppStorage(StarterSettings.sizeKey) private var size = HUDSize.medium
    @State private var hovering = false

    public init(model: StarterModel, hide: @escaping @MainActor () -> Void) {
        self.model = model
        self.hide = hide
    }

    public var body: some View {
        HStack(spacing: 10 * size.scale) {
            StateMark(state: model.stopwatch.state, scale: size.scale)
            ElapsedTime(stopwatch: model.stopwatch, isVisible: model.isHUDVisible, scale: size.scale)
            Spacer(minLength: 4)
            HUDButton(title: model.stopwatch.state == .running ? "Pause" : "Start",
                      symbol: model.stopwatch.state == .running ? "pause.fill" : "play.fill",
                      scale: size.scale, action: model.toggle)
            HUDButton(title: "Reset", symbol: "arrow.counterclockwise", scale: size.scale, action: model.reset)
                .disabled(model.stopwatch.state == .idle)
                .opacity(hovering ? 1 : 0.3)
            HUDButton(title: "Hide", symbol: "xmark", scale: size.scale, action: hide)
                .opacity(hovering ? 1 : 0.3)
        }
        .padding(.leading, 14 * size.scale)
        .padding(.trailing, 8 * size.scale)
        .frame(width: 210 * size.scale, height: 44 * size.scale)
        .background { HUDDragArea { velocity in model.dragEnded(velocity) } }
        .hudBackground(state: model.stopwatch.state)
        .environment(\.colorScheme, .dark) // HUDs are dark in both modes (HIG Panels)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stopwatch")
    }
}

/// The state, as a shape and a color (never color alone): a red dot while running, an amber pause mark, a gray
/// ring when idle.
struct StateMark: View {
    let state: Stopwatch.State
    let scale: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11 * scale, weight: .bold))
            .foregroundStyle(color)
            .accessibilityLabel(label)
    }

    private var symbol: String {
        switch state {
        case .running: "circle.fill"
        case .paused: "pause.circle.fill"
        case .idle: "circle"
        }
    }

    private var color: Color {
        switch state {
        case .running: .red
        case .paused: .orange
        case .idle: .secondary
        }
    }

    private var label: String {
        switch state {
        case .running: "Running"
        case .paused: "Paused"
        case .idle: "Stopped"
        }
    }
}

/// Redraws once a second while running and on screen, and not at all otherwise: a hidden HUD costs no wakeups.
struct ElapsedTime: View {
    let stopwatch: Stopwatch
    let isVisible: Bool
    let scale: CGFloat

    var body: some View {
        if stopwatch.state == .running && isVisible {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                label(at: context.date)
            }
        } else {
            label(at: Date())
        }
    }

    private func label(at date: Date) -> some View {
        Text(Stopwatch.format(stopwatch.elapsed(at: date)))
            .font(.system(size: 14 * scale, weight: .semibold).monospacedDigit())
            .contentTransition(.numericText())
    }
}

struct HUDButton: View {
    let title: String
    let symbol: String
    let scale: CGFloat
    let action: @MainActor () -> Void

    var body: some View {
        Button(title, systemImage: symbol, action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 12 * scale, weight: .semibold))
            .frame(width: 24 * scale, height: 24 * scale)
            .contentShape(.rect)
            .help(title)
    }
}

extension View {
    /// Dark glass: Liquid Glass on macOS 26, the HUD material before; a 1 px light border so it reads over busy
    /// windows, red while running and amber while paused.
    @ViewBuilder
    func hudBackground(state: Stopwatch.State) -> some View {
        let shape = Capsule()
        Group {
            if #available(macOS 26, *) {
                glassEffect(.regular, in: shape)
            } else {
                background(.ultraThickMaterial, in: shape)
            }
        }
        .overlay {
            shape.strokeBorder(border(state), lineWidth: state == .idle ? 1 : 1.5)
        }
        .clipShape(shape)
    }

    private func border(_ state: Stopwatch.State) -> Color {
        switch state {
        case .running: .red.opacity(0.7)
        case .paused: .orange.opacity(0.7)
        case .idle: .white.opacity(0.15)
        }
    }
}

#Preview("Running") {
    HUDView(model: .preview, hide: {}).padding()
}

#Preview("Idle") {
    HUDView(model: StarterModel(), hide: {}).padding()
}
