import CoreGraphics

public enum HotkeyOption: String, CaseIterable, Sendable {
    case rightOption
    case leftOption
    case rightCommand
    case rightControl
    case rightShift

    public var keyCode: Int64 {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    public var flagMask: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: return "Right ⌥ (Option)"
        case .leftOption: return "Left ⌥ (Option)"
        case .rightCommand: return "Right ⌘ (Command)"
        case .rightControl: return "Right ⌃ (Control)"
        case .rightShift: return "Right ⇧ (Shift)"
        }
    }
}
