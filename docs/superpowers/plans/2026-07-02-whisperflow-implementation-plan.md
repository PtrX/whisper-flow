# WhisperFlow Implementation Plan

> **For agentic workers:** This plan is executed by feeding one task at a time to `opencode run` (model `opencode/deepseek-v4-flash-free`), not by Claude subagents. Each task is self-contained: paste its steps as the prompt, let opencode implement + run the commands, verify the "Expected" output before moving to the next task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build WhisperFlow, a native Swift menu-bar app that does fully local push-to-talk dictation (German/Russian) with LLM cleanup, per `docs/superpowers/specs/2026-07-02-local-dictation-design.md`.

**Architecture:** Swift Package with two targets — `WhisperFlowCore` (a testable library: protocols + implementations for recording, transcription, cleanup, text insertion, and the orchestrating `PipelineCoordinator`) and `WhisperFlowApp` (the executable: menu bar UI, global hotkey, AppKit glue). Core logic is protocol-based so every component except AppKit/CoreML glue is unit-testable with fakes.

**Tech Stack:** Swift 6, Swift Package Manager, AVFoundation, AppKit, FluidAudio (Parakeet-TDT 0.6B v3, CoreML), Ollama HTTP API (Qwen3-4B), XCTest.

## What OpenCode Can and Cannot QA

Be honest about this boundary in every task:

- **OpenCode CAN automate:** `swift build`, `swift test`, unit tests with fakes, the integration test in Task 5 (if fixture audio exists), reading command output and fixing failures.
- **OpenCode CANNOT automate:** granting Microphone/Accessibility permissions, verifying the hotkey fires in real apps, verifying text actually lands in Notes/Mail/Chrome/VS Code/Slack, judging dictation/cleanup quality by ear. Those require a human with a real desktop session — Peter runs the Task 12 manual checklist himself.

---

### Task 1: Project scaffolding

**Files:**
- Create: `Package.swift`
- Create: `Sources/WhisperFlowCore/.gitkeep`
- Create: `Sources/WhisperFlowApp/main.swift`
- Create: `Tests/WhisperFlowCoreTests/.gitkeep`
- Create: `.gitignore`

- [ ] **Step 1: Write `Package.swift`**

```swift
// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "WhisperFlow",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "WhisperFlowCore", targets: ["WhisperFlowCore"]),
        .executable(name: "WhisperFlowApp", targets: ["WhisperFlowApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4")
    ],
    targets: [
        .target(
            name: "WhisperFlowCore",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio")
            ]
        ),
        .executableTarget(
            name: "WhisperFlowApp",
            dependencies: ["WhisperFlowCore"]
        ),
        .testTarget(
            name: "WhisperFlowCoreTests",
            dependencies: ["WhisperFlowCore"]
        ),
    ]
)
```

- [ ] **Step 2: Write placeholder entry point**

```swift
// Sources/WhisperFlowApp/main.swift
print("WhisperFlow starting...")
```

- [ ] **Step 3: Write `.gitignore`**

```
.build/
.swiftpm/
*.xcodeproj
.DS_Store
```

- [ ] **Step 4: Create empty dirs so git tracks them, resolve dependency, build**

Run: `touch Sources/WhisperFlowCore/.gitkeep Tests/WhisperFlowCoreTests/.gitkeep && swift build`
Expected: Package resolves `FluidAudio`, build succeeds with `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Package.swift Package.resolved Sources .gitignore Tests
git commit -m "Scaffold WhisperFlow Swift package with FluidAudio dependency"
```

---

### Task 2: Ollama setup script

**Files:**
- Create: `scripts/setup_ollama.sh`

- [ ] **Step 1: Write the setup script**

```bash
#!/usr/bin/env bash
set -euo pipefail

if ! command -v ollama >/dev/null 2>&1; then
    echo "Ollama not found. Install it with: brew install ollama"
    exit 1
fi

if ! pgrep -x "ollama" >/dev/null 2>&1; then
    echo "Starting ollama serve in the background..."
    nohup ollama serve >/tmp/ollama.log 2>&1 &
    sleep 2
fi

echo "Pulling qwen3:4b..."
ollama pull qwen3:4b

echo "Verifying with a test prompt..."
curl -s http://localhost:11434/api/generate -d '{
  "model": "qwen3:4b",
  "prompt": "Reply with exactly: OK",
  "stream": false
}' | grep -q '"response"' && echo "Ollama + qwen3:4b ready."
```

- [ ] **Step 2: Make it executable and run it**

Run: `chmod +x scripts/setup_ollama.sh && ./scripts/setup_ollama.sh`
Expected: ends with `Ollama + qwen3:4b ready.` (if `ollama` isn't installed yet, install via `brew install ollama` first, then re-run)

- [ ] **Step 3: Commit**

```bash
git add scripts/setup_ollama.sh
git commit -m "Add Ollama + qwen3:4b setup script"
```

---

### Task 3: Hotkey pure logic (TDD)

Right-Option (⌥) is a modifier key, detected via `.flagsChanged` CGEvents, not `.keyDown`. `kVK_RightOption` is keycode 61. This task isolates the state-transition logic so it's testable without a real event tap.

**Files:**
- Create: `Sources/WhisperFlowCore/HotkeyState.swift`
- Test: `Tests/WhisperFlowCoreTests/HotkeyStateTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WhisperFlowCoreTests/HotkeyStateTests.swift
import XCTest
@testable import WhisperFlowCore

final class HotkeyStateTests: XCTestCase {
    func test_rightOptionKeyDown_fromIdle_transitionsToRecording() {
        var machine = HotkeyStateMachine()
        let transition = machine.handle(keyCode: 61, isDown: true)
        XCTAssertEqual(transition, .startRecording)
        XCTAssertEqual(machine.current, .recording)
    }

    func test_rightOptionKeyUp_fromRecording_transitionsToIdle() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(keyCode: 61, isDown: true)
        let transition = machine.handle(keyCode: 61, isDown: false)
        XCTAssertEqual(transition, .stopRecording)
        XCTAssertEqual(machine.current, .idle)
    }

    func test_otherKeyCode_isIgnored() {
        var machine = HotkeyStateMachine()
        let transition = machine.handle(keyCode: 58, isDown: true)
        XCTAssertNil(transition)
        XCTAssertEqual(machine.current, .idle)
    }

    func test_repeatedKeyDown_whileRecording_isIgnored() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(keyCode: 61, isDown: true)
        let transition = machine.handle(keyCode: 61, isDown: true)
        XCTAssertNil(transition)
        XCTAssertEqual(machine.current, .recording)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyStateTests`
Expected: FAIL — `HotkeyStateMachine` does not exist

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WhisperFlowCore/HotkeyState.swift
public enum HotkeyPhase: Equatable {
    case idle
    case recording
}

public enum HotkeyTransition: Equatable {
    case startRecording
    case stopRecording
}

public struct HotkeyStateMachine {
    public static let rightOptionKeyCode: Int64 = 61

    public private(set) var current: HotkeyPhase = .idle

    public init() {}

    public mutating func handle(keyCode: Int64, isDown: Bool) -> HotkeyTransition? {
        guard keyCode == Self.rightOptionKeyCode else { return nil }

        switch (current, isDown) {
        case (.idle, true):
            current = .recording
            return .startRecording
        case (.recording, false):
            current = .idle
            return .stopRecording
        default:
            return nil
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotkeyStateTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/HotkeyState.swift Tests/WhisperFlowCoreTests/HotkeyStateTests.swift
git commit -m "Add hotkey state machine with tests"
```

---

### Task 4: CleanupService (Ollama HTTP client, TDD)

**Files:**
- Create: `Sources/WhisperFlowCore/CleanupService.swift`
- Test: `Tests/WhisperFlowCoreTests/CleanupServiceTests.swift`

- [ ] **Step 1: Write the failing tests (mocking `URLSession` via `URLProtocol`)**

```swift
// Tests/WhisperFlowCoreTests/CleanupServiceTests.swift
import XCTest
@testable import WhisperFlowCore

final class StubURLProtocol: URLProtocol {
    static var responseData: Data?
    static var statusCode: Int = 200
    static var error: Error?
    static var delay: TimeInterval = 0

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

final class CleanupServiceTests: XCTestCase {
    func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        StubURLProtocol.responseData = nil
        StubURLProtocol.error = nil
        StubURLProtocol.delay = 0
        StubURLProtocol.statusCode = 200
        super.tearDown()
    }

    func test_cleanup_returnsPolishedText_onSuccess() async throws {
        StubURLProtocol.responseData = """
        {"response": "Können Sie mir bitte das Protokoll schicken?"}
        """.data(using: .utf8)
        let service = OllamaCleanupService(session: makeSession(), timeout: 3.0)

        let result = try await service.cleanup(rawText: "äh können sie mir bitte äh das protokoll schicken")

        XCTAssertEqual(result, "Können Sie mir bitte das Protokoll schicken?")
    }

    func test_cleanup_throwsTimeout_whenSlowerThanConfiguredTimeout() async {
        StubURLProtocol.delay = 0.2
        let service = OllamaCleanupService(session: makeSession(), timeout: 0.05)

        do {
            _ = try await service.cleanup(rawText: "test")
            XCTFail("expected timeout error")
        } catch is CleanupError {
            // expected
        } catch {
            XCTFail("expected CleanupError, got \(error)")
        }
    }

    func test_cleanup_throws_onNon200Status() async {
        StubURLProtocol.statusCode = 500
        let service = OllamaCleanupService(session: makeSession(), timeout: 3.0)

        do {
            _ = try await service.cleanup(rawText: "test")
            XCTFail("expected error")
        } catch is CleanupError {
            // expected
        } catch {
            XCTFail("expected CleanupError, got \(error)")
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CleanupServiceTests`
Expected: FAIL — `OllamaCleanupService` / `CleanupError` do not exist

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WhisperFlowCore/CleanupService.swift
import Foundation

public enum CleanupError: Error {
    case timeout
    case badStatus(Int)
    case decodingFailed
}

public protocol CleanupService {
    func cleanup(rawText: String) async throws -> String
}

public struct OllamaCleanupService: CleanupService {
    private let session: URLSession
    private let timeout: TimeInterval
    private let model: String
    private let endpoint: URL

    public init(
        session: URLSession = .shared,
        timeout: TimeInterval = 3.0,
        model: String = "qwen3:4b",
        endpoint: URL = URL(string: "http://localhost:11434/api/generate")!
    ) {
        self.session = session
        self.timeout = timeout
        self.model = model
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
        let prompt = "\(Self.systemPrompt)\n\nDictated text:\n\(rawText)"
        let body = GenerateRequest(model: model, prompt: prompt, stream: false)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

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
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter CleanupServiceTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/CleanupService.swift Tests/WhisperFlowCoreTests/CleanupServiceTests.swift
git commit -m "Add Ollama-backed CleanupService with timeout handling"
```

---

### Task 5: TranscriptionEngine protocol + Parakeet integration

**Files:**
- Create: `Sources/WhisperFlowCore/TranscriptionEngine.swift`
- Create: `Sources/WhisperFlowCore/ParakeetEngine.swift`
- Test: `Tests/WhisperFlowCoreTests/TranscriptionEngineTests.swift`
- Test: `Tests/WhisperFlowCoreTests/ParakeetEngineIntegrationTests.swift`
- Fixtures (Peter provides, see Step 5): `Tests/Fixtures/de_sample.wav`, `Tests/Fixtures/ru_sample.wav`

- [ ] **Step 1: Write the protocol and a fake for downstream tests**

```swift
// Sources/WhisperFlowCore/TranscriptionEngine.swift
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
```

- [ ] **Step 2: Write a basic test for the fake (confirms the protocol compiles and is usable)**

```swift
// Tests/WhisperFlowCoreTests/TranscriptionEngineTests.swift
import XCTest
@testable import WhisperFlowCore

final class TranscriptionEngineTests: XCTestCase {
    func test_fakeEngine_returnsConfiguredText() async throws {
        let engine = FakeTranscriptionEngine(textToReturn: "hallo welt")
        let result = try await engine.transcribe(samples: [0.0, 0.1, 0.2])
        XCTAssertEqual(result, "hallo welt")
    }

    func test_fakeEngine_throwsConfiguredError() async {
        struct DummyError: Error {}
        let engine = FakeTranscriptionEngine(errorToThrow: DummyError())
        do {
            _ = try await engine.transcribe(samples: [])
            XCTFail("expected error")
        } catch is DummyError {
            // expected
        } catch {
            XCTFail("wrong error type")
        }
    }
}
```

Run: `swift test --filter TranscriptionEngineTests`
Expected: PASS (2 tests) — no FluidAudio dependency needed for this part.

- [ ] **Step 3: Inspect the real FluidAudio API before wrapping it**

The exact method name for loading models varies between FluidAudio versions (candidates seen in docs: `configure(models:)` vs `loadModels(_:)`). Don't guess — check the checked-out source:

Run:
```bash
swift package resolve
grep -rn "func .*[Mm]odel" .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/AsrManager.swift
grep -rn "func transcribe" .build/checkouts/FluidAudio/Sources/FluidAudio/ASR/AsrManager.swift
grep -rn "enum AsrModelVersion" -A5 .build/checkouts/FluidAudio/Sources/FluidAudio/**/*.swift
```
Expected: prints the real method signatures. Use whatever they actually are in Step 4 below — if they differ from the sketch here, use the real ones.

- [ ] **Step 4: Write `ParakeetEngine` using the confirmed API**

```swift
// Sources/WhisperFlowCore/ParakeetEngine.swift
import FluidAudio

public final class ParakeetEngine: TranscriptionEngine {
    private let asrManager: AsrManager

    public init() async throws {
        let models = try await AsrModels.downloadAndLoad(version: .v3)
        asrManager = AsrManager(config: .default)
        try await asrManager.configure(models: models) // adjust to the real method name found in Step 3
    }

    public func transcribe(samples: [Float]) async throws -> String {
        let result = try await asrManager.transcribe(samples, source: .system)
        return result.text
    }
}
```

- [ ] **Step 5: Ask Peter for two short fixture recordings, then write the integration test**

This step needs a human: ask Peter to record two ~5 second clips, one speaking German and one speaking Russian, saved as 16kHz mono WAV at `Tests/Fixtures/de_sample.wav` and `Tests/Fixtures/ru_sample.wav`. Do not fabricate audio content — skip the test gracefully if the files aren't there yet.

```swift
// Tests/WhisperFlowCoreTests/ParakeetEngineIntegrationTests.swift
import XCTest
@testable import WhisperFlowCore

final class ParakeetEngineIntegrationTests: XCTestCase {
    func test_german_fixture_transcribes_nonEmpty_germanText() async throws {
        let path = "Tests/Fixtures/de_sample.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Fixture not present yet: \(path)")
        }
        let samples = try WavLoader.loadMono16k(path: path)
        let engine = try await ParakeetEngine()

        let text = try await engine.transcribe(samples: samples)

        XCTAssertFalse(text.isEmpty)
    }

    func test_russian_fixture_transcribes_nonEmpty_russianText() async throws {
        let path = "Tests/Fixtures/ru_sample.wav"
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Fixture not present yet: \(path)")
        }
        let samples = try WavLoader.loadMono16k(path: path)
        let engine = try await ParakeetEngine()

        let text = try await engine.transcribe(samples: samples)

        XCTAssertFalse(text.isEmpty)
    }
}
```

Also add the tiny WAV-loading helper it depends on:

```swift
// Sources/WhisperFlowCore/WavLoader.swift
import Foundation
import AVFoundation

public enum WavLoader {
    public static func loadMono16k(path: String) throws -> [Float] {
        let url = URL(fileURLWithPath: path)
        let file = try AVAudioFile(forReading: url)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try file.read(into: buffer)
        let count = Int(buffer.frameLength)
        return Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: count))
    }
}
```

Run: `swift build && swift test --filter ParakeetEngineIntegrationTests`
Expected: if fixtures are missing, both tests report "skipped" — that's a pass, not a failure. If fixtures exist, both print non-empty transcribed text (model downloads ~600MB on first run, so this can take a few minutes the first time).

- [ ] **Step 6: Commit**

```bash
git add Sources/WhisperFlowCore/TranscriptionEngine.swift Sources/WhisperFlowCore/ParakeetEngine.swift Sources/WhisperFlowCore/WavLoader.swift Tests/WhisperFlowCoreTests/TranscriptionEngineTests.swift Tests/WhisperFlowCoreTests/ParakeetEngineIntegrationTests.swift
git commit -m "Add TranscriptionEngine protocol and Parakeet v3 integration"
```

---

### Task 6: AudioRecorder

**Files:**
- Create: `Sources/WhisperFlowCore/AudioRecorder.swift`
- Test: `Tests/WhisperFlowCoreTests/AudioRecorderTests.swift`

- [ ] **Step 1: Write the protocol, a fake, and a pure helper test**

The real `AVAudioEngine` needs a live mic and can't run in `swift test`. Isolate the one pure piece of logic (converting a captured buffer into `[Float]` samples) so it's testable, and leave the engine wiring behind the protocol for manual verification in Task 12.

```swift
// Tests/WhisperFlowCoreTests/AudioRecorderTests.swift
import XCTest
@testable import WhisperFlowCore

final class AudioRecorderTests: XCTestCase {
    func test_fakeRecorder_returnsBufferedSamplesOnStop() {
        let recorder = FakeAudioRecorder()
        recorder.startRecording()
        recorder.feed(samples: [0.1, 0.2, 0.3])
        let result = recorder.stopRecording()
        XCTAssertEqual(result, [0.1, 0.2, 0.3])
    }

    func test_fakeRecorder_clearsBufferBetweenRecordings() {
        let recorder = FakeAudioRecorder()
        recorder.startRecording()
        recorder.feed(samples: [0.1])
        _ = recorder.stopRecording()

        recorder.startRecording()
        let result = recorder.stopRecording()

        XCTAssertEqual(result, [])
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter AudioRecorderTests`
Expected: FAIL — `FakeAudioRecorder` does not exist

- [ ] **Step 3: Implement the protocol, fake, and real engine wrapper**

```swift
// Sources/WhisperFlowCore/AudioRecorder.swift
import AVFoundation

public protocol AudioRecorder {
    func startRecording()
    func stopRecording() -> [Float]
}

public final class FakeAudioRecorder: AudioRecorder {
    private var buffer: [Float] = []

    public init() {}

    public func startRecording() {
        buffer = []
    }

    public func feed(samples: [Float]) {
        buffer.append(contentsOf: samples)
    }

    public func stopRecording() -> [Float] {
        let result = buffer
        buffer = []
        return result
    }
}

public final class AVAudioEngineRecorder: AudioRecorder {
    private let engine = AVAudioEngine()
    private var buffer: [Float] = []
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false)!

    public init() {}

    public func startRecording() {
        buffer = []
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] pcmBuffer, _ in
            guard let self else { return }
            let outputFrames = AVAudioFrameCount(targetFormat.sampleRate * Double(pcmBuffer.frameLength) / inputFormat.sampleRate)
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: outputFrames) else { return }
            var error: NSError?
            converter.convert(to: outBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            if error == nil, let channelData = outBuffer.floatChannelData {
                let count = Int(outBuffer.frameLength)
                self.buffer.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: count))
            }
        }

        try? engine.start()
    }

    public func stopRecording() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let result = buffer
        buffer = []
        return result
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter AudioRecorderTests`
Expected: PASS (2 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/AudioRecorder.swift Tests/WhisperFlowCoreTests/AudioRecorderTests.swift
git commit -m "Add AudioRecorder protocol with fake and AVAudioEngine implementation"
```

---

### Task 7: TextInserter (AX API + clipboard fallback, TDD on decision logic)

**Files:**
- Create: `Sources/WhisperFlowCore/TextInserter.swift`
- Test: `Tests/WhisperFlowCoreTests/TextInserterTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WhisperFlowCoreTests/TextInserterTests.swift
import XCTest
@testable import WhisperFlowCore

final class TextInserterTests: XCTestCase {
    func test_insert_usesPrimary_whenItSucceeds() throws {
        var primaryCalled = false
        var fallbackCalled = false
        let inserter = CompositeTextInserter(
            primary: { _ in primaryCalled = true },
            fallback: { _ in fallbackCalled = true }
        )

        try inserter.insert(text: "hallo")

        XCTAssertTrue(primaryCalled)
        XCTAssertFalse(fallbackCalled)
    }

    func test_insert_usesFallback_whenPrimaryThrows() throws {
        struct AXFailure: Error {}
        var fallbackCalled = false
        let inserter = CompositeTextInserter(
            primary: { _ in throw AXFailure() },
            fallback: { _ in fallbackCalled = true }
        )

        try inserter.insert(text: "hallo")

        XCTAssertTrue(fallbackCalled)
    }

    func test_insert_throws_whenBothPrimaryAndFallbackFail() {
        struct AXFailure: Error {}
        struct ClipboardFailure: Error {}
        let inserter = CompositeTextInserter(
            primary: { _ in throw AXFailure() },
            fallback: { _ in throw ClipboardFailure() }
        )

        XCTAssertThrowsError(try inserter.insert(text: "hallo")) { error in
            XCTAssertTrue(error is ClipboardFailure)
        }
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter TextInserterTests`
Expected: FAIL — `CompositeTextInserter` does not exist

- [ ] **Step 3: Implement the protocol and composite, plus the real AX/clipboard backends**

```swift
// Sources/WhisperFlowCore/TextInserter.swift
import AppKit
import ApplicationServices

public protocol TextInserter {
    func insert(text: String) throws
}

public struct CompositeTextInserter: TextInserter {
    private let primary: (String) throws -> Void
    private let fallback: (String) throws -> Void

    public init(primary: @escaping (String) throws -> Void, fallback: @escaping (String) throws -> Void) {
        self.primary = primary
        self.fallback = fallback
    }

    public func insert(text: String) throws {
        do {
            try primary(text)
        } catch {
            try fallback(text)
        }
    }
}

public enum AXInsertError: Error {
    case noFocusedElement
    case notSettable
}

public enum AXTextInserter {
    public static func insert(text: String) throws {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard focusResult == .success, let focusedElement = focusedElementRef else {
            throw AXInsertError.noFocusedElement
        }
        let element = focusedElement as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard setResult == .success else {
            throw AXInsertError.notSettable
        }
    }
}

public enum ClipboardTextInserter {
    public static func insert(text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previousContents, forType: .string)
            }
        }
    }
}

public extension CompositeTextInserter {
    static func production() -> CompositeTextInserter {
        CompositeTextInserter(
            primary: { try AXTextInserter.insert(text: $0) },
            fallback: { try ClipboardTextInserter.insert(text: $0) }
        )
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter TextInserterTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/TextInserter.swift Tests/WhisperFlowCoreTests/TextInserterTests.swift
git commit -m "Add TextInserter with AX-primary, clipboard-fallback composite"
```

---

### Task 8: PipelineCoordinator (the core orchestrator, TDD-heavy)

This is the piece that encodes the spec's error-handling rules: discard near-empty recordings, fall back to raw text if cleanup fails, surface a failure if both insert paths fail.

**Files:**
- Create: `Sources/WhisperFlowCore/PipelineCoordinator.swift`
- Test: `Tests/WhisperFlowCoreTests/PipelineCoordinatorTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WhisperFlowCoreTests/PipelineCoordinatorTests.swift
import XCTest
@testable import WhisperFlowCore

private struct FakeCleanupService: CleanupService {
    var textToReturn: String
    var errorToThrow: Error?
    func cleanup(rawText: String) async throws -> String {
        if let errorToThrow { throw errorToThrow }
        return textToReturn
    }
}

private final class FakeTextInserter: TextInserter {
    var insertedText: String?
    var errorToThrow: Error?
    func insert(text: String) throws {
        if let errorToThrow { throw errorToThrow }
        insertedText = text
    }
}

final class PipelineCoordinatorTests: XCTestCase {
    func test_happyPath_insertsCleanedText() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "äh hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        XCTAssertEqual(outcome, .inserted(usedFallback: false))
        XCTAssertEqual(inserter.insertedText, "Hallo Welt.")
    }

    func test_shortRecording_isDiscardedSilently() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hi"),
            cleanupService: FakeCleanupService(textToReturn: "Hi."),
            textInserter: inserter
        )

        // 0.2s at 16kHz = 3200 samples, below the 0.3s / 4800 sample threshold
        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 3200))

        XCTAssertEqual(outcome, .discarded)
        XCTAssertNil(inserter.insertedText)
    }

    func test_cleanupFailure_fallsBackToRawTranscript() async {
        struct CleanupBoom: Error {}
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "raw text"),
            cleanupService: FakeCleanupService(textToReturn: "", errorToThrow: CleanupBoom()),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        XCTAssertEqual(outcome, .inserted(usedFallback: true))
        XCTAssertEqual(inserter.insertedText, "raw text")
    }

    func test_transcriptionFailure_returnsFailedOutcome() async {
        struct AsrBoom: Error {}
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(errorToThrow: AsrBoom()),
            cleanupService: FakeCleanupService(textToReturn: "unused"),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        XCTAssertEqual(outcome, .transcriptionFailed)
        XCTAssertNil(inserter.insertedText)
    }

    func test_bothInsertPathsFail_returnsInsertFailedOutcome() async {
        struct InsertBoom: Error {}
        let inserter = FakeTextInserter()
        inserter.errorToThrow = InsertBoom()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "raw text"),
            cleanupService: FakeCleanupService(textToReturn: "Cleaned."),
            textInserter: inserter
        )

        let outcome = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        XCTAssertEqual(outcome, .insertFailed)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PipelineCoordinatorTests`
Expected: FAIL — `PipelineCoordinator` / `PipelineOutcome` do not exist

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WhisperFlowCore/PipelineCoordinator.swift
public enum PipelineOutcome: Equatable {
    case discarded
    case inserted(usedFallback: Bool)
    case transcriptionFailed
    case insertFailed
}

public final class PipelineCoordinator {
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
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PipelineCoordinatorTests`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/PipelineCoordinator.swift Tests/WhisperFlowCoreTests/PipelineCoordinatorTests.swift
git commit -m "Add PipelineCoordinator encoding the spec's error-handling rules"
```

---

### Task 9: PermissionsManager

**Files:**
- Create: `Sources/WhisperFlowCore/PermissionsManager.swift`
- Test: `Tests/WhisperFlowCoreTests/PermissionsManagerTests.swift`

- [ ] **Step 1: Write the failing tests (pure mapping logic only — the real system calls aren't unit-testable)**

```swift
// Tests/WhisperFlowCoreTests/PermissionsManagerTests.swift
import XCTest
@testable import WhisperFlowCore

final class PermissionsManagerTests: XCTestCase {
    func test_allGranted_producesReadyMessage() {
        let status = PermissionsStatus(microphoneGranted: true, accessibilityGranted: true)
        XCTAssertEqual(status.guidance, .ready)
    }

    func test_missingMicrophone_producesMicrophoneGuidance() {
        let status = PermissionsStatus(microphoneGranted: false, accessibilityGranted: true)
        XCTAssertEqual(status.guidance, .needsMicrophone)
    }

    func test_missingAccessibility_producesAccessibilityGuidance() {
        let status = PermissionsStatus(microphoneGranted: true, accessibilityGranted: false)
        XCTAssertEqual(status.guidance, .needsAccessibility)
    }

    func test_missingBoth_prioritizesMicrophoneGuidance() {
        let status = PermissionsStatus(microphoneGranted: false, accessibilityGranted: false)
        XCTAssertEqual(status.guidance, .needsMicrophone)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `swift test --filter PermissionsManagerTests`
Expected: FAIL — `PermissionsStatus` does not exist

- [ ] **Step 3: Implement the mapping logic plus the real system-call wrapper**

```swift
// Sources/WhisperFlowCore/PermissionsManager.swift
import AVFoundation
import ApplicationServices

public enum PermissionGuidance: Equatable {
    case ready
    case needsMicrophone
    case needsAccessibility
}

public struct PermissionsStatus: Equatable {
    public let microphoneGranted: Bool
    public let accessibilityGranted: Bool

    public init(microphoneGranted: Bool, accessibilityGranted: Bool) {
        self.microphoneGranted = microphoneGranted
        self.accessibilityGranted = accessibilityGranted
    }

    public var guidance: PermissionGuidance {
        if !microphoneGranted { return .needsMicrophone }
        if !accessibilityGranted { return .needsAccessibility }
        return .ready
    }
}

public enum PermissionsManager {
    public static func currentStatus() -> PermissionsStatus {
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axGranted = AXIsProcessTrusted()
        return PermissionsStatus(microphoneGranted: micGranted, accessibilityGranted: axGranted)
    }

    public static func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    public static func promptForAccessibilityAccess() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `swift test --filter PermissionsManagerTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/PermissionsManager.swift Tests/WhisperFlowCoreTests/PermissionsManagerTests.swift
git commit -m "Add PermissionsManager with pure guidance logic and system wrappers"
```

---

### Task 10: App wiring — HotkeyListener, MenuBarController, main.swift

This task is AppKit/CGEventTap glue. It cannot be unit tested — verify it manually per Task 12.

**Files:**
- Create: `Sources/WhisperFlowApp/HotkeyListener.swift`
- Create: `Sources/WhisperFlowApp/MenuBarController.swift`
- Modify: `Sources/WhisperFlowApp/main.swift`

- [ ] **Step 1: Write `HotkeyListener` wrapping the tested `HotkeyStateMachine`**

```swift
// Sources/WhisperFlowApp/HotkeyListener.swift
import Cocoa
import WhisperFlowCore

final class HotkeyListener {
    private var eventTap: CFMachPort?
    private var stateMachine = HotkeyStateMachine()
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?

    func start() {
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, _, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
            listener.handle(event: event)
            return Unmanaged.passUnretained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            print("Failed to create event tap. Is Accessibility permission granted?")
            return
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func handle(event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isDown = flags.contains(.maskAlternate)

        guard let transition = stateMachine.handle(keyCode: keyCode, isDown: isDown) else { return }

        switch transition {
        case .startRecording: onStartRecording?()
        case .stopRecording: onStopRecording?()
        }
    }
}
```

- [ ] **Step 2: Write `MenuBarController`**

```swift
// Sources/WhisperFlowApp/MenuBarController.swift
import Cocoa
import WhisperFlowCore

enum MenuBarState {
    case ready, recording, processing, warning
}

final class MenuBarController {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init() {
        setState(.ready)
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit WhisperFlow", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.menu?.items.forEach { $0.target = self }
    }

    func setState(_ state: MenuBarState) {
        let symbolName: String
        switch state {
        case .ready: symbolName = "mic"
        case .recording: symbolName = "mic.fill"
        case .processing: symbolName = "waveform"
        case .warning: symbolName = "exclamationmark.triangle"
        }
        statusItem.button?.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: state.description)
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

extension MenuBarState {
    var description: String {
        switch self {
        case .ready: return "Ready"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .warning: return "Warning"
        }
    }
}
```

- [ ] **Step 3: Wire it all together in `main.swift`**

```swift
// Sources/WhisperFlowApp/main.swift
import Cocoa
import WhisperFlowCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController!
    private var hotkeyListener: HotkeyListener!
    private var coordinator: PipelineCoordinator!
    private var audioRecorder: AudioRecorder!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = PermissionsManager.currentStatus()
        if status.guidance == .needsAccessibility {
            PermissionsManager.promptForAccessibilityAccess()
        }
        if status.guidance == .needsMicrophone {
            PermissionsManager.requestMicrophoneAccess { _ in }
        }

        menuBarController = MenuBarController()
        audioRecorder = AVAudioEngineRecorder()
        coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(), // replaced once ParakeetEngine() async init is wired in Task 11
            cleanupService: OllamaCleanupService(),
            textInserter: CompositeTextInserter.production()
        )

        hotkeyListener = HotkeyListener()
        hotkeyListener.onStartRecording = { [weak self] in
            self?.menuBarController.setState(.recording)
            self?.audioRecorder.startRecording()
        }
        hotkeyListener.onStopRecording = { [weak self] in
            guard let self else { return }
            self.menuBarController.setState(.processing)
            let samples = self.audioRecorder.stopRecording()
            Task {
                let outcome = await self.coordinator.handleRecordingFinished(samples: samples)
                if case .insertFailed = outcome {
                    self.menuBarController.setState(.warning)
                } else {
                    self.menuBarController.setState(.ready)
                }
            }
        }
        hotkeyListener.start()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowApp
git commit -m "Wire hotkey listener, menu bar, and pipeline into the app entry point"
```

---

### Task 11: Swap in the real Parakeet engine, package as a `.app` bundle

Accessibility/Microphone permissions only register reliably for a real `.app` bundle with a bundle identifier and `LSUIElement`, not a bare SwiftPM executable — this task produces that bundle.

**Files:**
- Modify: `Sources/WhisperFlowApp/main.swift`
- Create: `Resources/Info.plist`
- Create: `scripts/build_app_bundle.sh`

- [ ] **Step 1: Replace the fake engine with the real async-initialized one**

Since `ParakeetEngine.init` is `async`, restructure the delegate to finish setup in a `Task`:

```swift
// Sources/WhisperFlowApp/main.swift — replace applicationDidFinishLaunching's coordinator setup with:
    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = PermissionsManager.currentStatus()
        if status.guidance == .needsAccessibility {
            PermissionsManager.promptForAccessibilityAccess()
        }
        if status.guidance == .needsMicrophone {
            PermissionsManager.requestMicrophoneAccess { _ in }
        }

        menuBarController = MenuBarController()
        audioRecorder = AVAudioEngineRecorder()

        menuBarController.setState(.processing)
        Task {
            let engine = try await ParakeetEngine()
            self.coordinator = PipelineCoordinator(
                transcriptionEngine: engine,
                cleanupService: OllamaCleanupService(),
                textInserter: CompositeTextInserter.production()
            )
            self.menuBarController.setState(.ready)
            self.setupHotkeyListener()
        }
    }

    private func setupHotkeyListener() {
        hotkeyListener = HotkeyListener()
        hotkeyListener.onStartRecording = { [weak self] in
            self?.menuBarController.setState(.recording)
            self?.audioRecorder.startRecording()
        }
        hotkeyListener.onStopRecording = { [weak self] in
            guard let self else { return }
            self.menuBarController.setState(.processing)
            let samples = self.audioRecorder.stopRecording()
            Task {
                let outcome = await self.coordinator.handleRecordingFinished(samples: samples)
                if case .insertFailed = outcome {
                    self.menuBarController.setState(.warning)
                } else {
                    self.menuBarController.setState(.ready)
                }
            }
        }
        hotkeyListener.start()
    }
```

- [ ] **Step 2: Write `Info.plist`**

```xml
<!-- Resources/Info.plist -->
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>WhisperFlow</string>
    <key>CFBundleIdentifier</key>
    <string>com.peter.whisperflow</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>WhisperFlowApp</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>WhisperFlow needs microphone access to transcribe your dictation locally.</string>
</dict>
</plist>
```

- [ ] **Step 3: Write the bundle build script**

```bash
#!/usr/bin/env bash
set -euo pipefail

swift build -c release

APP_NAME="WhisperFlow"
BUNDLE="$APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/WhisperFlowApp" "$BUNDLE/Contents/MacOS/"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

echo "Built $BUNDLE. Move it to /Applications, then grant Microphone + Accessibility access in System Settings > Privacy & Security."
```

- [ ] **Step 4: Build and verify the bundle is well-formed**

Run: `chmod +x scripts/build_app_bundle.sh && ./scripts/build_app_bundle.sh && ls WhisperFlow.app/Contents/MacOS/ && plutil -lint WhisperFlow.app/Contents/Info.plist`
Expected: lists `WhisperFlowApp` binary, `plutil` prints `WhisperFlow.app/Contents/Info.plist: OK`

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowApp/main.swift Resources/Info.plist scripts/build_app_bundle.sh
git commit -m "Wire real Parakeet engine and add .app bundle packaging script"
```

---

### Task 12: Full QA pass

**Automated (opencode runs these):**

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests pass (some `ParakeetEngineIntegrationTests` may report skipped if fixtures are absent — that's fine)

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: `Build complete!`

- [ ] **Step 3: App bundle sanity check**

Run: `./scripts/build_app_bundle.sh && codesign -dv WhisperFlow.app 2>&1 || echo "not signed yet — ad-hoc sign next"`
Expected: bundle builds; if unsigned, ad-hoc sign it:

Run: `codesign --force --deep --sign - WhisperFlow.app && codesign -dv WhisperFlow.app`
Expected: prints signature info, no error

- [ ] **Step 4: Report results and stop**

If any automated step fails, fix the underlying code (not the test) and re-run this task from Step 1. Once everything passes, report done — the remaining checklist below is manual and belongs to Peter, not opencode.

**Manual (Peter runs these — opencode cannot access mic/AX/GUI):**

- [ ] Move `WhisperFlow.app` to `/Applications`, launch it once
- [ ] Grant Microphone access when prompted
- [ ] Grant Accessibility access in System Settings → Privacy & Security → Accessibility
- [ ] Hold right-⌥, say a German sentence with filler words, release — confirm cleaned text appears at the cursor within ~1.5s
- [ ] Repeat in Russian
- [ ] Test insertion in: Notes, Mail, Chrome address bar, VS Code, Slack
- [ ] Quit Ollama (`killall ollama`) and dictate again — confirm raw (uncleaned) text still gets inserted, no crash
- [ ] Try dictating into a password field — confirm no unexpected content appears
- [ ] Tap right-⌥ for under 0.3s — confirm nothing is inserted

---

## Self-Review Notes

- **Spec coverage:** hotkey (Task 3, 10), ASR DE/RU via Parakeet v3 (Task 5), Ollama/Qwen3 cleanup with timeout fallback (Task 4, 8), AX+clipboard insertion (Task 7), menu bar states (Task 10), permissions flow (Task 9), error principle "raw text over no text" (Task 8 tests), setup script (Task 2), testing strategy (unit/integration/manual matrix, Task 12) — all covered.
- **Placeholder scan:** no TBD/TODO; the one open API-name uncertainty (`configure` vs `loadModels` in Task 5) is resolved via a concrete `grep` verification step, not left vague.
- **Type consistency:** `PipelineCoordinator` (Task 8) consumes `TranscriptionEngine`/`CleanupService`/`TextInserter` exactly as defined in Tasks 4, 5, 7; `main.swift` (Task 10/11) constructs them with matching initializer signatures (`OllamaCleanupService()`, `CompositeTextInserter.production()`, `ParakeetEngine()`).
- **Scope:** single subsystem (the V1 core app per the spec) — no decomposition needed.
