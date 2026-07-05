public enum PipelineOutcome: Equatable {
    case discarded
    case inserted(usedFallback: Bool)
    case transcriptionFailed
    case insertFailed
}

public final class PipelineCoordinator: @unchecked Sendable {
    private static let minimumSamples = 4800 // 0.3s at 16kHz

    private let transcriptionEngine: TranscriptionEngine
    private let cleanupService: CleanupService
    private let textInserter: TextInserter

    public init(
        transcriptionEngine: TranscriptionEngine,
        cleanupService: CleanupService,
        textInserter: TextInserter
    ) {
        self.transcriptionEngine = transcriptionEngine
        self.cleanupService = cleanupService
        self.textInserter = textInserter
    }

    public func handleRecordingFinished(samples: [Float]) async -> PipelineOutcome {
        guard samples.count >= Self.minimumSamples else {
            return .discarded
        }

        let rawText: String
        do {
            rawText = try await transcriptionEngine.transcribe(samples: samples)
        } catch {
            return .transcriptionFailed
        }

        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .discarded
        }

        var textToInsert = rawText
        var usedFallback = false
        do {
            textToInsert = try await cleanupService.cleanup(rawText: rawText)
        } catch {
            usedFallback = true
        }

        do {
            try textInserter.insert(text: textToInsert)
        } catch {
            return .insertFailed
        }

        return .inserted(usedFallback: usedFallback)
    }
}
