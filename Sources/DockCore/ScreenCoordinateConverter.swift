import CoreGraphics

/// Converts between AppKit's bottom-left global coordinates and the
/// top-left global coordinates used by Quartz events and Accessibility.
public struct ScreenCoordinateConverter: Sendable {
    public let primaryScreenTop: CGFloat

    public init(primaryScreenTop: CGFloat) {
        self.primaryScreenTop = primaryScreenTop
    }

    public func appKitPoint(fromQuartz point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: primaryScreenTop - point.y)
    }

    public func accessibilityRect(fromAppKit rect: CGRect) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: rect.origin.x,
                y: primaryScreenTop - (rect.origin.y + rect.size.height)
            ),
            size: rect.size
        )
    }
}
