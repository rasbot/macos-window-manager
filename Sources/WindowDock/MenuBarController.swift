import AppKit
import DockCore

final class MenuBarController: NSObject, NSMenuDelegate {
    private let dragMonitor: WindowDragMonitor
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "Enable WindowDock", action: #selector(toggleEnabled), keyEquivalent: "")
    private let layoutHeadingItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
    private let layoutSubmenu = NSMenu()
    private var targetScreen: NSScreen?
    private var zoneEditor: ZoneEditorWindowController?

    init(dragMonitor: WindowDragMonitor) {
        self.dragMonitor = dragMonitor
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.split.2x1",
            accessibilityDescription: "WindowDock"
        )

        enabledMenuItem.target = self
        menu.addItem(enabledMenuItem)
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        layoutHeadingItem.submenu = layoutSubmenu
        menu.addItem(layoutHeadingItem)
        menu.addItem(.separator())

        let permissionItem = NSMenuItem(
            title: "Open Accessibility Settings…",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        permissionItem.target = self
        menu.addItem(permissionItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit WindowDock", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.delegate = self
        statusItem.menu = menu
        dragMonitor.onStatusChange = { [weak self] status in
            self?.statusMenuItem.title = status
        }
        updateMenuState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }

    @objc private func toggleEnabled() {
        dragMonitor.isEnabled.toggle()
        updateMenuState()
    }

    @objc private func openAccessibilitySettings() {
        AccessibilityPermission.request()
        if let settingsURL = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(settingsURL)
        }
        updateMenuState()
    }

    @objc private func selectLayout(_ sender: NSMenuItem) {
        guard let layoutID = sender.representedObject as? String,
              let screen = targetScreen ?? screenUnderPointer() ?? NSScreen.main else {
            return
        }
        dragMonitor.selectLayout(id: layoutID, for: screen)
        updateLayoutMenu(for: screen)
    }

    @objc private func createCustomProfile() {
        showLayoutEditor(createNewProfile: true)
    }

    @objc private func editCurrentCustomProfile() {
        showLayoutEditor(createNewProfile: false)
    }

    private func showLayoutEditor(createNewProfile: Bool) {
        guard let screen = targetScreen ?? screenUnderPointer() ?? NSScreen.main else { return }
        let display = DisplayDescriptor(screen: screen)
        let layout = dragMonitor.selectedLayout(for: screen)
        let editor = ZoneEditorWindowController(
            layout: layout,
            displayName: display.name,
            displaySize: screen.visibleFrame.size,
            createNewProfile: createNewProfile
        ) { [weak self, weak screen] customLayout in
            guard let self, let screen else { return }
            self.dragMonitor.saveCustomLayout(customLayout, for: screen)
            self.updateLayoutMenu(for: screen)
        }
        zoneEditor = editor
        editor.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func deleteCustomProfile(_ sender: NSMenuItem) {
        guard let layoutID = sender.representedObject as? String,
              let layout = dragMonitor.profileStore.customLayouts.first(where: { $0.id == layoutID }),
              let screen = targetScreen ?? screenUnderPointer() ?? NSScreen.main else {
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Delete “\(layout.name)”?"
        alert.informativeText = "This custom profile will be permanently removed. Displays using it will fall back to Two Columns."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if dragMonitor.deleteCustomLayout(id: layoutID, for: screen) {
            updateLayoutMenu(for: screen)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateMenuState() {
        enabledMenuItem.state = dragMonitor.isEnabled ? .on : .off
        let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        targetScreen = screen
        if let screen {
            updateLayoutMenu(for: screen)
        }
        if !AccessibilityPermission.isGranted {
            statusMenuItem.title = "Accessibility access is missing or stale"
        } else if dragMonitor.isEnabled {
            statusMenuItem.title = "Ready — hold Shift while dragging"
        } else {
            statusMenuItem.title = "Disabled"
        }
    }

    private func updateLayoutMenu(for screen: NSScreen) {
        let display = DisplayDescriptor(screen: screen)
        let selectedLayout = dragMonitor.selectedLayout(for: screen)
        layoutHeadingItem.title = "Layout for \(display.name)"

        layoutSubmenu.removeAllItems()
        addSection(title: "Built-in Profiles", layouts: dragMonitor.profileStore.builtInLayouts, selectedID: selectedLayout.id)
        if !dragMonitor.profileStore.customLayouts.isEmpty {
            layoutSubmenu.addItem(.separator())
            addSection(title: "Custom Profiles", layouts: dragMonitor.profileStore.customLayouts, selectedID: selectedLayout.id)
        }
        layoutSubmenu.addItem(.separator())

        let createItem = NSMenuItem(
            title: "New Custom Profile from Current…",
            action: #selector(createCustomProfile),
            keyEquivalent: ""
        )
        createItem.target = self
        layoutSubmenu.addItem(createItem)

        if selectedLayout.id.hasPrefix("custom-") {
            let editItem = NSMenuItem(
                title: "Edit Current Custom Profile…",
                action: #selector(editCurrentCustomProfile),
                keyEquivalent: ""
            )
            editItem.target = self
            layoutSubmenu.addItem(editItem)
        }

        if !dragMonitor.profileStore.customLayouts.isEmpty {
            let deleteItem = NSMenuItem(title: "Delete Custom Profile", action: nil, keyEquivalent: "")
            let deleteSubmenu = NSMenu()
            for layout in dragMonitor.profileStore.customLayouts {
                let item = NSMenuItem(
                    title: layout.name,
                    action: #selector(deleteCustomProfile(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = layout.id
                deleteSubmenu.addItem(item)
            }
            deleteItem.submenu = deleteSubmenu
            layoutSubmenu.addItem(deleteItem)
        }
    }

    private func addSection(title: String, layouts: [ZoneLayout], selectedID: String) {
        let heading = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        heading.isEnabled = false
        layoutSubmenu.addItem(heading)

        for layout in layouts {
            let item = NSMenuItem(title: layout.name, action: #selector(selectLayout(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = layout.id
            item.state = layout.id == selectedID ? .on : .off
            item.indentationLevel = 1
            layoutSubmenu.addItem(item)
        }
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
    }
}
