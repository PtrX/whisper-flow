@preconcurrency import FluidAudio
import Foundation

public final class ParakeetEngine: TranscriptionEngine {
    private let manager: UnifiedAsrManager

    public init(
        config: UnifiedConfig = UnifiedConfig(),
        encoderPrecision: UnifiedEncoderPrecision = .int8
    ) {
        self.manager = UnifiedAsrManager(
            configuration: nil,
            config: config,
            encoderPrecision: encoderPrecision
        )
    }

    public func loadModels() async throws {
        try await manager.loadModels()
    }

    public func transcribe(samples: [Float]) async throws -> String {
        try await manager.transcribe(samples)
    }

    public func cleanup() async {
        await manager.cleanup()
    }
}
