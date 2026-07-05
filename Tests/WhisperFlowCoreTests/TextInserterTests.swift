import Testing
@testable import WhisperFlowCore

struct TextInserterTests {

    @Test func insert_usesPrimary_whenItSucceeds() throws {
        var primaryCalled = false
        var fallbackCalled = false
        let inserter = CompositeTextInserter(
            primary: { _ in primaryCalled = true },
            fallback: { _ in fallbackCalled = true }
        )

        try inserter.insert(text: "hallo")

        #expect(primaryCalled)
        #expect(!fallbackCalled)
    }

    @Test func insert_usesFallback_whenPrimaryThrows() throws {
        struct AXFailure: Error {}
        var fallbackCalled = false
        let inserter = CompositeTextInserter(
            primary: { _ in throw AXFailure() },
            fallback: { _ in fallbackCalled = true }
        )

        try inserter.insert(text: "hallo")

        #expect(fallbackCalled)
    }

    @Test func insert_throws_whenBothPrimaryAndFallbackFail() {
        struct AXFailure: Error {}
        struct ClipboardFailure: Error {}
        let inserter = CompositeTextInserter(
            primary: { _ in throw AXFailure() },
            fallback: { _ in throw ClipboardFailure() }
        )

        #expect(throws: ClipboardFailure.self) {
            try inserter.insert(text: "hallo")
        }
    }
}
