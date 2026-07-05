import AppKit
import WhisperFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = MenuBarController()
    private var listener: HotkeyListener?
    private var recorder: AVAudioEngineRecorder?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        checkPermissionsAndStart()
    }

    private func checkPermissionsAndStart() {
        let status = PermissionsManager.currentStatus()
        switch status.guidance {
        case .ready:
            startEngine()
        case .needsMicrophone:
            PermissionsManager.requestMicrophoneAccess { _ in
                DispatchQueue.main.async { self.checkPermissionsAndStart() }
            }
        case .needsAccessibility:
            PermissionsManager.promptForAccessibilityAccess()
        }
    }

    private func startEngine() {
        let rec = AVAudioEngineRecorder()
        let engine = ParakeetEngine()
        let cleanup = OllamaCleanupService()
        let coordinator = PipelineCoordinator(
            transcriptionEngine: engine,
            cleanupService: cleanup,
            textInserter: CompositeTextInserter.production()
        )
        recorder = rec

        Task {
            do {
                try await engine.loadModels()
                let hotkey = HotkeyListener(recorder: rec, coordinator: coordinator)
                if hotkey.start() {
                    listener = hotkey
                    await MainActor.run { menuController.updateState(.ready) }
                } else {
                    await MainActor.run { menuController.updateState(.error("Failed to start hotkey listener — check Accessibility permission")) }
                }
            } catch {
                await MainActor.run { menuController.updateState(.error("Model loading failed: \(error.localizedDescription)")) }
            }
        }
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
