import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var dragMonitor: WindowDragMonitor?
    private var menuBarController: MenuBarController?
    private var authorizationTimer: Timer?
    private var editorSmokeTestController: ZoneEditorWindowController?
    private var overlaySmokeTestWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ProcessInfo.processInfo.arguments.contains("--overlay-smoke-test") {
            showOverlaySmokeTest()
            return
        }

        if ProcessInfo.processInfo.arguments.contains("--editor-smoke-test") {
            NSApp.setActivationPolicy(.regular)
            let editor = ZoneEditorWindowController(
                layout: .twoColumns,
                displayName: NSScreen.main?.localizedName ?? "Test Display",
                displaySize: NSScreen.main?.visibleFrame.size ?? CGSize(width: 16, height: 9),
                onSave: { _ in }
            )
            editorSmokeTestController = editor
            editor.showWindow(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        let monitor = WindowDragMonitor()
        dragMonitor = monitor
        menuBarController = MenuBarController(dragMonitor: monitor)

        if !AccessibilityPermission.isGranted {
            AccessibilityPermission.request()
        }
        startMonitoringWhenAuthorized(monitor)
    }

    func applicationWillTerminate(_ notification: Notification) {
        authorizationTimer?.invalidate()
        dragMonitor?.stop()
    }

    private func startMonitoringWhenAuthorized(_ monitor: WindowDragMonitor) {
        guard AccessibilityPermission.isGranted else {
            authorizationTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self, weak monitor] timer in
                guard let self, let monitor else {
                    timer.invalidate()
                    return
                }
                guard AccessibilityPermission.isGranted else { return }

                timer.invalidate()
                self.authorizationTimer = nil
                _ = monitor.start()
            }
            return
        }

        _ = monitor.start()
    }

    private func showOverlaySmokeTest() {
        NSApp.setActivationPolicy(.regular)
        let contentSize = CGSize(width: 1000, height: 360)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowDock Drop Target Preview"

        let view = ZoneOverlayView(frame: CGRect(origin: .zero, size: contentSize))
        let preview = CGRect(x: 24, y: 44, width: 952, height: 268)
        view.zoneFrames = [
            CGRect(x: preview.minX, y: preview.minY, width: preview.width / 2 - 4, height: preview.height),
            CGRect(x: preview.midX + 4, y: preview.minY, width: preview.width / 2 - 4, height: preview.height)
        ]
        view.highlightedIndex = 1
        window.contentView = view
        window.center()
        window.makeKeyAndOrderFront(nil)
        overlaySmokeTestWindow = window
        NSApp.activate(ignoringOtherApps: true)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
