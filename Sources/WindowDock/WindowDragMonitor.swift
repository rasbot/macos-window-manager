import AppKit
import ApplicationServices
import DockCore

/// Watches mouse drags and shows the zone overlay while a window is being dragged
/// with the activation modifier held.
final class WindowDragMonitor {
    var isEnabled = true

    private let controller: DockController
    private let overlay = ZoneOverlayController()
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var candidateWindow: AccessibleWindow?
    private var initialFrame: CGRect?
    private var selectedZoneIndex: Int?
    private var dragScreen: NSScreen?
    private var isDockingDrag = false

    init(controller: DockController) {
        self.controller = controller
    }

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
            controller.report("Unable to monitor drags")
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        eventTap = tap
        runLoopSource = source
        controller.report("Ready — \(controller.settings.activationModifier.dragHint)")
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

    /// Drops any overlay and in-flight drag state, used when displays change.
    func cancelActiveDrag() {
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
                controller.report("Accessibility permission required")
                return
            }
            candidateWindow = AccessibleWindowResolver.window(at: quartzPoint)
            initialFrame = candidateWindow?.frame
            selectedZoneIndex = nil
            dragScreen = nil
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
        guard controller.settings.activationModifier.isSatisfied(by: flags),
              let candidateWindow,
              let initialFrame,
              let currentFrame = candidateWindow.frame,
              hasMoved(from: initialFrame, to: currentFrame),
              let coordinateConverter = coordinateConverter() else {
            if isDockingDrag {
                overlay.hide()
                selectedZoneIndex = nil
                dragScreen = nil
                isDockingDrag = false
            }
            return
        }

        let appKitPoint = coordinateConverter.appKitPoint(fromQuartz: quartzPoint)
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(appKitPoint) }) else {
            return
        }

        isDockingDrag = true
        dragScreen = screen
        selectedZoneIndex = overlay.show(
            on: screen,
            layout: controller.layout(for: screen),
            pointer: appKitPoint
        )
    }

    private func finishDrag() {
        defer { resetDrag() }

        guard isDockingDrag,
              let selectedZoneIndex,
              let candidateWindow,
              let dragScreen else {
            return
        }

        controller.dock(window: candidateWindow, intoZoneAt: selectedZoneIndex, on: dragScreen)
    }

    private func resetDrag() {
        overlay.hide()
        candidateWindow = nil
        initialFrame = nil
        selectedZoneIndex = nil
        dragScreen = nil
        isDockingDrag = false
    }

    private func hasMoved(from initial: CGRect, to current: CGRect) -> Bool {
        abs(initial.minX - current.minX) > 2 || abs(initial.minY - current.minY) > 2
    }

    private func coordinateConverter() -> ScreenCoordinateConverter? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        return ScreenCoordinateConverter(primaryScreenTop: primaryScreen.frame.maxY)
    }
}
