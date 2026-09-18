import AppKit
import DockCore
import UniformTypeIdentifiers

final class MenuBarController: NSObject, NSMenuDelegate {
    private let controller: DockController
    private let dragMonitor: WindowDragMonitor
    private let hotkeys: HotkeyCenter
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private let enabledMenuItem = NSMenuItem(title: "Enable WindowDock", action: #selector(toggleEnabled), keyEquivalent: "")
    private let layoutHeadingItem = NSMenuItem(title: "Layout", action: nil, keyEquivalent: "")
    private let layoutSubmenu = NSMenu()
    private let activationHeadingItem = NSMenuItem(title: "Activation", action: nil, keyEquivalent: "")
    private let activationSubmenu = NSMenu()
    private let shortcutsHeadingItem = NSMenuItem(title: "Keyboard Shortcuts", action: nil, keyEquivalent: "")
    private let shortcutsSubmenu = NSMenu()
    private let restoreItem = NSMenuItem(title: "Restore Last Window", action: #selector(restoreLastWindow), keyEquivalent: "")
    private var targetScreen: NSScreen?
    private var zoneEditor: ZoneEditorWindowController?

    init(controller: DockController, dragMonitor: WindowDragMonitor, hotkeys: HotkeyCenter) {
        self.controller = controller
        self.dragMonitor = dragMonitor
        self.hotkeys = hotkeys
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusItem.button?.image = NSImage(
            systemSymbolName: "rectangle.split.2x1",
            accessibilityDescription: "WindowDock"
        )

        buildMenu()

        menu.delegate = self
        statusItem.menu = menu
        controller.onStatusChange = { [weak self] status in
            self?.statusMenuItem.title = status
        }
        controller.onProfilesChange = { [weak self] in
            guard let self, let screen = self.targetScreen else { return }
            self.updateLayoutMenu(for: screen)
        }
        updateMenuState()
    }

    private func buildMenu() {
        // Auto-enabling would re-enable Restore Last Window whenever it has a valid
        // target, regardless of whether there is anything to restore.
        menu.autoenablesItems = false

        enabledMenuItem.target = self
        menu.addItem(enabledMenuItem)
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())

        layoutHeadingItem.submenu = layoutSubmenu
        menu.addItem(layoutHeadingItem)

        activationHeadingItem.submenu = activationSubmenu
        menu.addItem(activationHeadingItem)

        shortcutsHeadingItem.submenu = shortcutsSubmenu
        menu.addItem(shortcutsHeadingItem)

        restoreItem.target = self
        menu.addItem(restoreItem)
        menu.addItem(.separator())

        let importItem = NSMenuItem(title: "Import Profiles…", action: #selector(importProfiles), keyEquivalent: "")
        importItem.target = self
        menu.addItem(importItem)

        let exportItem = NSMenuItem(title: "Export Custom Profiles…", action: #selector(exportProfiles), keyEquivalent: "")
        exportItem.target = self
        menu.addItem(exportItem)
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
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        dragMonitor.isEnabled.toggle()
        if !dragMonitor.isEnabled {
            dragMonitor.cancelActiveDrag()
        }
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
        guard let layoutID = sender.representedObject as? String, let screen = resolvedScreen() else {
            return
        }
        controller.selectLayout(id: layoutID, for: screen)
        updateLayoutMenu(for: screen)
    }

    @objc private func selectActivationModifier(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let modifier = ActivationModifier(rawValue: raw) else {
            return
        }
        controller.settings.activationModifier = modifier
        controller.report(modifier.dragHint)
        updateMenuState()
    }

    @objc private func toggleKeyboardShortcuts() {
        let enabled = !controller.settings.areKeyboardShortcutsEnabled
        controller.settings.areKeyboardShortcutsEnabled = enabled
        if enabled {
            let failures = hotkeys.register()
            controller.report(
                failures == 0
                    ? "Keyboard shortcuts enabled"
                    : "Keyboard shortcuts enabled — \(failures) combination(s) already in use"
            )
        } else {
            hotkeys.unregisterAll()
            controller.report("Keyboard shortcuts disabled")
        }
        updateMenuState()
    }

    @objc private func restoreLastWindow() {
        controller.undoLastDock()
    }

    @objc private func createCustomProfile() {
        showLayoutEditor(createNewProfile: true)
    }

    @objc private func editCurrentCustomProfile() {
        showLayoutEditor(createNewProfile: false)
    }

    @objc private func duplicateCurrentProfile() {
        guard let screen = resolvedScreen() else { return }
        guard let copy = controller.duplicateCurrentLayout(for: screen) else { return }
        controller.report("Duplicated as “\(copy.name)”")
        updateLayoutMenu(for: screen)
    }

    @objc private func deleteCustomProfile(_ sender: NSMenuItem) {
        guard let layoutID = sender.representedObject as? String,
              let layout = controller.profileStore.customLayouts.first(where: { $0.id == layoutID }),
              let screen = resolvedScreen() else {
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
        if controller.deleteCustomLayout(id: layoutID, for: screen) {
            updateLayoutMenu(for: screen)
        }
    }

    @objc private func exportProfiles() {
        guard !controller.profileStore.customLayouts.isEmpty else {
            presentAlert(style: .informational, message: "No custom profiles to export", detail: "Create a custom profile first, then export it to share it or move it to another Mac.")
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export WindowDock Profiles"
        panel.nameFieldStringValue = "WindowDock Profiles.\(LayoutArchive.fileExtension)"
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try controller.exportCustomProfiles(to: url)
        } catch {
            presentAlert(style: .warning, message: "Export failed", detail: error.localizedDescription)
        }
    }

    @objc private func importProfiles() {
        let panel = NSOpenPanel()
        panel.title = "Import WindowDock Profiles"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.json]
        panel.allowsOtherFileTypes = true
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let added = try controller.importProfiles(from: url)
            presentAlert(
                style: .informational,
                message: added == 1 ? "Imported 1 profile" : "Imported \(added) profiles",
                detail: "Imported profiles are added under Custom Profiles and never replace a profile already on this Mac."
            )
        } catch {
            presentAlert(style: .warning, message: "Import failed", detail: error.localizedDescription)
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Menu state

    private func updateMenuState() {
        enabledMenuItem.state = dragMonitor.isEnabled ? .on : .off
        let screen = screenUnderPointer() ?? NSScreen.main ?? NSScreen.screens.first
        targetScreen = screen
        if let screen {
            updateLayoutMenu(for: screen)
        }
        updateActivationMenu()
        updateShortcutsMenu()

        restoreItem.isEnabled = controller.canUndo
        restoreItem.title = "Restore Last Window  ⌃⌥Z"

        if !AccessibilityPermission.isGranted {
            statusMenuItem.title = "Accessibility access is missing or stale"
        } else if dragMonitor.isEnabled {
            statusMenuItem.title = "Ready — \(controller.settings.activationModifier.dragHint)"
        } else {
            statusMenuItem.title = "Disabled"
        }
    }

    private func updateActivationMenu() {
        let selected = controller.settings.activationModifier
        activationHeadingItem.title = "Drag Activation: \(selected.displayName)"
        activationSubmenu.removeAllItems()

        for modifier in ActivationModifier.allCases {
            let title = modifier == .always
                ? "\(modifier.displayName) (always show zones)"
                : "\(modifier.symbol) \(modifier.displayName)"
            let item = NSMenuItem(title: title, action: #selector(selectActivationModifier(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = modifier.rawValue
            item.state = modifier == selected ? .on : .off
            activationSubmenu.addItem(item)
        }
    }

    private func updateShortcutsMenu() {
        let enabled = controller.settings.areKeyboardShortcutsEnabled
        shortcutsHeadingItem.title = enabled ? "Keyboard Shortcuts" : "Keyboard Shortcuts (off)"
        shortcutsSubmenu.removeAllItems()

        let toggleItem = NSMenuItem(
            title: "Enable Keyboard Shortcuts",
            action: #selector(toggleKeyboardShortcuts),
            keyEquivalent: ""
        )
        toggleItem.target = self
        toggleItem.state = enabled ? .on : .off
        shortcutsSubmenu.addItem(toggleItem)
        shortcutsSubmenu.addItem(.separator())

        for binding in HotkeyCenter.bindings {
            let item = NSMenuItem(title: "\(binding.shortcut)   \(binding.action.displayName)", action: nil, keyEquivalent: "")
            item.isEnabled = false
            shortcutsSubmenu.addItem(item)
        }
    }

    private func updateLayoutMenu(for screen: NSScreen) {
        let display = DisplayDescriptor.cached(for: screen)
        let selectedLayout = controller.layout(for: screen)
        layoutHeadingItem.title = "Layout for \(display.name)"

        layoutSubmenu.removeAllItems()
        addSection(title: "Built-in Profiles", layouts: controller.profileStore.builtInLayouts, selectedID: selectedLayout.id)
        if !controller.profileStore.customLayouts.isEmpty {
            layoutSubmenu.addItem(.separator())
            addSection(title: "Custom Profiles", layouts: controller.profileStore.customLayouts, selectedID: selectedLayout.id)
        }
        layoutSubmenu.addItem(.separator())

        let createItem = NSMenuItem(
            title: "New Custom Profile from Current…",
            action: #selector(createCustomProfile),
            keyEquivalent: ""
        )
        createItem.target = self
        layoutSubmenu.addItem(createItem)

        if selectedLayout.isCustom {
            let editItem = NSMenuItem(
                title: "Edit Current Custom Profile…",
                action: #selector(editCurrentCustomProfile),
                keyEquivalent: ""
            )
            editItem.target = self
            layoutSubmenu.addItem(editItem)
        }

        let duplicateItem = NSMenuItem(
            title: "Duplicate Current Profile",
            action: #selector(duplicateCurrentProfile),
            keyEquivalent: ""
        )
        duplicateItem.target = self
        layoutSubmenu.addItem(duplicateItem)

        if !controller.profileStore.customLayouts.isEmpty {
            let deleteItem = NSMenuItem(title: "Delete Custom Profile", action: nil, keyEquivalent: "")
            let deleteSubmenu = NSMenu()
            for layout in controller.profileStore.customLayouts {
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

    // MARK: - Helpers

    private func showLayoutEditor(createNewProfile: Bool) {
        guard let screen = resolvedScreen() else { return }
        let display = DisplayDescriptor.cached(for: screen)
        let editor = ZoneEditorWindowController(
            layout: controller.layout(for: screen),
            displayName: display.name,
            displaySize: screen.visibleFrame.size,
            createNewProfile: createNewProfile
        ) { [weak self, weak screen] customLayout in
            guard let self, let screen else { return }
            self.controller.saveCustomLayout(customLayout, for: screen)
            self.updateLayoutMenu(for: screen)
        }
        zoneEditor = editor
        editor.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func presentAlert(style: NSAlert.Style, message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func resolvedScreen() -> NSScreen? {
        targetScreen ?? screenUnderPointer() ?? NSScreen.main
    }

    private func screenUnderPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { $0.frame.contains(point) })
    }
}
