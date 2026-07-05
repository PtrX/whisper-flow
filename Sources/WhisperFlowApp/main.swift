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

        menuController.updateState(.initializing)
        Task {
            do {
                try await engine.loadModels()
                let hotkey = makeHotkeyListener(recorder: rec, coordinator: coordinator)
                if hotkey.start() {
                    listener = hotkey
                    menuController.updateState(.ready)
                } else {
                    menuController.updateState(.error("Failed to start hotkey listener"))
                }
            } catch {
                menuController.updateState(.error("Model loading failed: \(error.localizedDescription)"))
            }
        }
    }

    private func makeHotkeyListener(recorder: AVAudioEngineRecorder, coordinator: PipelineCoordinator) -> HotkeyListener {
        let hotkey = HotkeyListener(recorder: recorder, coordinator: coordinator)
        hotkey.onStartedRecording = { [weak self] in
            Task { @MainActor in
                self?.menuController.updateState(.recording)
            }
        }
        hotkey.onStoppedRecording = { [weak self] outcome in
            Task { @MainActor in
                if case .insertFailed = outcome {
                    self?.menuController.updateState(.error("Insert failed"))
                } else {
                    self?.menuController.updateState(.ready)
                }
            }
        }
        return hotkey
    }
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
