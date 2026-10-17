import AppKit
import SwiftUI

/// The menu bar icon: Summon's mark as a template image (bundled by scripts/bundle.sh),
/// falling back to an SF Symbol when running unbundled from `swift run`.
public struct MenuBarLabel: View {
    public init() {}

    public var body: some View {
        if let image = Self.templateImage {
            Image(nsImage: image)
        } else {
            Image(systemName: "sparkles")
        }
    }

    @MainActor private static let templateImage: NSImage? = {
        // image(forResource:) picks up menubar-icon@2x.png on Retina displays.
        guard let image = Bundle.main.image(forResource: "menubar-icon") else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}
