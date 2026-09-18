import AppKit
import DockCore

/// Places windows into zones and remembers where each window was beforehand so a
/// dock can be undone.
final class WindowSnapper {
    private struct Restore {
        let window: AccessibleWindow
        let accessibilityFrame: CGRect
        let label: String
    }

    /// Bounded so a long session cannot grow the history without limit, and so
    /// undo never reaches back to a window the user has long forgotten about.
    private let historyLimit = 20
    private var history: [Restore] = []

    var canUndo: Bool { !history.isEmpty }

    /// Docks a window into an AppKit-space zone frame.
    /// - Returns: a status message describing the outcome.
    func dock(
        window: AccessibleWindow,
        into appKitFrame: CGRect,
        zoneNumber: Int,
        converter: ScreenCoordinateConverter
    ) -> String {
        let previousFrame = window.frame
        let target = converter.accessibilityRect(fromAppKit: appKitFrame)

        guard let placement = window.setFrame(target) else {
            return "This window cannot be moved"
        }

        if let previousFrame {
            recordRestore(window: window, frame: previousFrame)
        }

        if placement.isExact {
            return "Docked in zone \(zoneNumber)"
        }
        if placement.isConstrainedBySize {
            return "Zone \(zoneNumber) — window kept its minimum size"
        }
        return "Zone \(zoneNumber) — window only partly accepted the change"
    }

    /// Restores the most recently docked window to the frame it had before.
    /// - Returns: a status message, or `nil` when nothing could be restored.
    func undoLastDock() -> String? {
        while let entry = history.popLast() {
            guard entry.window.isDockable,
                  entry.window.setFrame(entry.accessibilityFrame) != nil else {
                continue
            }
            return "Restored \(entry.label)"
        }
        return nil
    }

    func clearHistory() {
        history.removeAll()
    }

    private func recordRestore(window: AccessibleWindow, frame: CGRect) {
        let label = window.title.map { $0.isEmpty ? "window" : $0 } ?? "window"
        history.append(Restore(window: window, accessibilityFrame: frame, label: label))
        if history.count > historyLimit {
            history.removeFirst(history.count - historyLimit)
        }
    }
}
