import AppKit
import WhisperFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let menuController = MenuBarController()
    private let settings = SettingsStore()
    private var listener: HotkeyListener?
    private var recorder: AVAudioEngineRecorder?
    private var settingsWindowController: SettingsWindowController?
    private var coordinator: PipelineCoordinator?
    private var accessibilityPollTimer: Timer?
    private var isRecording = false
    private var pendingHotkeyOption: HotkeyOption?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        menuController.onOpenSettings = { [weak self] in
            self?.showSettings()
        }
        checkPermissionsAndStart()
    }

    private func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(settings: settings) { [weak self] newOption in
                self?.applyHotkeyChange(newOption)
            }
        }
        settingsWindowController?.show()
    }

    // Per spec, defer hotkey changes made mid-recording until capture finishes.
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

    private func checkPermissionsAndStart() {
        let status = PermissionsManager.currentStatus()
        switch status.guidance {
        case .ready:
            accessibilityPollTimer?.invalidate()
            accessibilityPollTimer = nil
            startEngine()
        case .needsMicrophone:
            PermissionsManager.requestMicrophoneAccess { _ in
                DispatchQueue.main.async { self.checkPermissionsAndStart() }
            }
        case .needsAccessibility:
            PermissionsManager.promptForAccessibilityAccess()
            startPollingForAccessibilityGrant()
        }
    }

    // AXIsProcessTrustedWithOptions has no completion callback — granting access in
    // System Settings happens fully out-of-band, so this is the only way to notice it.
    private func startPollingForAccessibilityGrant() {
        guard accessibilityPollTimer == nil else { return }
        accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if PermissionsManager.currentStatus().accessibilityGranted {
                    self.checkPermissionsAndStart()
                }
            }
        }
    }

    private func startEngine() {
        let rec = AVAudioEngineRecorder()
        let engine = ParakeetEngine()
        let cleanup = OllamaCleanupService(settings: settings)
        let coordinator = PipelineCoordinator(
            transcriptionEngine: engine,
            cleanupService: cleanup,
            textInserter: CompositeTextInserter.production()
        )
        recorder = rec
        self.coordinator = coordinator

        menuController.updateState(.initializing)
        Task {
            do {
                try await engine.loadModels()
                let hotkey = makeHotkeyListener(recorder: rec, coordinator: coordinator, hotkeyOption: settings.hotkeyOption)
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

    private func makeHotkeyListener(
        recorder: AVAudioEngineRecorder,
        coordinator: PipelineCoordinator,
        hotkeyOption: HotkeyOption
    ) -> HotkeyListener {
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
}

let delegate = AppDelegate()
let app = NSApplication.shared
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
