@preconcurrency import FluidAudio
import Foundation

// FluidAudio ships two unrelated Parakeet backends: `UnifiedAsrManager` wraps
// "Parakeet Unified 0.6B" (repo path `parakeet-unified-en-0.6b` — English only),
// while `AsrManager` + `AsrModels.downloadAndLoad(version: .v3)` wraps the
// multilingual TDT model (25 European languages incl. German/Russian) the spec
// requires. Using the former silently produced English phonetic transliterations
// of German/Russian speech instead of real transcriptions.
public final class ParakeetEngine: TranscriptionEngine, @unchecked Sendable {
    private let manager: AsrManager

    public init() {
        self.manager = AsrManager()
    }

    public func loadModels() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        try await manager.loadModels(models)
    }

    public func transcribe(samples: [Float]) async throws -> String {
        var decoderState = try TdtDecoderState()
        let result = try await manager.transcribe(samples, decoderState: &decoderState, language: nil)
        return result.text
    }

    public func cleanup() async {
        await manager.cleanup()
    }
}
