import AppKit
import ApplicationServices
import DockCore

final class WindowDragMonitor {
    var isEnabled = true
    var onStatusChange: ((String) -> Void)?
    let profileStore = ProfileStore()

    private let overlay = ZoneOverlayController()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var candidateWindow: AccessibleWindow?
    private var initialFrame: CGRect?
    private var selectedZoneIndex: Int?
    private var isDockingDrag = false

    deinit {
        stop()
    }

    func start() -> Bool {
        guard eventTap == nil else { return true }

        let types: [CGEventType] = [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .flagsChanged]
        let mask = types.reduce(CGEventMask(0)) { partial, type in
            partial | (CGEventMask(1) << type.rawValue)
        }

        let callback: CGEventTapCallBack = { _, eventType, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<WindowDragMonitor>.fromOpaque(userInfo).takeUnretainedValue()

            if eventType == .tapDisabledByTimeout || eventType == .tapDisabledByUserInput {
                if let tap = monitor.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let location = event.location
            let flags = event.flags
            DispatchQueue.main.async {
                monitor.handle(type: eventType, quartzPoint: location, flags: flags)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            onStatusChange?("Unable to monitor drags")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        onStatusChange?("Ready — hold Shift while dragging")
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        eventTap = nil
        runLoopSource = nil
        resetDrag()
    }

    private func handle(type: CGEventType, quartzPoint: CGPoint, flags: CGEventFlags) {
        guard isEnabled else {
            resetDrag()
            return
        }

        switch type {
        case .leftMouseDown:
            guard AccessibilityPermission.isGranted else {
                onStatusChange?("Accessibility permission required")
                return
            }
            candidateWindow = AccessibleWindowResolver.window(at: quartzPoint)
            initialFrame = candidateWindow?.frame
            selectedZoneIndex = nil
            isDockingDrag = false

        case .leftMouseDragged, .flagsChanged:
            updateDrag(quartzPoint: quartzPoint, flags: flags)

        case .leftMouseUp:
            finishDrag()

        default:
            break
        }
    }

    private func updateDrag(quartzPoint: CGPoint, flags: CGEventFlags) {
        guard flags.contains(.maskShift),
              let candidateWindow,
              let initialFrame,
              let currentFrame = candidateWindow.frame,
              hasMoved(from: initialFrame, to: currentFrame),
              let coordinateConverter = coordinateConverter() else {
            if isDockingDrag {
                overlay.hide()
                selectedZoneIndex = nil
                isDockingDrag = false
            }
            return
        }

        let appKitPoint = coordinateConverter.appKitPoint(fromQuartz: quartzPoint)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }) else {
            return
        }
        let display = DisplayDescriptor(screen: screen)
        let layout = profileStore.layout(for: display)

        isDockingDrag = true
        selectedZoneIndex = overlay.show(on: screen, layout: layout, pointer: appKitPoint)
    }

    private func finishDrag() {
        defer { resetDrag() }

        guard isDockingDrag,
              let selectedZoneIndex,
              overlay.globalZoneFrames.indices.contains(selectedZoneIndex),
              let candidateWindow,
              let coordinateConverter = coordinateConverter() else {
            return
        }

        let appKitFrame = overlay.globalZoneFrames[selectedZoneIndex]
        let accessibilityFrame = coordinateConverter.accessibilityRect(fromAppKit: appKitFrame)
        if candidateWindow.setFrame(accessibilityFrame) {
            onStatusChange?("Docked in zone \(selectedZoneIndex + 1)")
        } else {
            onStatusChange?("This window could not be resized")
        }
    }

    private func resetDrag() {
        overlay.hide()
        candidateWindow = nil
        initialFrame = nil
        selectedZoneIndex = nil
        isDockingDrag = false
    }

    private func hasMoved(from initial: CGRect, to current: CGRect) -> Bool {
        abs(initial.minX - current.minX) > 2 || abs(initial.minY - current.minY) > 2
    }

    private func coordinateConverter() -> ScreenCoordinateConverter? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        return ScreenCoordinateConverter(primaryScreenTop: primaryScreen.frame.maxY)
    }

    func selectedLayout(for screen: NSScreen) -> ZoneLayout {
        profileStore.layout(for: DisplayDescriptor(screen: screen))
    }

    func selectLayout(id: String, for screen: NSScreen) {
        let display = DisplayDescriptor(screen: screen)
        profileStore.select(layoutID: id, for: display)
        onStatusChange?("\(display.name): \(selectedLayout(for: screen).name)")
    }

    func saveCustomLayout(_ layout: ZoneLayout, for screen: NSScreen) {
        profileStore.saveCustomLayout(layout)
        selectLayout(id: layout.id, for: screen)
    }

    @discardableResult
    func deleteCustomLayout(id: String, for screen: NSScreen) -> Bool {
        guard profileStore.deleteCustomLayout(id: id) else { return false }

        let display = DisplayDescriptor(screen: screen)
        let fallback = profileStore.layout(for: display)
        onStatusChange?("Deleted custom profile — using \(fallback.name)")
        return true
    }
}
