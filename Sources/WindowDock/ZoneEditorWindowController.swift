import AppKit
import DockCore

final class ZoneEditorWindowController: NSWindowController {
    private static let initialContentSize = CGSize(width: 840, height: 660)

    init(
        layout: ZoneLayout,
        displayName: String,
        displaySize: CGSize,
        createNewProfile: Bool = false,
        onSave: @escaping (ZoneLayout) -> Void
    ) {
        let isBuiltIn = layout.isBuiltIn
        let isCreating = createNewProfile || isBuiltIn
        let draft = ZoneLayout(
            id: isCreating ? ZoneLayout.newCustomID() : layout.id,
            name: isCreating
                ? (isBuiltIn ? "\(layout.name) Custom" : "\(layout.name) Copy")
                : layout.name,
            zones: layout.zones,
            gap: layout.gap
        )
        let editor = ZoneEditorViewController(
            layout: draft,
            displayName: displayName,
            displaySize: displaySize,
            onSave: onSave
        )
        _ = editor.view
        editor.view.frame = CGRect(origin: .zero, size: Self.initialContentSize)
        let window = NSWindow(
            contentRect: CGRect(origin: .zero, size: Self.initialContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = isCreating ? "New WindowDock Profile" : "Edit WindowDock Profile"
        window.contentViewController = editor
        window.setContentSize(Self.initialContentSize)
        window.minSize = CGSize(width: 700, height: 560)
        window.isRestorable = false
        window.center()
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window else { return }

        // Ordering the window can change its backing scale and final content frame.
        // Finish layout on the next run-loop pass, then invalidate the canvas so its
        // first real draw happens at the visible size instead of the pre-order size.
        DispatchQueue.main.async { [weak window] in
            guard let window else { return }
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentViewController?.view.needsDisplay = true
            window.contentView?.displayIfNeeded()
        }
    }
}

private final class ZoneEditorViewController: NSViewController {
    private let layoutID: String
    private let displayName: String
    private let displaySize: CGSize
    private let onSave: (ZoneLayout) -> Void
    private let nameField: NSTextField
    private let canvas = ZoneCanvasView()
    private let gapSlider: NSSlider
    private let gapValueLabel = NSTextField(labelWithString: "")
    private let deleteButton = NSButton(title: "Delete Selected", target: nil, action: nil)
    private let saveButton = NSButton(title: "Save Layout", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    init(
        layout: ZoneLayout,
        displayName: String,
        displaySize: CGSize,
        onSave: @escaping (ZoneLayout) -> Void
    ) {
        self.layoutID = layout.id
        self.displayName = displayName
        self.displaySize = displaySize
        self.onSave = onSave
        self.nameField = NSTextField(string: layout.name)
        self.gapSlider = NSSlider(value: layout.gap, minValue: 0, maxValue: 40, target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
        canvas.zones = layout.zones
        canvas.gap = layout.gap
        canvas.previewAspectRatio = displaySize.width / max(displaySize.height, 1)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 840, height: 660))
        view = root

        let titleLabel = NSTextField(labelWithString: "Custom layout for \(displayName)")
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        let displayDetailsLabel = NSTextField(labelWithString: displayDetails)
        displayDetailsLabel.textColor = .secondaryLabelColor
        let nameLabel = NSTextField(labelWithString: "Name")
        let gapLabel = NSTextField(labelWithString: "Gap")
        let instructions = NSTextField(wrappingLabelWithString: "Click a zone to activate it. Drag inside to move it, or drag any white edge or corner handle to resize. Everything snaps to a 5% grid.")
        instructions.textColor = .secondaryLabelColor

        let addButton = NSButton(title: "Split Zone", target: self, action: #selector(splitZone))
        deleteButton.target = self
        deleteButton.action = #selector(deleteSelectedZone)
        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"
        saveButton.bezelStyle = .rounded
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail

        gapSlider.target = self
        gapSlider.action = #selector(gapChanged)
        gapSlider.isContinuous = true
        gapValueLabel.alignment = .right
        gapValueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        updateGapLabel()

        canvas.onSelectionChange = { [weak self] selection in
            guard let self else { return }
            self.deleteButton.isEnabled = selection != nil && self.canvas.zones.count > 1
            self.updateValidationStatus()
        }
        canvas.onZonesChange = { [weak self] _ in
            self?.updateValidationStatus()
        }
        deleteButton.isEnabled = false
        updateValidationStatus()

        let editButtons = NSStackView(views: [addButton, deleteButton])
        editButtons.orientation = .horizontal
        editButtons.spacing = 8
        let actionButtons = NSStackView(views: [cancelButton, saveButton])
        actionButtons.orientation = .horizontal
        actionButtons.spacing = 8

        for subview in [titleLabel, displayDetailsLabel, nameLabel, nameField, gapLabel, gapSlider, gapValueLabel, instructions, canvas, editButtons, statusLabel, actionButtons] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            titleLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            displayDetailsLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            displayDetailsLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            displayDetailsLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            nameLabel.topAnchor.constraint(equalTo: displayDetailsLabel.bottomAnchor, constant: 14),
            nameLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            nameLabel.widthAnchor.constraint(equalToConstant: 48),
            nameField.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
            nameField.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 8),
            nameField.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            gapLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 14),
            gapLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            gapLabel.widthAnchor.constraint(equalTo: nameLabel.widthAnchor),
            gapSlider.centerYAnchor.constraint(equalTo: gapLabel.centerYAnchor),
            gapSlider.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            gapValueLabel.centerYAnchor.constraint(equalTo: gapLabel.centerYAnchor),
            gapValueLabel.leadingAnchor.constraint(equalTo: gapSlider.trailingAnchor, constant: 10),
            gapValueLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            gapValueLabel.widthAnchor.constraint(equalToConstant: 48),

            instructions.topAnchor.constraint(equalTo: gapLabel.bottomAnchor, constant: 14),
            instructions.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            instructions.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),

            canvas.topAnchor.constraint(equalTo: instructions.bottomAnchor, constant: 12),
            canvas.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            canvas.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            canvas.bottomAnchor.constraint(equalTo: editButtons.topAnchor, constant: -16),
            canvas.heightAnchor.constraint(greaterThanOrEqualToConstant: 300),

            editButtons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            editButtons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -20),
            editButtons.trailingAnchor.constraint(lessThanOrEqualTo: actionButtons.leadingAnchor, constant: -24),
            actionButtons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            actionButtons.bottomAnchor.constraint(equalTo: editButtons.bottomAnchor),

            statusLabel.centerYAnchor.constraint(equalTo: editButtons.centerYAnchor),
            statusLabel.leadingAnchor.constraint(greaterThanOrEqualTo: editButtons.trailingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: actionButtons.leadingAnchor, constant: -12),
            statusLabel.centerXAnchor.constraint(equalTo: root.centerXAnchor)
        ])
        root.layoutSubtreeIfNeeded()
        canvas.needsDisplay = true
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        canvas.needsDisplay = true
    }

    @objc private func splitZone() {
        guard canvas.zones.count < 12 else {
            NSSound.beep()
            return
        }

        let index = canvas.selectedZoneIndex
            ?? canvas.zones.indices.max(by: { zoneArea(at: $0) < zoneArea(at: $1) })
        guard let index, canvas.zones.indices.contains(index) else { return }

        let source = canvas.zones[index]
        let nextID = (canvas.zones.map(\.id).max() ?? 0) + 1
        if source.width >= source.height, source.width >= 0.20 {
            let halfWidth = source.width / 2
            canvas.zones[index] = NormalizedZone(
                id: source.id,
                x: source.x,
                y: source.y,
                width: halfWidth,
                height: source.height
            )
            canvas.zones.append(
                NormalizedZone(
                    id: nextID,
                    x: source.x + halfWidth,
                    y: source.y,
                    width: halfWidth,
                    height: source.height
                )
            )
        } else if source.height >= 0.20 {
            let halfHeight = source.height / 2
            canvas.zones[index] = NormalizedZone(
                id: source.id,
                x: source.x,
                y: source.y,
                width: source.width,
                height: halfHeight
            )
            canvas.zones.append(
                NormalizedZone(
                    id: nextID,
                    x: source.x,
                    y: source.y + halfHeight,
                    width: source.width,
                    height: halfHeight
                )
            )
        } else {
            NSSound.beep()
            return
        }
        canvas.selectedZoneIndex = canvas.zones.count - 1
    }

    @objc private func deleteSelectedZone() {
        guard canvas.zones.count > 1,
              let index = canvas.selectedZoneIndex,
              canvas.zones.indices.contains(index) else {
            return
        }
        canvas.zones.remove(at: index)
        canvas.selectedZoneIndex = nil
    }

    @objc private func gapChanged() {
        canvas.gap = gapSlider.doubleValue
        updateGapLabel()
    }

    @objc private func save() {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !canvas.zones.isEmpty, canvas.overlappingZoneIDs.isEmpty else {
            NSSound.beep()
            return
        }

        let layout = ZoneLayout(
            id: layoutID,
            name: name,
            zones: canvas.zones,
            gap: gapSlider.doubleValue
        )
        onSave(layout)
        view.window?.close()
    }

    @objc private func cancel() {
        view.window?.close()
    }

    private func updateGapLabel() {
        gapValueLabel.stringValue = "\(Int(gapSlider.doubleValue.rounded())) pt"
    }

    private var displayDetails: String {
        let width = Int(displaySize.width.rounded())
        let height = Int(displaySize.height.rounded())
        let aspectRatio = displaySize.width / max(displaySize.height, 1)
        return "Usable area: \(width) × \(height) pt  ·  \(String(format: "%.2f", aspectRatio)):1"
    }

    private func updateValidationStatus() {
        let overlapCount = canvas.overlappingZoneIDs.count
        saveButton.isEnabled = overlapCount == 0
        if overlapCount > 0 {
            statusLabel.stringValue = "Overlapping zones must be fixed"
            statusLabel.textColor = .systemRed
        } else if let selection = canvas.selectedZoneIndex {
            statusLabel.stringValue = "Zone \(selection + 1) active"
            statusLabel.textColor = .secondaryLabelColor
        } else {
            statusLabel.stringValue = "Select a zone to edit"
            statusLabel.textColor = .secondaryLabelColor
        }
    }

    private func zoneArea(at index: Int) -> Double {
        let zone = canvas.zones[index]
        return zone.width * zone.height
    }
}
