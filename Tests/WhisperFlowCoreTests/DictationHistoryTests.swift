import Testing
@testable import WhisperFlowCore

struct DictationHistoryTests {

    @Test func startsEmpty() {
        let history = DictationHistory()
        #expect(history.all.isEmpty)
    }

    @Test func record_addsMostRecentFirst() {
        var history = DictationHistory()
        history.record("first")
        history.record("second")
        #expect(history.all == ["second", "first"])
    }

    @Test func record_capsAtMaxEntries_droppingOldest() {
        var history = DictationHistory()
        for i in 1...11 {
            history.record("entry \(i)")
        }
        #expect(history.all.count == 10)
        #expect(history.all.first == "entry 11")
        #expect(history.all.last == "entry 2")
        #expect(!history.all.contains("entry 1"))
    }
}
