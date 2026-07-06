import Foundation

public struct DoubleTapDetector: Sendable {
    private let tapMaxDuration: TimeInterval
    private let doubleTapWindow: TimeInterval
    private var lastTapEndTime: TimeInterval?

    public init(tapMaxDuration: TimeInterval = 0.3, doubleTapWindow: TimeInterval = 0.5) {
        self.tapMaxDuration = tapMaxDuration
        self.doubleTapWindow = doubleTapWindow
    }

    /// Call on every key release with how long it was held and the current
    /// (monotonic) timestamp. Returns true when this release completes a
    /// double-tap; consumes the sequence so a third tap starts fresh instead
    /// of being read as a second double-tap.
    public mutating func handleRelease(pressDuration: TimeInterval, at timestamp: TimeInterval) -> Bool {
        guard pressDuration <= tapMaxDuration else {
            lastTapEndTime = nil
            return false
        }
        if let lastTapEndTime, timestamp - lastTapEndTime <= doubleTapWindow {
            self.lastTapEndTime = nil
            return true
        }
        lastTapEndTime = timestamp
        return false
    }
}
