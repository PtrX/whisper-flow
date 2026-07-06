public enum PipelineOutcome: Equatable, Sendable {
    case discarded
    case inserted(usedFallback: Bool)
    case reinserted
    case transcriptionFailed
    case insertFailed
}

public final class PipelineCoordinator: @unchecked Sendable {
    private static let minimumSamples = 4800 // 0.3s at 16kHz

    private let transcriptionEngine: TranscriptionEngine
    private let cleanupService: CleanupService
    private let textInserter: TextInserter
    private var lastInsertedText: String?

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

        // Trailing space so back-to-back dictations don't run into each other.
        if !textToInsert.hasSuffix(" ") {
            textToInsert += " "
        }

        do {
            try textInserter.insert(text: textToInsert)
        } catch {
            return .insertFailed
        }

        lastInsertedText = textToInsert
        return .inserted(usedFallback: usedFallback)
    }

    /// Re-inserts the most recently inserted text, e.g. when the cursor wasn't
    /// where the user expected and the dictation landed somewhere unseen.
    public func reinsertLastTranscription() -> PipelineOutcome {
        guard let lastInsertedText else {
            return .discarded
        }
        do {
            try textInserter.insert(text: lastInsertedText)
        } catch {
            return .insertFailed
        }
        return .reinserted
    }
}
