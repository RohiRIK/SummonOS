import CoreGraphics

/// Where the notch panel goes on one screen, in screen coordinates (origin bottom-left, like AppKit).
/// Apple has no notch API: `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` (macOS 12) are the menu bar
/// on either side of the camera housing, so the housing is what lies between them. A screen without a housing
/// (an external display, an older Mac) has neither, and the panel falls back to a small pill under the menu bar.
public struct NotchGeometry: Equatable, Sendable {
    /// The camera housing, or the fallback pill's resting frame.
    public let closed: CGRect
    public let hasNotch: Bool
    private let screen: CGRect

    public static let fallbackSize = CGSize(width: 180, height: 6)

    public init(screen: CGRect, topLeftArea: CGRect?, topRightArea: CGRect?, menuBarHeight: CGFloat) {
        self.screen = screen
        if let left = topLeftArea, let right = topRightArea, right.minX > left.maxX {
            hasNotch = true
            let height = max(left.height, right.height)
            closed = CGRect(x: left.maxX, y: screen.maxY - height, width: right.minX - left.maxX, height: height)
        } else {
            hasNotch = false
            let size = NotchGeometry.fallbackSize
            closed = CGRect(x: (screen.midX - size.width / 2).rounded(), y: screen.maxY - menuBarHeight - size.height,
                            width: size.width, height: size.height)
        }
    }

    /// The open panel: at least `size`, at least as wide as the housing, centered on it, hanging from the top
    /// edge (or from under the menu bar on a screen without a housing), kept inside the screen.
    public func open(_ size: CGSize) -> CGRect {
        let width = min(max(size.width, closed.width), screen.width)
        let top = hasNotch ? screen.maxY : closed.maxY
        var x = (closed.midX - width / 2).rounded()
        x = min(max(x, screen.minX), screen.maxX - width)
        return CGRect(x: x, y: top - size.height, width: width, height: size.height)
    }
}
