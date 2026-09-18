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

public extension ScreenCoordinateConverter {
    /// The inverse of `accessibilityRect(fromAppKit:)`, used to find which screen
    /// holds a window whose frame came from the Accessibility API.
    func appKitRect(fromAccessibility rect: CGRect) -> CGRect {
        CGRect(
            origin: CGPoint(
                x: rect.origin.x,
                y: primaryScreenTop - (rect.origin.y + rect.size.height)
            ),
            size: rect.size
        )
    }
}
