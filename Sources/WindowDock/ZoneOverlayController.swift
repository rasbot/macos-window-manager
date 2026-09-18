import AppKit
import DockCore

final class ZoneOverlayController {
    private var panel: NSPanel?
    private var overlayView: ZoneOverlayView?
    private(set) var globalZoneFrames: [CGRect] = []
    private(set) weak var screen: NSScreen?

    @discardableResult
    func show(on screen: NSScreen, layout: ZoneLayout, pointer: CGPoint) -> Int? {
        if self.screen !== screen || panel == nil {
            hide()
            createPanel(on: screen)
        }

        let visibleFrame = screen.visibleFrame
        globalZoneFrames = layout.frames(in: visibleFrame)
        overlayView?.zoneFrames = globalZoneFrames.map {
            $0.offsetBy(dx: -visibleFrame.minX, dy: -visibleFrame.minY)
        }
        let highlightedIndex = zoneIndex(at: pointer)
        overlayView?.highlightedIndex = highlightedIndex
        panel?.orderFrontRegardless()
        return highlightedIndex
    }

    func zoneIndex(at appKitPoint: CGPoint) -> Int? {
        globalZoneFrames.firstIndex { $0.contains(appKitPoint) }
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        overlayView = nil
        globalZoneFrames = []
        screen = nil
    }

    private func createPanel(on screen: NSScreen) {
        let panel = NSPanel(
            contentRect: screen.visibleFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = ZoneOverlayView(frame: CGRect(origin: .zero, size: screen.visibleFrame.size))
        panel.contentView = view

        self.screen = screen
        self.panel = panel
        self.overlayView = view
    }
}
