import Foundation

public enum CleanupError: Error {
    case timeout
    case badStatus(Int)
    case decodingFailed
    case disabled
}

public protocol CleanupService: Sendable {
    func cleanup(rawText: String) async throws -> String
}

public struct OllamaCleanupService: CleanupService, Sendable {
    private let session: URLSession
    private let settings: SettingsStore
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        settings: SettingsStore = SettingsStore(),
        endpoint: URL = URL(string: "http://localhost:11434/api/generate")!
    ) {
        self.session = session
        self.settings = settings
        self.endpoint = endpoint
    }

    private struct GenerateRequest: Encodable {
        let model: String
        let prompt: String
        let stream: Bool
    }

    private struct GenerateResponse: Decodable {
        let response: String
    }

    private static let systemPrompt = """
    You clean up dictated speech. Rules:
    - Remove filler words (um, uh, äh, ähm, э-э, ну).
    - Fix grammar and punctuation.
    - Keep the original language — never translate.
    - Never add information that wasn't said.
    - Reply with ONLY the cleaned text, nothing else.
    """

    public func cleanup(rawText: String) async throws -> String {
        guard settings.cleanupEnabled else { throw CleanupError.disabled }
        let model = settings.ollamaModel
        let timeout = settings.cleanupTimeout

        let prompt = "\(Self.systemPrompt)\n\nDictated text:\n\(rawText)"
        let body = GenerateRequest(model: model, prompt: prompt, stream: false)

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)
        let request = req

        let (data, response) = try await withTimeout(seconds: timeout) {
            try await session.data(for: request)
        }

        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CleanupError.badStatus(status)
        }

        guard let decoded = try? JSONDecoder().decode(GenerateResponse.self, from: data) else {
            throw CleanupError.decodingFailed
        }

        return decoded.response.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw CleanupError.timeout
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
