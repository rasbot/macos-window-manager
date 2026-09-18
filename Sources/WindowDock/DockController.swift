import AppKit
import DockCore

/// Owns the docking model shared by the two ways a window can be docked: dragging
/// it onto a zone, and the keyboard shortcuts.
final class DockController {
    let profileStore = ProfileStore()
    let settings = SettingsStore()
    private let snapper = WindowSnapper()

    var onStatusChange: ((String) -> Void)?
    /// Raised when the set of profiles changes so the menu can rebuild.
    var onProfilesChange: (() -> Void)?

    var canUndo: Bool { snapper.canUndo }

    func report(_ status: String) {
        onStatusChange?(status)
    }

    // MARK: - Layout selection

    func layout(for screen: NSScreen) -> ZoneLayout {
        profileStore.layout(for: DisplayDescriptor.cached(for: screen))
    }

    /// Zone frames in AppKit global coordinates for a screen's usable area.
    func zoneFrames(on screen: NSScreen) -> [CGRect] {
        layout(for: screen).frames(in: screen.visibleFrame)
    }

    func selectLayout(id: String, for screen: NSScreen) {
        let display = DisplayDescriptor.cached(for: screen)
        profileStore.select(layoutID: id, for: display)
        report("\(display.name): \(layout(for: screen).name)")
        onProfilesChange?()
    }

    func saveCustomLayout(_ layout: ZoneLayout, for screen: NSScreen) {
        guard profileStore.saveCustomLayout(layout) else {
            report("That layout could not be saved")
            return
        }
        selectLayout(id: layout.id, for: screen)
    }

    @discardableResult
    func deleteCustomLayout(id: String, for screen: NSScreen) -> Bool {
        guard profileStore.deleteCustomLayout(id: id) else { return false }

        report("Deleted custom profile — using \(layout(for: screen).name)")
        onProfilesChange?()
        return true
    }

    /// Copies the screen's current profile into a new editable custom profile.
    @discardableResult
    func duplicateCurrentLayout(for screen: NSScreen) -> ZoneLayout? {
        let copy = layout(for: screen).duplicated()
        guard profileStore.saveCustomLayout(copy) else {
            report("That profile could not be duplicated")
            return nil
        }
        selectLayout(id: copy.id, for: screen)
        return copy
    }

    // MARK: - Import and export

    func exportCustomProfiles(to url: URL) throws {
        let archive = LayoutArchive(layouts: profileStore.customLayouts)
        try archive.encoded().write(to: url, options: .atomic)
        report("Exported \(profileStore.customLayouts.count) profile(s)")
    }

    @discardableResult
    func importProfiles(from url: URL) throws -> Int {
        let archive = try LayoutArchive.decoded(from: Data(contentsOf: url))
        let importable = try archive.importableLayouts(alongside: profileStore.layouts)
        let added = profileStore.addCustomLayouts(importable)
        report(added == 1 ? "Imported 1 profile" : "Imported \(added) profiles")
        onProfilesChange?()
        return added
    }

    // MARK: - Docking

    /// Docks a specific window into a zone on a screen. Used on drag release.
    func dock(window: AccessibleWindow, intoZoneAt index: Int, on screen: NSScreen) {
        let frames = zoneFrames(on: screen)
        guard frames.indices.contains(index), let converter = coordinateConverter() else { return }

        report(snapper.dock(
            window: window,
            into: frames[index],
            zoneNumber: index + 1,
            converter: converter
        ))
    }

    /// Docks the frontmost window into zone `number` (1-based) on its own screen.
    func dockFocusedWindow(toZoneNumber number: Int) {
        guard let context = focusedWindowContext() else { return }

        let frames = zoneFrames(on: context.screen)
        let index = number - 1
        guard frames.indices.contains(index) else {
            report("This layout has no zone \(number)")
            return
        }

        report(snapper.dock(
            window: context.window,
            into: frames[index],
            zoneNumber: number,
            converter: context.converter
        ))
    }

    /// Moves the frontmost window to the neighbouring zone in a direction. A window
    /// that is not in a zone yet snaps into the zone nearest to where it already is.
    func moveFocusedWindow(_ direction: ZoneDirection) {
        guard let context = focusedWindowContext() else { return }

        let frames = zoneFrames(on: context.screen)
        guard let currentIndex = ZoneNavigator.index(matching: context.appKitFrame, in: frames) else {
            report("No zones on this display")
            return
        }

        // A window that is not already sitting in its nearest zone snaps into that
        // zone first, so the first press tidies it up and the next press moves it.
        let isAligned = frames[currentIndex].insetBy(dx: -4, dy: -4).contains(context.appKitFrame)
            && context.appKitFrame.insetBy(dx: -4, dy: -4).contains(frames[currentIndex])
        let targetIndex = isAligned
            ? ZoneNavigator.index(from: currentIndex, direction: direction, in: frames)
            : currentIndex

        guard let targetIndex else {
            report("No zone to the \(direction.rawValue)")
            return
        }

        report(snapper.dock(
            window: context.window,
            into: frames[targetIndex],
            zoneNumber: targetIndex + 1,
            converter: context.converter
        ))
    }

    func undoLastDock() {
        guard let status = snapper.undoLastDock() else {
            report("Nothing to restore")
            return
        }
        report(status)
    }

    /// Dropped display references invalidate remembered frames, so the undo history
    /// is cleared when the display arrangement changes.
    func displayArrangementChanged() {
        DisplayDescriptor.invalidateCache()
        snapper.clearHistory()
        onProfilesChange?()
    }

    // MARK: - Helpers

    private struct FocusedWindowContext {
        let window: AccessibleWindow
        let screen: NSScreen
        let appKitFrame: CGRect
        let converter: ScreenCoordinateConverter
    }

    private func focusedWindowContext() -> FocusedWindowContext? {
        guard AccessibilityPermission.isGranted else {
            report("Accessibility permission required")
            return nil
        }
        guard let window = AccessibleWindowResolver.focusedWindow() else {
            report("No dockable window is focused")
            return nil
        }
        guard let converter = coordinateConverter(), let accessibilityFrame = window.frame else {
            report("This window did not report its position")
            return nil
        }

        let appKitFrame = converter.appKitRect(fromAccessibility: accessibilityFrame)
        let center = CGPoint(x: appKitFrame.midX, y: appKitFrame.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            report("No display available")
            return nil
        }

        return FocusedWindowContext(
            window: window,
            screen: screen,
            appKitFrame: appKitFrame,
            converter: converter
        )
    }

    private func coordinateConverter() -> ScreenCoordinateConverter? {
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        return ScreenCoordinateConverter(primaryScreenTop: primaryScreen.frame.maxY)
    }
}
