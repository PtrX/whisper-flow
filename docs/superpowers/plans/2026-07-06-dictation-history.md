# Dictation History Implementation Plan

> **For agentic workers:** This plan is executed task-by-task by Codex (via the codex plugin). Each task is self-contained TDD: write the failing test, confirm it fails, implement, confirm it passes. **Do NOT run `git add`/`git commit` — the sandbox cannot write to `.git` (`index.lock: Operation not permitted`) and this has failed before. Just implement + verify with `swift build`/`swift test`, then move to the next task. List the exact files touched per task in your final report.** Claude does the commits and all live/manual QA afterwards — do not attempt to launch the app or click UI.

**Goal:** A "History" submenu showing the last 10 dictations; clicking one re-inserts it at the cursor. In-memory only, cleared on quit.

**Architecture:** A small `DictationHistory` ring-buffer struct in `WhisperFlowCore`, owned internally by `PipelineCoordinator` (no constructor change). `MenuBarController` builds the submenu from a provider closure at each `rebuildMenu()` call (which already re-runs after every dictation).

**Tech Stack:** Swift 6, swift-testing.

**Spec:** `docs/superpowers/specs/2026-07-06-history-design.md`

---

### Task 1: DictationHistory (TDD)

**Files:**
- Create: `Sources/WhisperFlowCore/DictationHistory.swift`
- Test: `Tests/WhisperFlowCoreTests/DictationHistoryTests.swift`

- [ ] **Step 1: Write the failing tests**

```swift
// Tests/WhisperFlowCoreTests/DictationHistoryTests.swift
import Testing
@testable import WhisperFlowCore

struct DictationHistoryTests {

    @Test func startsEmpty() {
        let history = DictationHistory()
        #expect(history.all.isEmpty)
    }

    @Test func record_addsMostRecentFirst() {
        var history = DictationHistory()
        history.record("first")
        history.record("second")
        #expect(history.all == ["second", "first"])
    }

    @Test func record_capsAtMaxEntries_droppingOldest() {
        var history = DictationHistory()
        for i in 1...11 {
            history.record("entry \(i)")
        }
        #expect(history.all.count == 10)
        #expect(history.all.first == "entry 11")
        #expect(history.all.last == "entry 2")
        #expect(!history.all.contains("entry 1"))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter DictationHistoryTests`
Expected: FAIL — `DictationHistory` does not exist

- [ ] **Step 3: Write the implementation**

```swift
// Sources/WhisperFlowCore/DictationHistory.swift
public struct DictationHistory: Sendable {
    public static let maxEntries = 10

    private var entries: [String] = []

    public init() {}

    public var all: [String] { entries }

    public mutating func record(_ text: String) {
        entries.insert(text, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --filter DictationHistoryTests`
Expected: PASS (3 tests)

- [ ] **Step 5: Do NOT commit.** Note the two files created for the final report.

---

### Task 2: PipelineCoordinator uses DictationHistory + exposes it (TDD)

**Files:**
- Modify: `Sources/WhisperFlowCore/PipelineCoordinator.swift`
- Modify: `Tests/WhisperFlowCoreTests/PipelineCoordinatorTests.swift`

Replace the single `lastInsertedText: String?` with a `DictationHistory`, keeping `reinsertLastTranscription()`'s existing behavior (and existing tests) unchanged, and add `historyEntries` + `insertHistoryEntry(at:)`.

- [ ] **Step 1: Append the failing tests**

Append inside the existing `PipelineCoordinatorTests` struct in `Tests/WhisperFlowCoreTests/PipelineCoordinatorTests.swift` (the existing `FakeCleanupService`/`FakeTextInserter` above the struct stay as-is):

```swift
    @Test func historyEntries_listsPastDictationsMostRecentFirst() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.2, count: 16000))

        #expect(coordinator.historyEntries == ["Hallo Welt. ", "Hallo Welt. "])
    }

    @Test func historyEntries_isEmpty_beforeAnyDictation() {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "unused"),
            cleanupService: FakeCleanupService(textToReturn: "unused"),
            textInserter: inserter
        )

        #expect(coordinator.historyEntries.isEmpty)
    }

    @Test func insertHistoryEntry_insertsTheChosenEntry() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        let outcome = coordinator.insertHistoryEntry(at: 0)

        #expect(outcome == .reinserted)
        #expect(inserter.allInsertedTexts == ["Hallo Welt. ", "Hallo Welt. "])
    }

    @Test func insertHistoryEntry_withOutOfRangeIndex_returnsDiscarded() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))

        let outcome = coordinator.insertHistoryEntry(at: 5)

        #expect(outcome == .discarded)
    }

    @Test func insertHistoryEntry_whenInsertThrows_returnsInsertFailed() async {
        let inserter = FakeTextInserter()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: FakeTranscriptionEngine(textToReturn: "hallo welt"),
            cleanupService: FakeCleanupService(textToReturn: "Hallo Welt."),
            textInserter: inserter
        )
        _ = await coordinator.handleRecordingFinished(samples: Array(repeating: 0.1, count: 16000))
        struct InsertBoom: Error {}
        inserter.errorToThrow = InsertBoom()

        let outcome = coordinator.insertHistoryEntry(at: 0)

        #expect(outcome == .insertFailed)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter PipelineCoordinatorTests`
Expected: FAIL — no `historyEntries`/`insertHistoryEntry`

- [ ] **Step 3: Modify the implementation**

In `Sources/WhisperFlowCore/PipelineCoordinator.swift`, replace:

```swift
    private var lastInsertedText: String?
```

with:

```swift
    private var history = DictationHistory()
```

Replace the line `lastInsertedText = textToInsert` (at the end of `handleRecordingFinished`, right before `return .inserted(usedFallback: usedFallback)`) with:

```swift
        history.record(textToInsert)
```

Replace the body of `reinsertLastTranscription()`:

```swift
    public func reinsertLastTranscription() -> PipelineOutcome {
        guard let mostRecent = history.all.first else {
            return .discarded
        }
        do {
            try textInserter.insert(text: mostRecent)
        } catch {
            return .insertFailed
        }
        return .reinserted
    }
```

Add these two new members right after it:

```swift
    /// Past dictations, most recent first. Empty until the first successful insert.
    public var historyEntries: [String] { history.all }

    /// Re-inserts a specific history entry (from `historyEntries`) at the cursor.
    public func insertHistoryEntry(at index: Int) -> PipelineOutcome {
        guard history.all.indices.contains(index) else {
            return .discarded
        }
        do {
            try textInserter.insert(text: history.all[index])
        } catch {
            return .insertFailed
        }
        return .reinserted
    }
```

- [ ] **Step 4: Run the full core suite (this touches shared code)**

Run: `swift test`
Expected: PASS — all tests, old and new

- [ ] **Step 5: Do NOT commit.** Note the two files modified for the final report.

---

### Task 3: History submenu in MenuBarController

**Files:**
- Modify: `Sources/WhisperFlowApp/MenuBarController.swift`

App-target glue — no unit tests possible (NSMenu construction). Verified by build here; live-clicked later.

- [ ] **Step 1: Add the two new callback/provider properties**

Right under `var onOpenSettings: (() -> Void)?` in `Sources/WhisperFlowApp/MenuBarController.swift`, add:

```swift
    var historyProvider: (() -> [String])?
    var onSelectHistoryEntry: ((Int) -> Void)?
```

- [ ] **Step 2: Build the submenu and insert it into rebuildMenu()**

Add this new private method anywhere in the class body:

```swift
    private func buildHistorySubmenu() -> NSMenu {
        let submenu = NSMenu()
        let entries = historyProvider?() ?? []
        if entries.isEmpty {
            let empty = submenu.addItem(withTitle: "No dictations yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for (index, text) in entries.enumerated() {
                let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
                let item = submenu.addItem(withTitle: preview, action: #selector(selectHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
            }
        }
        return submenu
    }

    @objc private func selectHistoryEntry(_ sender: NSMenuItem) {
        onSelectHistoryEntry?(sender.tag)
    }
```

In `rebuildMenu()`, directly before the `menu.addItem(.separator())` that precedes the "Settings…" item, insert:

```swift
        menu.addItem(.separator())
        let historyItem = menu.addItem(withTitle: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistorySubmenu()
```

(There will now be two separators in a row before "Settings…" in the `.ready`/`.needsMicrophone`/`.needsAccessibility` cases where one already existed — that's fine, but to keep the menu clean, this new separator+History block replaces the single existing `menu.addItem(.separator())` line that currently sits directly above `let settingsItem = ...`. Do not add a duplicate.)

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Do NOT commit.** Note the file modified for the final report.

---

### Task 4: Wire history provider/selection in AppDelegate

**Files:**
- Modify: `Sources/WhisperFlowApp/main.swift`

- [ ] **Step 1: Wire the two new MenuBarController properties**

In `applicationDidFinishLaunching`, right after the existing `menuController.onOpenSettings = { ... }` assignment, add:

```swift
        menuController.historyProvider = { [weak self] in
            self?.coordinator?.historyEntries ?? []
        }
        menuController.onSelectHistoryEntry = { [weak self] index in
            guard let self, let coordinator = self.coordinator else { return }
            let outcome = coordinator.insertHistoryEntry(at: index)
            if case .insertFailed = outcome {
                self.menuController.updateState(.error("Insert failed"))
            } else {
                self.menuController.updateState(.ready)
            }
        }
```

`coordinator` is already a stored `private var coordinator: PipelineCoordinator?` on `AppDelegate` (set inside `startEngine()`) — do not redeclare it.

- [ ] **Step 2: Verify it builds and the full suite passes**

Run: `swift build && swift test`
Expected: `Build complete!`, all tests PASS

- [ ] **Step 3: Do NOT commit.** Note the file modified for the final report.

---

### Task 5: Final automated check and report

- [ ] **Step 1: Full test suite**

Run: `swift test`
Expected: all tests PASS (46 existing + ~7 new)

- [ ] **Step 2: Release build**

Run: `swift build -c release`
Expected: `Build complete!`

- [ ] **Step 3: Report and stop**

List every file created/modified, grouped by task (1: DictationHistory.swift + test; 2: PipelineCoordinator.swift + test; 3: MenuBarController.swift; 4: main.swift), plus the final `swift test` output. Do not commit, do not launch the app, do not click any UI — that's handled separately.

---

## Self-Review Notes

- **Spec coverage:** ring buffer capped at 10 most-recent-first (Task 1), `PipelineCoordinator` exposing history without a constructor change (Task 2), submenu + empty state + truncation (Task 3), wiring with the same error-handling pattern as the existing double-tap path (Task 4). No gaps.
- **Placeholder scan:** none found.
- **Type consistency:** `DictationHistory.all`/`record(_:)`, `PipelineCoordinator.historyEntries`/`insertHistoryEntry(at:)`, `MenuBarController.historyProvider`/`onSelectHistoryEntry` — consistent across all four tasks.
