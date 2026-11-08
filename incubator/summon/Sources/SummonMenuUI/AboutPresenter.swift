import AppKit
import SummonCore

/// The one About surface: AppKit's standard About panel fed immutable `BuildInfo`. Settings → General → About Summon
/// and the app menu's About command both call `show()`. The panel is a singleton owned by AppKit, so opening it again
/// raises the same window instead of making another; nothing here touches the network or the updater.
@MainActor
public enum AboutPresenter {
    public static func show(_ build: BuildInfo = .current) {
        // An accessory app has no app menu or focus; activate so the panel takes keyboard and VoiceOver focus.
        NSApp.activate()
        NSApp.orderFrontStandardAboutPanel(options: options(for: build))
    }

    private static var launchObserver: NSObjectProtocol?

    /// Visual QA hook: `SummonMenu --show-about` opens the real panel once, when launch finishes. One-shot: the
    /// observer removes itself after firing and a second call while pending registers nothing.
    public static func showIfAsked() {
        guard CommandLine.arguments.contains("--show-about"), launchObserver == nil else { return }
        launchObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                if let token = launchObserver { NotificationCenter.default.removeObserver(token) }
                show()
            }
        }
    }

    static func options(for build: BuildInfo) -> [NSApplication.AboutPanelOptionKey: Any] {
        [.applicationName: "Summon",
         .applicationVersion: build.marketingVersion,
         .version: build.buildNumber,
         .credits: credits(for: build)]
    }

    /// Selectable, labeled text so every field is read by VoiceOver and copyable.
    static func credits(for build: BuildInfo) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let text = build.fields.dropFirst(2).map { "\($0.label): \($0.value)" }.joined(separator: "\n")
        return NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph])
    }
}
