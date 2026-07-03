public enum HotkeyPhase: Equatable {
    case idle
    case recording
}

public enum HotkeyTransition: Equatable {
    case startRecording
    case stopRecording
}

public struct HotkeyStateMachine {
    public static let rightOptionKeyCode: Int64 = 61

    public private(set) var current: HotkeyPhase = .idle

    public init() {}

    public mutating func handle(keyCode: Int64, isDown: Bool) -> HotkeyTransition? {
        guard keyCode == Self.rightOptionKeyCode else { return nil }

        switch (current, isDown) {
        case (.idle, true):
            current = .recording
            return .startRecording
        case (.recording, false):
            current = .idle
            return .stopRecording
        default:
            return nil
        }
    }
}
