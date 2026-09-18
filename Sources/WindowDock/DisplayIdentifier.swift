import AppKit
import ColorSync
import CoreGraphics

struct DisplayDescriptor: Equatable {
    let id: String
    let name: String

    init(screen: NSScreen) {
        name = screen.localizedName

        guard let displayID = Self.displayID(of: screen) else {
            id = "screen-\(screen.localizedName)"
            return
        }

        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
        if let uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid) {
            id = uuidString as String
        } else {
            id = "display-\(displayID)"
        }
    }

    /// Descriptors are looked up once per display rather than rebuilt per event.
    ///
    /// Resolving the persistent UUID allocates through CoreGraphics, and the drag
    /// monitor needs a descriptor for every mouse-moved event while zones are shown.
    static func cached(for screen: NSScreen) -> DisplayDescriptor {
        guard let displayID = displayID(of: screen) else {
            return DisplayDescriptor(screen: screen)
        }
        if let cached = cache[displayID] {
            return cached
        }

        let descriptor = DisplayDescriptor(screen: screen)
        cache[displayID] = descriptor
        return descriptor
    }

    /// Called when displays are attached, removed, or rearranged.
    static func invalidateCache() {
        cache.removeAll()
    }

    private static var cache: [CGDirectDisplayID: DisplayDescriptor] = [:]

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        return CGDirectDisplayID(number.uint32Value)
    }
}
