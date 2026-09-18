import CoreGraphics

/// The modifier a user must hold while dragging a window for the zone overlay to
/// appear. `always` shows zones for every window drag.
public enum ActivationModifier: String, CaseIterable, Codable, Sendable {
    case shift
    case control
    case option
    case command
    case always

    public var displayName: String {
        switch self {
        case .shift: "Shift"
        case .control: "Control"
        case .option: "Option"
        case .command: "Command"
        case .always: "No modifier"
        }
    }

    /// Menu-facing description, e.g. "Hold ⇧ Shift while dragging".
    public var dragHint: String {
        switch self {
        case .always: "Drag a window to show zones"
        default: "Hold \(symbol) \(displayName) while dragging"
        }
    }

    public var symbol: String {
        switch self {
        case .shift: "⇧"
        case .control: "⌃"
        case .option: "⌥"
        case .command: "⌘"
        case .always: ""
        }
    }

    private var eventFlag: CGEventFlags? {
        switch self {
        case .shift: .maskShift
        case .control: .maskControl
        case .option: .maskAlternate
        case .command: .maskCommand
        case .always: nil
        }
    }

    /// Whether the current event flags activate docking.
    public func isSatisfied(by flags: CGEventFlags) -> Bool {
        guard let eventFlag else { return true }
        return flags.contains(eventFlag)
    }
}
