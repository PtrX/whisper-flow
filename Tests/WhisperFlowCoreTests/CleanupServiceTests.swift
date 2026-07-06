import Testing
import Foundation
@testable import WhisperFlowCore

final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData: Data?
    nonisolated(unsafe) static var statusCode: Int = 200
    nonisolated(unsafe) static var error: Error?
    nonisolated(unsafe) static var delay: TimeInterval = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if Self.delay > 0 {
            Thread.sleep(forTimeInterval: Self.delay)
        }
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(
            url: request.url!, statusCode: Self.statusCode,
            httpVersion: nil, headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized) struct CleanupServiceTests {
    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeSettings(
        timeout: TimeInterval = 3.0,
        model: String = "qwen3:4b",
        enabled: Bool = true
    ) -> SettingsStore {
        let store = SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
        store.cleanupTimeout = timeout
        store.ollamaModel = model
        store.cleanupEnabled = enabled
        return store
    }

    init() {
        StubURLProtocol.responseData = nil
        StubURLProtocol.error = nil
        StubURLProtocol.delay = 0
        StubURLProtocol.statusCode = 200
    }

    @Test func cleanup_returnsPolishedText_onSuccess() async throws {
        StubURLProtocol.responseData = """
        {"response": "Können Sie mir bitte das Protokoll schicken?"}
        """.data(using: .utf8)
        let service = OllamaCleanupService(session: makeSession(), settings: makeSettings())

        let result = try await service.cleanup(rawText: "äh können sie mir bitte äh das protokoll schicken")

        #expect(result == "Können Sie mir bitte das Protokoll schicken?")
    }

    @Test func cleanup_throwsTimeout_whenSlowerThanConfiguredTimeout() async {
        StubURLProtocol.delay = 0.2
        let service = OllamaCleanupService(session: makeSession(), settings: makeSettings(timeout: 0.05))

        do {
            _ = try await service.cleanup(rawText: "test")
            Issue.record("expected timeout error")
        } catch is CleanupError {
            // expected
        } catch {
            Issue.record("expected CleanupError, got \(error)")
        }
    }

    @Test func cleanup_throws_onNon200Status() async {
        StubURLProtocol.statusCode = 500
        let service = OllamaCleanupService(session: makeSession(), settings: makeSettings())

        do {
            _ = try await service.cleanup(rawText: "test")
            Issue.record("expected error")
        } catch is CleanupError {
            // expected
        } catch {
            Issue.record("expected CleanupError, got \(error)")
        }
    }

    @Test func cleanup_throwsDisabled_withoutTouchingTheNetwork() async {
        StubURLProtocol.responseData = "{\"response\": \"should never be fetched\"}".data(using: .utf8)
        let service = OllamaCleanupService(session: makeSession(), settings: makeSettings(enabled: false))

        do {
            _ = try await service.cleanup(rawText: "test")
            Issue.record("expected CleanupError.disabled")
        } catch CleanupError.disabled {
            // expected
        } catch {
            Issue.record("expected CleanupError.disabled, got \(error)")
        }
    }

    @Test func cleanup_readsSettingsFreshOnEveryCall() async throws {
        StubURLProtocol.responseData = "{\"response\": \"ok\"}".data(using: .utf8)
        let settings = makeSettings(enabled: true)
        let service = OllamaCleanupService(session: makeSession(), settings: settings)

        _ = try await service.cleanup(rawText: "first call works")

        settings.cleanupEnabled = false
        do {
            _ = try await service.cleanup(rawText: "second call must see the change")
            Issue.record("expected CleanupError.disabled on second call")
        } catch CleanupError.disabled {
            // expected
        } catch {
            Issue.record("expected CleanupError.disabled, got \(error)")
        }
    }
}
