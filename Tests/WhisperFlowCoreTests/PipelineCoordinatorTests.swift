import Testing
@testable import WhisperFlowCore

private struct FakeCleanupService: CleanupService, @unchecked Sendable {
    var textToReturn: String
    var errorToThrow: Error?
    func cleanup(rawText: String) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        return textToReturn
    }
}

private final class FakeTextInserter: TextInserter, @unchecked Sendable {
    var insertedText: String?
    var allInsertedTexts: [String] = []
    var errorToThrow: Error?
    func insert(text: String) throws {
        if let errorToThrow { throw errorToThrow }
        insertedText = text
        allInsertedTexts.append(text)
    }
}

struct PipelineCoordinatorTests {

    @Test func happyPath_insertsCleanedText() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "äh hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        #expect(outcome == .inserted(usedFallback: false))
        #expect(inserter.insertedText == "Hallo Welt. ")
    }

    @Test func insertedText_doesNotDuplicateTrailingSpace_whenAlreadyPresent() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt. "),
            textInserter: inserter
        )

        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        #expect(inserter.insertedText == "Hallo Welt. ")
    }

    @Test func shortRecording_isDiscardedSilently() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hi"),
            cleanupService: FakeCleanupService(textToReturn: "Hi."),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 3200))

        #expect(outcome == .discarded)
        #expect(inserter.insertedText == nil)
    }

    @Test func cleanupFailure_fallsBackToRawTranscript() async {
        struct CleanupBoom: Error {}
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "raw text"),
            cleanupService: FakeCleanupService(textToReturn: "", errorToThrow: CleanupBoom()),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        #expect(outcome == .inserted(usedFallback: true))
        #expect(inserter.insertedText == "raw text ")
    }

    @Test func transcriptionFailure_returnsFailedOutcome() async {
        struct AsrBoom: Error {}
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(errorToThrow: AsrBoom()),
            cleanupService: FakeCleanupService(textToReturn: "unused"),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        #expect(outcome == .transcriptionFailed)
        #expect(inserter.insertedText == nil)
    }

    @Test func bothInsertPathsFail_returnsInsertFailedOutcome() async {
        struct InsertBoom: Error {}
        let inserter = FakeTextInserter()
        inserter.errorToThrow = InsertBoom()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "raw text"),
            cleanupService: FakeCleanupService(textToReturn: "Cleaned."),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        #expect(outcome == .insertFailed)
    }

    @Test func reinsertLastTranscription_afterSuccessfulInsert_insertsSameTextAgain() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        let outcome = coordinator.reinsertLastTranscription()

        #expect(outcome == .reinserted)
        #expect(inserter.allInsertedTexts == ["Hallo Welt. ", "Hallo Welt. "])
    }

    @Test func reinsertLastTranscription_withNothingInsertedYet_returnsDiscarded() {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "unused"),
            cleanupService: FakeCleanupService(textToReturn: "unused"),
            textInserter: inserter
        )

        let outcome = coordinator.reinsertLastTranscription()

        #expect(outcome == .discarded)
        #expect(inserter.allInsertedTexts.isEmpty)
    }

    @Test func reinsertLastTranscription_whenInsertThrows_returnsInsertFailed() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))
        struct InsertBoom: Error {}
        inserter.errorToThrow = InsertBoom()

        let outcome = coordinator.reinsertLastTranscription()

        #expect(outcome == .insertFailed)
    }
}
