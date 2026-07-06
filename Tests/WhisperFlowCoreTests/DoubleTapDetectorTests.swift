import Testing
@testable import WhisperFlowCore

struct DoubleTapDetectorTests {

    @Test func singleShortTap_isNotADoubleTap() {
        var detector = DoubleTapDetector()
        let result = detector.handleRelease(pressDuration: 0.1, at: 0.0)
        #expect(result == false)
    }

    @Test func twoShortTaps_withinWindow_isADoubleTap() {
        var detector = DoubleTapDetector()
        _ = detector.handleRelease(pressDuration: 0.1, at: 0.0)
        let result = detector.handleRelease(pressDuration: 0.1, at: 0.3)
        #expect(result == true)
    }

    @Test func twoShortTaps_outsideWindow_isNotADoubleTap() {
        var detector = DoubleTapDetector()
        _ = detector.handleRelease(pressDuration: 0.1, at: 0.0)
        let result = detector.handleRelease(pressDuration: 0.1, at: 1.0)
        #expect(result == false)
    }

    @Test func longPress_cancelsAPendingTap() {
        var detector = DoubleTapDetector()
        _ = detector.handleRelease(pressDuration: 0.1, at: 0.0)
        _ = detector.handleRelease(pressDuration: 2.0, at: 0.2) // a real dictation in between
        let result = detector.handleRelease(pressDuration: 0.1, at: 0.4)
        #expect(result == false)
    }

    @Test func longPress_isNeverADoubleTap() {
        var detector = DoubleTapDetector()
        let result = detector.handleRelease(pressDuration: 2.0, at: 0.0)
        #expect(result == false)
    }

    @Test func thirdTap_afterADoubleTap_startsAFreshSequence() {
        var detector = DoubleTapDetector()
        _ = detector.handleRelease(pressDuration: 0.1, at: 0.0)
        _ = detector.handleRelease(pressDuration: 0.1, at: 0.3) // consumes as a double-tap
        let result = detector.handleRelease(pressDuration: 0.1, at: 0.4)
        #expect(result == false)
    }
}
