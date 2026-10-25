import CoreGraphics
import Foundation

/// Where a floating HUD rests: one of the four corners of the screen's visible frame, like Picture in Picture.
public enum Corner: String, CaseIterable, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .topLeft: "Top Left"
        case .topRight: "Top Right"
        case .bottomLeft: "Bottom Left"
        case .bottomRight: "Bottom Right"
        }
    }
}

/// Snapping math for a thrown HUD, in screen coordinates (origin bottom-left, like AppKit).
public enum CornerSnap {
    /// How far a throw carries: the release velocity (points per second) times this many seconds.
    public static let carry: TimeInterval = 0.18

    /// The corner a window released at `frame` with `velocity` comes to rest in: where its center would land
    /// after the throw, nearest corner wins. Pass a zero velocity to snap without the throw (Reduce Motion).
    public static func corner(for frame: CGRect, velocity: CGVector, in visible: CGRect) -> Corner {
        let landing = CGPoint(x: frame.midX + velocity.dx * carry, y: frame.midY + velocity.dy * carry)
        let right = landing.x >= visible.midX
        let top = landing.y >= visible.midY
        switch (top, right) {
        case (true, false): return .topLeft
        case (true, true): return .topRight
        case (false, false): return .bottomLeft
        case (false, true): return .bottomRight
        }
    }

    /// The frame of a window of `size` resting in `corner`, `margin` points inside the visible frame.
    public static func frame(of size: CGSize, in corner: Corner, of visible: CGRect, margin: CGFloat = 16) -> CGRect {
        let x = corner == .topLeft || corner == .bottomLeft ? visible.minX + margin : visible.maxX - margin - size.width
        let y = corner == .bottomLeft || corner == .bottomRight ? visible.minY + margin : visible.maxY - margin - size.height
        return CGRect(origin: CGPoint(x: x.rounded(), y: y.rounded()), size: size)
    }
}

/// The HUD's size setting: a scale for its text and controls.
public enum HUDSize: String, CaseIterable, Codable, Sendable {
    case small, medium, large

    public var title: String { rawValue.capitalized }

    public var scale: CGFloat {
        switch self {
        case .small: 0.85
        case .medium: 1
        case .large: 1.3
        }
    }
}
