import Testing
import CoreGraphics
@testable import WhisperFlowCore

struct HotkeyOptionTests {

    @Test func keyCodes_matchMacOSVirtualKeyCodes() {
        #expect(HotkeyOption.rightOption.keyCode == 61)
        #expect(HotkeyOption.leftOption.keyCode == 58)
        #expect(HotkeyOption.rightCommand.keyCode == 54)
        #expect(HotkeyOption.rightControl.keyCode == 62)
        #expect(HotkeyOption.rightShift.keyCode == 60)
    }

    @Test func flagMasks_matchModifierFamilies() {
        #expect(HotkeyOption.rightOption.flagMask == .maskAlternate)
        #expect(HotkeyOption.leftOption.flagMask == .maskAlternate)
        #expect(HotkeyOption.rightCommand.flagMask == .maskCommand)
        #expect(HotkeyOption.rightControl.flagMask == .maskControl)
        #expect(HotkeyOption.rightShift.flagMask == .maskShift)
    }

    @Test func displayNames_areNonEmptyAndUnique() {
        let names = HotkeyOption.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test func rawValues_roundTrip() {
        for option in HotkeyOption.allCases {
            #expect(HotkeyOption(rawValue: option.rawValue) == option)
        }
    }
}
