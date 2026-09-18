import ApplicationServices
import Foundation

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

    var isMovableAndResizable: Bool {
        isAttributeSettable(kAXPositionAttribute) && isAttributeSettable(kAXSizeAttribute)
    }

    func setFrame(_ frame: CGRect) -> Bool {
        var position = frame.origin
        var size = frame.size

        guard let positionValue = AXValueCreate(.cgPoint, &position),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            return false
        }

        let positionResult = AXUIElementSetAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            positionValue
        )
        let sizeResult = AXUIElementSetAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            sizeValue
        )

        return positionResult == .success && sizeResult == .success
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
                return window.isMovableAndResizable ? window : nil
            }

            guard let parent = parent(of: current) else {
                break
            }
            current = parent
        }

        return focusedWindow()
    }

    private static func focusedWindow() -> AccessibleWindow? {
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
        return window.isMovableAndResizable ? window : nil
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
