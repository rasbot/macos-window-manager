import ApplicationServices
import Foundation

/// The result of asking a window to occupy a zone.
///
/// Applications with a minimum window size accept the move but refuse the full
/// resize, so the achieved frame is reported back rather than assumed.
struct WindowPlacement {
    let requested: CGRect
    let achieved: CGRect

    /// Whether the window ended up close enough to the zone to look docked.
    var isExact: Bool {
        abs(requested.origin.x - achieved.origin.x) <= 2
            && abs(requested.origin.y - achieved.origin.y) <= 2
            && abs(requested.size.width - achieved.size.width) <= 2
            && abs(requested.size.height - achieved.size.height) <= 2
    }

    /// The window moved but could not shrink to the zone.
    var isConstrainedBySize: Bool {
        !isExact
            && (achieved.size.width > requested.size.width + 2
                || achieved.size.height > requested.size.height + 2)
    }
}

final class AccessibleWindow {
    let element: AXUIElement

    init(element: AXUIElement) {
        self.element = element
    }

    var frame: CGRect? {
        guard let position = pointValue(for: kAXPositionAttribute),
              let size = sizeValue(for: kAXSizeAttribute) else {
            return nil
        }

        return CGRect(origin: position, size: size)
    }

    var title: String? {
        attributeValue(for: kAXTitleAttribute) as? String
    }

    var isMovableAndResizable: Bool {
        isAttributeSettable(kAXPositionAttribute) && isAttributeSettable(kAXSizeAttribute)
    }

    var isMinimized: Bool {
        attributeValue(for: kAXMinimizedAttribute) as? Bool ?? false
    }

    /// Native full-screen windows own their whole Space and ignore position and
    /// size changes, so docking them would silently do nothing.
    var isFullScreen: Bool {
        attributeValue(for: "AXFullScreen") as? Bool ?? false
    }

    /// Whether this window can meaningfully be docked into a zone.
    var isDockable: Bool {
        isMovableAndResizable && !isMinimized && !isFullScreen
    }

    /// Moves and resizes the window, then reports what actually happened.
    ///
    /// Position and size are applied in three steps because applications react to
    /// the two attributes independently: some clamp a resize against the screen the
    /// window currently occupies, and some re-anchor the window while resizing.
    /// Setting position, then size, then position again converges for both.
    @discardableResult
    func setFrame(_ frame: CGRect) -> WindowPlacement? {
        guard isMovableAndResizable else { return nil }

        setPosition(frame.origin)
        setSize(frame.size)
        setPosition(frame.origin)

        guard let achieved = self.frame else { return nil }
        return WindowPlacement(requested: frame, achieved: achieved)
    }

    @discardableResult
    private func setPosition(_ position: CGPoint) -> Bool {
        var position = position
        guard let value = AXValueCreate(.cgPoint, &position) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    @discardableResult
    private func setSize(_ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }

    private func pointValue(for attribute: String) -> CGPoint? {
        guard let value = attributeValue(for: attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var point = CGPoint.zero
        guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else {
            return nil
        }
        return point
    }

    private func sizeValue(for attribute: String) -> CGSize? {
        guard let value = attributeValue(for: attribute), CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        var size = CGSize.zero
        guard AXValueGetValue(value as! AXValue, .cgSize, &size) else {
            return nil
        }
        return size
    }

    private func attributeValue(for attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            attribute as CFString,
            &value
        )
        return result == .success ? value : nil
    }

    private func isAttributeSettable(_ attribute: String) -> Bool {
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(
            element,
            attribute as CFString,
            &settable
        )
        return result == .success && settable.boolValue
    }
}

enum AccessibleWindowResolver {
    static func window(at quartzPoint: CGPoint) -> AccessibleWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var hitElement: AXUIElement?

        guard AXUIElementCopyElementAtPosition(
            systemWide,
            Float(quartzPoint.x),
            Float(quartzPoint.y),
            &hitElement
        ) == .success, var current = hitElement else {
            return focusedWindow()
        }

        for _ in 0..<12 {
            if role(of: current) == kAXWindowRole as String {
                let window = AccessibleWindow(element: current)
                return window.isDockable ? window : nil
            }

            guard let parent = parent(of: current) else {
                break
            }
            current = parent
        }

        return focusedWindow()
    }

    /// The frontmost window of the frontmost application. Used by the keyboard
    /// shortcuts, which have no pointer location to hit-test against.
    static func focusedWindow() -> AccessibleWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var appValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &appValue
        ) == .success, let app = appValue else {
            return nil
        }

        var windowValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedWindowAttribute as CFString,
            &windowValue
        ) == .success, let windowElement = windowValue else {
            return nil
        }

        let window = AccessibleWindow(element: windowElement as! AXUIElement)
        return window.isDockable ? window : nil
    }

    private static func role(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXRoleAttribute as CFString,
            &value
        ) == .success else {
            return nil
        }
        return value as? String
    }

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &value
        ) == .success, let value else {
            return nil
        }
        return (value as! AXUIElement)
    }
}
