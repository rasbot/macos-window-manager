import AppKit
import ColorSync
import CoreGraphics

struct DisplayDescriptor: Equatable {
    let id: String
    let name: String

    init(screen: NSScreen) {
        name = screen.localizedName

        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            id = "screen-\(screen.localizedName)"
            return
        }

        let displayID = CGDirectDisplayID(number.uint32Value)
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID).takeRetainedValue()
        if let uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid) {
            id = uuidString as String
        } else {
            id = "display-\(displayID)"
        }
    }
}
