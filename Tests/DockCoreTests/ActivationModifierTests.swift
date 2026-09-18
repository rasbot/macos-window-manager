import CoreGraphics
import Testing
@testable import DockCore

@Test func activationModifierMatchesItsOwnFlag() {
    #expect(ActivationModifier.shift.isSatisfied(by: .maskShift))
    #expect(ActivationModifier.control.isSatisfied(by: .maskControl))
    #expect(ActivationModifier.option.isSatisfied(by: .maskAlternate))
    #expect(ActivationModifier.command.isSatisfied(by: .maskCommand))
}

@Test func activationModifierRejectsOtherFlags() {
    #expect(!ActivationModifier.shift.isSatisfied(by: .maskControl))
    #expect(!ActivationModifier.command.isSatisfied(by: []))
    #expect(!ActivationModifier.option.isSatisfied(by: [.maskShift, .maskCommand]))
}

@Test func activationModifierAcceptsExtraHeldKeys() {
    // Holding Shift together with Command must still activate a Shift binding.
    #expect(ActivationModifier.shift.isSatisfied(by: [.maskShift, .maskCommand]))
}

@Test func alwaysModifierNeedsNoKeys() {
    #expect(ActivationModifier.always.isSatisfied(by: []))
    #expect(ActivationModifier.always.isSatisfied(by: .maskControl))
    #expect(ActivationModifier.always.symbol.isEmpty)
}

@Test func activationModifiersRoundTripThroughRawValues() {
    for modifier in ActivationModifier.allCases {
        #expect(ActivationModifier(rawValue: modifier.rawValue) == modifier)
        #expect(!modifier.displayName.isEmpty)
        #expect(!modifier.dragHint.isEmpty)
    }
}
