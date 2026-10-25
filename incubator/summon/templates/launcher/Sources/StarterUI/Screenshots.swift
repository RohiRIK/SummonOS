import AppKit
import SwiftUI

/// `Starter --screenshot <folder>`: draws the launcher in light and dark into PNGs and exits, so `summon project shots`
/// gets clean pictures without a hotkey or Screen Recording.
public enum Screenshots {
    @MainActor
    public static func runIfAsked() {
        let arguments = CommandLine.arguments
        guard let flag = arguments.firstIndex(of: "--screenshot"), flag + 1 < arguments.count else { return }
        let folder = URL(fileURLWithPath: arguments[flag + 1], isDirectory: true)
        do {
            try write(to: folder)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("screenshot: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    public static func write(to folder: URL) throws {
        // `summon project shots` looks for panel-light.png and panel-dark.png.
        try render(name: "panel", to: folder) {
            LauncherView(model: .preview)
                .padding(20)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        try render(name: "settings", to: folder) {
            SettingsView()
        }
    }

    /// Writes `<name>-light.png` and `<name>-dark.png`.
    @MainActor
    static func render<V: View>(name: String, to folder: URL, @ViewBuilder _ view: () -> V) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (look, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            // An off-screen window draws real AppKit controls (ImageRenderer shows them as placeholders), with no
            // Screen Recording permission and no visible display needed.
            let host = NSHostingView(rootView: view())
            host.appearance = NSAppearance(named: appearance)
            host.frame.size = host.fittingSize
            let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: host.frame.size),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.backgroundColor = .clear
            window.isOpaque = false
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            host.display()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: folder.appendingPathComponent("\(name)-\(look).png"))
        }
    }
}
