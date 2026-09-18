import Carbon.HIToolbox
import DockCore
import Foundation

/// Global keyboard shortcuts.
///
/// Carbon's hot key API is used rather than an event tap because it reserves the
/// combination system-wide: the shortcut never reaches the frontmost application,
/// and no extra event-tap permission is involved.
final class HotkeyCenter {
    enum Action: Equatable {
        case dockZone(Int)
        case move(ZoneDirection)
        case undo

        /// Menu-facing shortcut description, e.g. "⌃⌥1".
        var displayShortcut: String {
            switch self {
            case .dockZone(let number): "⌃⌥\(number)"
            case .move(.left): "⌃⌥←"
            case .move(.right): "⌃⌥→"
            case .move(.up): "⌃⌥↑"
            case .move(.down): "⌃⌥↓"
            case .undo: "⌃⌥Z"
            }
        }

        var displayName: String {
            switch self {
            case .dockZone(let number): "Dock focused window in zone \(number)"
            case .move(let direction): "Move focused window \(direction.rawValue)"
            case .undo: "Restore last docked window"
            }
        }
    }

    private struct Binding {
        let action: Action
        let keyCode: Int
        let modifiers: Int
    }

    var onAction: ((Action) -> Void)?

    private static let signature = OSType(0x57_44_4B_59) // 'WDKY'
    private static let baseModifiers = controlKey | optionKey

    private var registeredKeys: [UInt32: EventHotKeyRef] = [:]
    private var actionsByID: [UInt32: Action] = [:]
    private var eventHandler: EventHandlerRef?

    private(set) var isEnabled = false

    /// Every shortcut this app offers, in the order shown in the menu.
    static var bindings: [(action: Action, shortcut: String)] {
        defaultBindings.map { ($0.action, $0.action.displayShortcut) }
    }

    private static let defaultBindings: [Binding] = {
        let numberKeys = [
            kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
            kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9
        ]
        var bindings = numberKeys.enumerated().map { index, keyCode in
            Binding(action: .dockZone(index + 1), keyCode: keyCode, modifiers: baseModifiers)
        }
        bindings.append(Binding(action: .move(.left), keyCode: kVK_LeftArrow, modifiers: baseModifiers))
        bindings.append(Binding(action: .move(.right), keyCode: kVK_RightArrow, modifiers: baseModifiers))
        bindings.append(Binding(action: .move(.up), keyCode: kVK_UpArrow, modifiers: baseModifiers))
        bindings.append(Binding(action: .move(.down), keyCode: kVK_DownArrow, modifiers: baseModifiers))
        bindings.append(Binding(action: .undo, keyCode: kVK_ANSI_Z, modifiers: baseModifiers))
        return bindings
    }()

    deinit {
        unregisterAll()
    }

    /// Registers every shortcut.
    /// - Returns: the number of shortcuts that could not be claimed, which happens
    ///   when another application already owns the combination.
    @discardableResult
    func register() -> Int {
        guard !isEnabled else { return 0 }

        installHandlerIfNeeded()

        var failures = 0
        for (index, binding) in Self.defaultBindings.enumerated() {
            let id = UInt32(index + 1)
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                UInt32(binding.modifiers),
                hotKeyID,
                GetApplicationEventTarget(),
                0,
                &reference
            )

            if status == noErr, let reference {
                registeredKeys[id] = reference
                actionsByID[id] = binding.action
            } else {
                failures += 1
            }
        }

        isEnabled = !registeredKeys.isEmpty
        return failures
    }

    func unregisterAll() {
        for reference in registeredKeys.values {
            UnregisterEventHotKey(reference)
        }
        registeredKeys.removeAll()
        actionsByID.removeAll()
        isEnabled = false
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let callback: EventHandlerUPP = { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }

            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }

            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            center.perform(id: hotKeyID.id)
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    private func perform(id: UInt32) {
        guard let action = actionsByID[id] else { return }
        // Carbon delivers on the main thread; hop explicitly so the contract is
        // clear to callers touching AppKit state.
        DispatchQueue.main.async { [weak self] in
            self?.onAction?(action)
        }
    }
}
