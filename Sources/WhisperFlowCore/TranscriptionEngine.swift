public protocol TranscriptionEngine {
    func transcribe(samples: [Float]) async throws -> String
}

public struct FakeTranscriptionEngine: TranscriptionEngine {
    public var textToReturn: String
    public var errorToThrow: Error?

    public init(textToReturn: String = "", errorToThrow: Error? = nil) {
        self.textToReturn = textToReturn
        self.errorToThrow = errorToThrow
    }

    public func transcribe(samples: [Float]) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        return textToReturn
    }
}
