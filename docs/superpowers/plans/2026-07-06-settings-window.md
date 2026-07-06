# Settings Window Implementation Plan

> **For agentic workers:** This plan is executed task-by-task by Codex (via the codex plugin). Each task is self-contained TDD: write the failing test, confirm it fails, implement, confirm it passes, commit with the exact command given. Claude (Fable) does live QA on the real system afterwards — do NOT attempt GUI/permission testing yourself. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the hardcoded config values (Ollama model, cleanup timeout, cleanup on/off, hotkey) editable via a native settings window; changes take effect immediately without app restart.

**Architecture:** A `SettingsStore` (typed UserDefaults wrapper, sole source of truth) and a `HotkeyOption` enum live in `WhisperFlowCore` and are fully unit-tested. `OllamaCleanupService` reads settings fresh on every call (no observers needed). The window itself is SwiftUI (`NSHostingController`) in the `WhisperFlowApp` target, opened from a new "Settings…" menu item; hotkey changes restart the `HotkeyListener` via a direct callback.

**Tech Stack:** Swift 6, SwiftUI (first use in this project — isolated to the settings window), AppKit, UserDefaults, swift-testing.

**Spec:** `docs/superpowers/specs/2026-07-06-settings-window-design.md`

---

### Task 1: HotkeyOption enum (TDD)

**Files:**
- Create: `Sources/WhisperFlowCore/HotkeyOption.swift`
- Test: `Tests/WhisperFlowCoreTests/HotkeyOptionTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WhisperFlowCoreTests/HotkeyOptionTests.swift
import Testing
import CoreGraphics
@testable import WhisperFlowCore

struct HotkeyOptionTests {

    @Test func keyCodes_matchMacOSVirtualKeyCodes() {
        #expect(HotkeyOption.rightOption.keyCode == 61)
        #expect(HotkeyOption.leftOption.keyCode == 58)
        #expect(HotkeyOption.rightCommand.keyCode == 54)
        #expect(HotkeyOption.rightControl.keyCode == 62)
        #expect(HotkeyOption.rightShift.keyCode == 60)
    }

    @Test func flagMasks_matchModifierFamilies() {
        #expect(HotkeyOption.rightOption.flagMask == .maskAlternate)
        #expect(HotkeyOption.leftOption.flagMask == .maskAlternate)
        #expect(HotkeyOption.rightCommand.flagMask == .maskCommand)
        #expect(HotkeyOption.rightControl.flagMask == .maskControl)
        #expect(HotkeyOption.rightShift.flagMask == .maskShift)
    }

    @Test func displayNames_areNonEmptyAndUnique() {
        let names = HotkeyOption.allCases.map(\.displayName)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(names).count == names.count)
    }

    @Test func rawValues_roundTrip() {
        for option in HotkeyOption.allCases {
            #expect(HotkeyOption(rawValue: option.rawValue) == option)
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyOptionTests`
Expected: FAIL — `HotkeyOption` does not exist

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WhisperFlowCore/HotkeyOption.swift
import CoreGraphics

public enum HotkeyOption: String, CaseIterable, Sendable {
    case rightOption
    case leftOption
    case rightCommand
    case rightControl
    case rightShift

    public var keyCode: Int64 {
        switch self {
        case .rightOption: return 61
        case .leftOption: return 58
        case .rightCommand: return 54
        case .rightControl: return 62
        case .rightShift: return 60
        }
    }

    public var flagMask: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .rightControl: return .maskControl
        case .rightShift: return .maskShift
        }
    }

    public var displayName: String {
        switch self {
        case .rightOption: return "Right ⌥ (Option)"
        case .leftOption: return "Left ⌥ (Option)"
        case .rightCommand: return "Right ⌘ (Command)"
        case .rightControl: return "Right ⌃ (Control)"
        case .rightShift: return "Right ⇧ (Shift)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter HotkeyOptionTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/HotkeyOption.swift Tests/WhisperFlowCoreTests/HotkeyOptionTests.swift
git commit -m "Add HotkeyOption enum with keycode/flag mappings"
```

---

### Task 2: SettingsStore (TDD)

**Files:**
- Create: `Sources/WhisperFlowCore/SettingsStore.swift`
- Test: `Tests/WhisperFlowCoreTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

Each test uses its own throwaway `UserDefaults` suite so tests never touch real prefs or each other.

```swift
// Tests/WhisperFlowCoreTests/SettingsStoreTests.swift
import Testing
import Foundation
@testable import WhisperFlowCore

struct SettingsStoreTests {

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: UserDefaults(suiteName: "test-\(UUID().uuidString)")!)
    }

    @Test func defaults_matchCurrentHardcodedBehavior() {
        let store = makeStore()
        #expect(store.ollamaModel == "qwen3:4b")
        #expect(store.cleanupTimeout == 3.0)
        #expect(store.cleanupEnabled == true)
        #expect(store.hotkeyOption == .rightOption)
    }

    @Test func writtenValues_persistWithinTheSameSuite() {
        let suiteName = "test-\(UUID().uuidString)"
        let store = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        store.ollamaModel = "llama3.2:3b"
        store.cleanupTimeout = 7.5
        store.cleanupEnabled = false
        store.hotkeyOption = .rightCommand

        let reread = SettingsStore(defaults: UserDefaults(suiteName: suiteName)!)
        #expect(reread.ollamaModel == "llama3.2:3b")
        #expect(reread.cleanupTimeout == 7.5)
        #expect(reread.cleanupEnabled == false)
        #expect(reread.hotkeyOption == .rightCommand)
    }

    @Test func emptyOrWhitespaceModelName_fallsBackToDefault() {
        let store = makeStore()
        store.ollamaModel = "   "
        #expect(store.ollamaModel == "qwen3:4b")
    }

    @Test func unknownHotkeyRawValue_fallsBackToRightOption() {
        let suiteName = "test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set("garbage", forKey: "hotkeyOption")
        let store = SettingsStore(defaults: defaults)
        #expect(store.hotkeyOption == .rightOption)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter SettingsStoreTests`
Expected: FAIL — `SettingsStore` does not exist

- [ ] **Step 3: Write the implementation**

`nonmutating set` because the struct itself never changes — writes go to UserDefaults. `@unchecked Sendable` is safe: UserDefaults is documented thread-safe.

```swift
// Sources/WhisperFlowCore/SettingsStore.swift
import Foundation

public struct SettingsStore: @unchecked Sendable {
    public static let defaultOllamaModel = "qwen3:4b"
    public static let defaultCleanupTimeout: TimeInterval = 3.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var ollamaModel: String {
        get {
            let value = defaults.string(forKey: "ollamaModel")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? Self.defaultOllamaModel : value
        }
        nonmutating set { defaults.set(newValue, forKey: "ollamaModel") }
    }

    public var cleanupTimeout: TimeInterval {
        get {
            defaults.object(forKey: "cleanupTimeout") == nil
                ? Self.defaultCleanupTimeout
                : defaults.double(forKey: "cleanupTimeout")
        }
        nonmutating set { defaults.set(newValue, forKey: "cleanupTimeout") }
    }

    public var cleanupEnabled: Bool {
        get {
            defaults.object(forKey: "cleanupEnabled") == nil
                ? true
                : defaults.bool(forKey: "cleanupEnabled")
        }
        nonmutating set { defaults.set(newValue, forKey: "cleanupEnabled") }
    }

    public var hotkeyOption: HotkeyOption {
        get {
            guard let raw = defaults.string(forKey: "hotkeyOption"),
                  let option = HotkeyOption(rawValue: raw) else {
                return .rightOption
            }
            return option
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "hotkeyOption") }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter SettingsStoreTests`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/SettingsStore.swift Tests/WhisperFlowCoreTests/SettingsStoreTests.swift
git commit -m "Add SettingsStore as typed UserDefaults wrapper"
```

---

### Task 3: Parametrize HotkeyStateMachine target key (TDD)

**Files:**
- Modify: `Sources/WhisperFlowCore/HotkeyState.swift`
- Test: `Tests/WhisperFlowCoreTests/HotkeyStateTests.swift` (append tests, keep existing ones untouched)

- [ ] **Step 1: Append the failing tests to the existing suite**

Append inside the existing `HotkeyStateTests` struct in `Tests/WhisperFlowCoreTests/HotkeyStateTests.swift`:

```swift
    @Test func customTargetKeyCode_triggersTransitions() {
        var machine = HotkeyStateMachine(targetKeyCode: 54) // right command
        #expect(machine.handle(keyCode: 54, isDown: true) == .startRecording)
        #expect(machine.handle(keyCode: 54, isDown: false) == .stopRecording)
    }

    @Test func customTargetKeyCode_ignoresTheOldDefaultKey() {
        var machine = HotkeyStateMachine(targetKeyCode: 54)
        #expect(machine.handle(keyCode: 61, isDown: true) == nil)
        #expect(machine.current == .idle)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter HotkeyStateTests`
Expected: FAIL — no `init(targetKeyCode:)`

- [ ] **Step 3: Modify the implementation**

Replace the body of `HotkeyStateMachine` in `Sources/WhisperFlowCore/HotkeyState.swift` (enums above it stay unchanged):

```swift
public struct HotkeyStateMachine {
    public static let rightOptionKeyCode: Int64 = 61

    private let targetKeyCode: Int64
    public private(set) var current: HotkeyPhase = .idle

    public init(targetKeyCode: Int64 = HotkeyStateMachine.rightOptionKeyCode) {
        self.targetKeyCode = targetKeyCode
    }

    public mutating func handle(keyCode: Int64, isDown: Bool) -> HotkeyTransition? {
        guard keyCode == targetKeyCode else { return nil }

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

- [ ] **Step 4: Run the full core suite to verify old + new tests pass**

Run: `swift test --filter HotkeyStateTests`
Expected: PASS (6 tests — 4 existing + 2 new)

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/HotkeyState.swift Tests/WhisperFlowCoreTests/HotkeyStateTests.swift
git commit -m "Parametrize HotkeyStateMachine target key code"
```

---

### Task 4: Settings-driven OllamaCleanupService (TDD)

**Files:**
- Modify: `Sources/WhisperFlowCore/CleanupService.swift`
- Modify: `Tests/WhisperFlowCoreTests/CleanupServiceTests.swift`

The service currently fixes `model`/`timeout` in its initializer. Change it to hold a `SettingsStore` and read model/timeout/enabled **fresh on every `cleanup` call**, plus a new `CleanupError.disabled`.

- [ ] **Step 1: Update existing tests and add new ones**

In `Tests/WhisperFlowCoreTests/CleanupServiceTests.swift`, the existing tests construct the service as `OllamaCleanupService(session: makeSession(), timeout: ...)`. Add this helper next to `makeSession()`:

```swift
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
```

Then update every existing construction site:
- `OllamaCleanupService(session: makeSession(), timeout: 3.0)` → `OllamaCleanupService(session: makeSession(), settings: makeSettings())`
- `OllamaCleanupService(session: makeSession(), timeout: 0.05)` → `OllamaCleanupService(session: makeSession(), settings: makeSettings(timeout: 0.05))`

And append these new tests to the suite:

```swift
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
            // expected — proves settings are read per call, not captured at init
        } catch {
            Issue.record("expected CleanupError.disabled, got \(error)")
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter CleanupServiceTests`
Expected: FAIL — no `init(session:settings:)`, no `CleanupError.disabled`

- [ ] **Step 3: Modify the implementation**

In `Sources/WhisperFlowCore/CleanupService.swift`:

Add the new error case:

```swift
public enum CleanupError: Error {
    case timeout
    case badStatus(Int)
    case decodingFailed
    case disabled
}
```

Replace the stored properties and initializer of `OllamaCleanupService`:

```swift
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
```

And change the top of `cleanup(rawText:)` to read settings fresh (the rest of the method body — request building, timeout wrapper, status/decoding checks — stays exactly as it is, just using the local `model`/`timeout`):

```swift
    public func cleanup(rawText: String) async throws -> String {
        guard settings.cleanupEnabled else { throw CleanupError.disabled }
        let model = settings.ollamaModel
        let timeout = settings.cleanupTimeout

        let prompt = "\(Self.systemPrompt)\n\nDictated text:\n\(rawText)"
        let body = GenerateRequest(model: model, prompt: prompt, stream: false)
        // ... unchanged from here ...
```

- [ ] **Step 4: Run the full suite (this change touches shared code)**

Run: `swift test`
Expected: PASS — all tests, including the 2 new ones

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowCore/CleanupService.swift Tests/WhisperFlowCoreTests/CleanupServiceTests.swift
git commit -m "Make OllamaCleanupService read settings fresh per call, add disabled state"
```

---

### Task 5: HotkeyListener takes a HotkeyOption

**Files:**
- Modify: `Sources/WhisperFlowApp/HotkeyListener.swift`

App-target glue — no unit tests possible (CGEventTap needs a live session + Accessibility). Verified by build here and live QA later.

- [ ] **Step 1: Change property declarations and initializer**

In `Sources/WhisperFlowApp/HotkeyListener.swift`, replace:

```swift
    private nonisolated(unsafe) var stateMachine = HotkeyStateMachine()
```

with:

```swift
    private let hotkeyOption: HotkeyOption
    private nonisolated(unsafe) var stateMachine: HotkeyStateMachine
```

and replace the initializer:

```swift
    public init(recorder: AudioRecorder, coordinator: PipelineCoordinator, hotkeyOption: HotkeyOption = .rightOption) {
        self.recorder = recorder
        self.coordinator = coordinator
        self.hotkeyOption = hotkeyOption
        self.stateMachine = HotkeyStateMachine(targetKeyCode: hotkeyOption.keyCode)
    }
```

- [ ] **Step 2: Use the option's flag mask in handleEvent**

In `handleEvent`, replace:

```swift
        let isDown = event.flags.contains(.maskAlternate)
```

with:

```swift
        let isDown = event.flags.contains(hotkeyOption.flagMask)
```

- [ ] **Step 3: Verify it builds and existing tests still pass**

Run: `swift build && swift test`
Expected: `Build complete!`, all tests PASS

- [ ] **Step 4: Commit**

```bash
git add Sources/WhisperFlowApp/HotkeyListener.swift
git commit -m "Make HotkeyListener hotkey configurable via HotkeyOption"
```

---

### Task 6: Settings window, menu item, and AppDelegate wiring

**Files:**
- Create: `Sources/WhisperFlowApp/SettingsWindow.swift`
- Modify: `Sources/WhisperFlowApp/MenuBarController.swift`
- Modify: `Sources/WhisperFlowApp/main.swift`

- [ ] **Step 1: Create the SwiftUI settings view + window controller**

```swift
// Sources/WhisperFlowApp/SettingsWindow.swift
import AppKit
import SwiftUI
import WhisperFlowCore

struct SettingsView: View {
    let settings: SettingsStore
    let onHotkeyChange: (HotkeyOption) -> Void

    @State private var model: String
    @State private var timeout: Double
    @State private var cleanupEnabled: Bool
    @State private var hotkey: HotkeyOption

    init(settings: SettingsStore, onHotkeyChange: @escaping (HotkeyOption) -> Void) {
        self.settings = settings
        self.onHotkeyChange = onHotkeyChange
        _model = State(initialValue: settings.ollamaModel)
        _timeout = State(initialValue: settings.cleanupTimeout)
        _cleanupEnabled = State(initialValue: settings.cleanupEnabled)
        _hotkey = State(initialValue: settings.hotkeyOption)
    }

    var body: some View {
        Form {
            Picker("Push-to-talk key", selection: $hotkey) {
                ForEach(HotkeyOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .onChange(of: hotkey) { _, newValue in
                settings.hotkeyOption = newValue
                onHotkeyChange(newValue)
            }

            Toggle("AI cleanup (via Ollama)", isOn: $cleanupEnabled)
                .onChange(of: cleanupEnabled) { _, newValue in
                    settings.cleanupEnabled = newValue
                }

            TextField("Ollama model", text: $model)
                .onChange(of: model) { _, newValue in
                    settings.ollamaModel = newValue
                }
                .disabled(!cleanupEnabled)

            HStack {
                Text("Cleanup timeout")
                Slider(value: $timeout, in: 1...10, step: 0.5)
                    .onChange(of: timeout) { _, newValue in
                        settings.cleanupTimeout = newValue
                    }
                Text(String(format: "%.1f s", timeout))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(!cleanupEnabled)
        }
        .padding(20)
        .frame(width: 400)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let onHotkeyChange: (HotkeyOption) -> Void

    init(settings: SettingsStore, onHotkeyChange: @escaping (HotkeyOption) -> Void) {
        self.settings = settings
        self.onHotkeyChange = onHotkeyChange
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(settings: settings, onHotkeyChange: onHotkeyChange)
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = "WhisperFlow Settings"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
```

- [ ] **Step 2: Add the "Settings…" menu item**

In `Sources/WhisperFlowApp/MenuBarController.swift`, add a callback property at the top of the class:

```swift
    var onOpenSettings: (() -> Void)?
```

In `rebuildMenu()`, directly before the `menu.addItem(.separator())` / Quit block, insert:

```swift
        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
```

And add the action method next to `quit()`:

```swift
    @objc private func openSettings() {
        onOpenSettings?()
    }
```

- [ ] **Step 3: Wire everything in the AppDelegate**

In `Sources/WhisperFlowApp/main.swift`:

Add properties to `AppDelegate`:

```swift
    private let settings = SettingsStore()
    private var settingsWindowController: SettingsWindowController?
    private var coordinator: PipelineCoordinator?
    private var isRecording = false
    private var pendingHotkeyOption: HotkeyOption?
```

In `applicationDidFinishLaunching`, after `NSApp.setActivationPolicy(.accessory)`, wire the menu callback:

```swift
        menuController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
```

Add these methods to `AppDelegate`:

```swift
    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings) { [weak self] newOption in
                self?.applyHotkeyChange(newOption)
            }
        }
        settingsWindowController?.show()
    }

    // Per spec: a hotkey change arriving mid-recording is deferred until the
    // recording finishes, so we never tear down the listener while it's capturing.
    private func applyHotkeyChange(_ option: HotkeyOption) {
        if isRecording {
            pendingHotkeyOption = option
        } else {
            restartHotkeyListener(with: option)
        }
    }

    private func restartHotkeyListener(with option: HotkeyOption) {
        guard let recorder, let coordinator else { return }
        listener?.stop()
        let hotkey = makeHotkeyListener(recorder: recorder, coordinator: coordinator, hotkeyOption: option)
        if hotkey.start() {
            listener = hotkey
        } else {
            menuController.updateState(.error("Failed to restart hotkey listener"))
        }
    }
```

In `startEngine()`, change the cleanup service construction to pass the store, keep a reference to the coordinator, and pass the configured hotkey:

```swift
        let cleanup = OllamaCleanupService(settings: settings)
        let coordinator = PipelineCoordinator(
            transcriptionEngine: engine,
            cleanupService: cleanup,
            textInserter: CompositeTextInserter.production()
        )
        self.coordinator = coordinator
```

and inside the `Task { ... }` block:

```swift
                let hotkey = makeHotkeyListener(recorder: rec, coordinator: coordinator, hotkeyOption: settings.hotkeyOption)
```

Change `makeHotkeyListener` to accept and forward the option, track recording state, and apply a deferred hotkey change when a recording ends:

```swift
    private func makeHotkeyListener(recorder: AVAudioEngineRecorder, coordinator: PipelineCoordinator, hotkeyOption: HotkeyOption) -> HotkeyListener {
        let hotkey = HotkeyListener(recorder: recorder, coordinator: coordinator, hotkeyOption: hotkeyOption)
        hotkey.onStartedRecording = { [weak self] in
            Task { @MainActor in
                self?.isRecording = true
                self?.menuController.updateState(.recording)
            }
        }
        hotkey.onStoppedRecording = { [weak self] outcome in
            Task { @MainActor in
                guard let self else { return }
                self.isRecording = false
                if case .insertFailed = outcome {
                    self.menuController.updateState(.error("Insert failed"))
                } else {
                    self.menuController.updateState(.ready)
                }
                if let pending = self.pendingHotkeyOption {
                    self.pendingHotkeyOption = nil
                    self.restartHotkeyListener(with: pending)
                }
            }
        }
        return hotkey
    }
```

Note: `recorder` is currently declared as `private var recorder: AVAudioEngineRecorder?` — the `guard let recorder` in `restartHotkeyListener` relies on that; do not rename it.

- [ ] **Step 4: Verify it builds and all tests pass**

Run: `swift build && swift test`
Expected: `Build complete!` with no errors (SwiftUI import must not warn), all tests PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/WhisperFlowApp/SettingsWindow.swift Sources/WhisperFlowApp/MenuBarController.swift Sources/WhisperFlowApp/main.swift
git commit -m "Add settings window with live hotkey/cleanup reconfiguration"
```

---

### Task 7: Final automated QA

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests PASS (existing 34 + ~12 new)

- [ ] **Step 2: Release build + bundle**

Run: `swift build -c release && ./scripts/build_app_bundle.sh`
Expected: `Build complete!`, bundle builds and signs (script prints "Built and signed WhisperFlow.app")

- [ ] **Step 3: Report and stop**

Report done. Do NOT attempt to launch the app, click menus, grant permissions, or dictate — that manual QA pass belongs to Claude (Fable) on the live system:

**Manual QA (Fable, after handback):**
- Settings… opens from the menu bar; only one window instance
- Model change to a nonsense name → raw-text fallback on next dictation
- Cleanup toggle off → raw text inserted immediately (no 3s wait)
- Timeout slider change → observable behavior change
- Hotkey switch to right ⌘ while idle → old key dead, new key dictates
- Hotkey switch during an active recording → applied only after the recording finishes
- Double-tap reinsert works with the newly chosen key
- Settings persist across app restart

---

## Self-Review Notes

- **Spec coverage:** SettingsStore incl. empty-model fallback (Task 2), HotkeyOption fixed list (Task 1), parametrized state machine (Task 3), per-call settings read + `.disabled` → existing raw-text fallback (Task 4), listener flag mask/keycode (Task 5), SwiftUI window + single instance + menu item + immediate-apply + mid-recording deferral (Task 6), tests incl. fresh-read proof (Tasks 1–4), manual QA checklist mirroring the spec (Task 7). No gaps found.
- **Placeholder scan:** the one "... unchanged from here ..." in Task 4 Step 3 refers to code shown in full directly above the change site in the same file the worker has open — acceptable; everything else is complete code.
- **Type consistency:** `SettingsStore(defaults:)`, `HotkeyOption.keyCode/flagMask/displayName`, `HotkeyStateMachine(targetKeyCode:)`, `OllamaCleanupService(session:settings:endpoint:)`, `HotkeyListener(recorder:coordinator:hotkeyOption:)`, `makeHotkeyListener(recorder:coordinator:hotkeyOption:)` — cross-checked across tasks.
