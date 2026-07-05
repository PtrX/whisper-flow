import Testing
import Foundation
@testable import WhisperFlowCore

@Test func parakeet_transcribesFixture_whenModelsAndFixturesExist() async throws {
    let fixturesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures", isDirectory: true)

    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: fixturesURL.path) else {
        return // no Fixtures/ directory yet — Peter provides these later, not a failure
    }

    let wavFiles = try fileManager.contentsOfDirectory(at: fixturesURL, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension.lowercased() == "wav" }
    guard !wavFiles.isEmpty else {
        return // no .wav files yet — not a failure
    }

    let samples = try WavLoader.loadSamples(from: wavFiles[0])

    let engine = ParakeetEngine()
    try await engine.loadModels()

    let result = try await engine.transcribe(samples: samples)

    #expect(!result.isEmpty, "Transcription should not be empty for fixture audio")

    await engine.cleanup()
}
