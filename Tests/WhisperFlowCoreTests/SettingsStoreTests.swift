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
