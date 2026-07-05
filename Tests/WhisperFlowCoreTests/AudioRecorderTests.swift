import Testing
@testable import WhisperFlowCore

struct AudioRecorderTests {

    @Test func fakeRecorder_returnsBufferedSamplesOnStop() {
        let recorder = FakeAudioRecorder()
        recorder.startRecording()
        recorder.feed(samples: [0.1, 0.2, 0.3])
        let result = recorder.stopRecording()
        #expect(result == [0.1, 0.2, 0.3])
    }

    @Test func fakeRecorder_clearsBufferBetweenRecordings() {
        let recorder = FakeAudioRecorder()
        recorder.startRecording()
        recorder.feed(samples: [0.1])
        _ = recorder.stopRecording()

        recorder.startRecording()
        let result = recorder.stopRecording()

        #expect(result == [])
    }
}
