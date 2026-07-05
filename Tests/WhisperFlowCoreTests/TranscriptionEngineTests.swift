import Testing
@testable import WhisperFlowCore

struct TranscriptionEngineTests {

    @Test func fakeTranscriptionEngine_returnsConfiguredText() async throws {
        let engine = FakeTranscriptionEngine(textToReturn: "hello world")

        let result = try await engine.transcribe(samples: [0.1, 0.2, 0.3])

        #expect(result == "hello world")
    }

    @Test func fakeTranscriptionEngine_throwsConfiguredError() async {
        struct TestError: Error, Equatable {}
        let engine = FakeTranscriptionEngine(errorToThrow: TestError())

        do {
            _ = try await engine.transcribe(samples: [0.1, 0.2, 0.3])
            Issue.record("expected TestError")
        } catch is TestError {
            // expected
        } catch {
            Issue.record("expected TestError, got \(error)")
        }
    }
}
