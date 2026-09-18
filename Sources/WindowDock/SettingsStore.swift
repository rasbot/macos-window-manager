import DockCore
import Foundation

/// User preferences that are not tied to a single display.
final class SettingsStore {
    private let defaults: UserDefaults
    private let activationModifierKey = "activationModifier"
    private let keyboardShortcutsKey = "keyboardShortcutsEnabled"

    /// Called after any setting changes so the menu and hotkeys can follow.
    var onChange: (() -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var activationModifier: ActivationModifier {
        get {
            guard let raw = defaults.string(forKey: activationModifierKey),
                  let modifier = ActivationModifier(rawValue: raw) else {
                return .shift
            }
            return modifier
        }
        set {
            defaults.set(newValue.rawValue, forKey: activationModifierKey)
            onChange?()
        }
    }

    var areKeyboardShortcutsEnabled: Bool {
        get {
            guard defaults.object(forKey: keyboardShortcutsKey) != nil else { return true }
            return defaults.bool(forKey: keyboardShortcutsKey)
        }
        set {
            defaults.set(newValue, forKey: keyboardShortcutsKey)
            onChange?()
        }
    }
}
