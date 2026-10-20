import AppKit
import SummonCore
import SwiftUI

/// A borderless panel that accepts key events for keyboard shortcuts without activating the app.
private final class CrashAlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A native pop-up alert that appears when an app crashes or hangs on macOS.
/// Offers an immediate "✨ Diagnose with AI" action to hand the crash facts to the default agent.
public struct CrashAlertView: View {
    let report: CrashReport
    let onDiagnose: () -> Void
    let onMute: () -> Void
    let onDismiss: () -> Void

    public init(
        report: CrashReport,
        onDiagnose: @escaping () -> Void,
        onMute: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.report = report
        self.onDiagnose = onDiagnose
        self.onMute = onMute
        self.onDismiss = onDismiss
    }

    private var iconName: String {
        switch report.kind {
        case .crash: return "exclamationmark.triangle.fill"
        case .hang: return "hourglass.badge.exclamationmark"
        case .panic: return "exclamationmark.shield.fill"
        case .memory: return "memorychip.fill"
        case .other: return "doc.text.fill"
        }
    }

    private var iconColor: Color {
        switch report.kind {
        case .crash: return .red
        case .hang: return .orange
        case .panic: return .purple
        case .memory: return .yellow
        case .other: return .secondary
        }
    }

    private var titleText: String {
        switch report.kind {
        case .crash: return "\(report.program) crashed"
        case .hang: return "\(report.program) stopped responding"
        case .panic: return "Kernel panic detected"
        case .memory: return "macOS stopped \(report.program)"
        case .other: return "\(report.program) diagnostic report"
        }
    }

    private var detailText: String {
        if let exc = report.exceptionType {
            if let sig = report.signal {
                return "\(exc) (\(sig))"
            }
            return exc
        }
        if report.kind == .hang {
            return "Application hung and became unresponsive"
        }
        if let reason = report.memoryKillReason {
            return CrashReport.memoryReason(reason)
        }
        return "A diagnostic report was recorded on your Mac"
    }

    private var summonLogo: some View {
        Group {
            if let image = Bundle.main.image(forResource: "app-icon") ?? NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Circle().fill(Color.accentColor))
            }
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Top Bar: Summon Brand + Dismiss (X)
            HStack(spacing: 6) {
                summonLogo
                    .frame(width: 16, height: 16)
                    .clipShape(Circle())

                Text("SUMMON DIAGNOSTIC")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.5)

                Spacer()

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .padding(5)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Dismiss (Esc)")
            }

            // Main Content: Summon Logo with Crash Indicator Badge + Text
            HStack(alignment: .top, spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    summonLogo
                        .frame(width: 42, height: 42)
                        .clipShape(Circle())
                        .shadow(color: .black.opacity(0.2), radius: 3, y: 1)

                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 17, height: 17)
                        .background(Circle().fill(iconColor))
                        .offset(x: 3, y: 3)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(titleText)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(detailText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            // Top frame snippet if available
            if let frame = report.topFrames.first, !frame.isEmpty {
                Text(frame)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
                    .lineLimit(1)
            }

            Divider()

            // Actions footer
            HStack(spacing: 10) {
                Button("Mute App", action: onMute)
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .help("Mute \(report.program) from future alerts")

                Spacer()

                Button("Dismiss", action: onDismiss)
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.bordered)
                    .controlSize(.regular)

                Button(action: onDiagnose) {
                    HStack(spacing: 5) {
                        Image(systemName: "sparkles")
                        Text("Diagnose with AI")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

/// Controller that presents the non-activating floating crash alert panel.
@MainActor
public final class CrashAlertController {
    private let model: SummonModel
    private var panel: NSPanel?
    private var autoDismissTask: Task<Void, Never>?
    /// Runs right before the alert orders front and takes key: the menu bar panel closes first (panel spec D12).
    public var onWillPresent: (() -> Void)?

    public init(model: SummonModel) {
        self.model = model
    }

    public func present(_ report: CrashReport) {
        // Skip routine memory kills as defined by CrashReport
        guard !report.isRoutine else { return }

        autoDismissTask?.cancel()

        let panel = self.panel ?? makePanel()
        self.panel = panel

        let view = CrashAlertView(
            report: report,
            onDiagnose: { [weak self] in
                self?.dismiss()
                self?.model.diagnose(file: report.file)
            },
            onMute: { [weak self] in
                self?.dismiss()
                self?.model.mute(program: report.program)
            },
            onDismiss: { [weak self] in
                self?.dismiss()
            }
        )

        panel.contentView = NSHostingView(rootView: view)

        // Position on active screen top-right (24pt margin)
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            panel.layoutIfNeeded()
            let size = panel.frame.size
            let origin = NSPoint(
                x: visible.maxX - size.width - 24,
                y: visible.maxY - size.height - 24
            )
            panel.setFrameOrigin(origin)
        }

        // D12: only one Summon panel is key at a time, and the crash alert wins.
        onWillPresent?()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }

        // Auto-dismiss after 30 seconds if untouched
        autoDismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    public func dismiss() {
        autoDismissTask?.cancel()
        autoDismissTask = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0
        }, completionHandler: { [panel] in
            MainActor.assumeIsolated {
                panel.orderOut(nil)
            }
        })
    }

    private func makePanel() -> NSPanel {
        let panel = CrashAlertPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 180),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = PanelConfig.level
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        return panel
    }
}
