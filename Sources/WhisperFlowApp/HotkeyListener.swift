import AppKit
import WhisperFlowCore

public final class HotkeyListener {
    public var onStartedRecording: (@Sendable () -> Void)?
    public var onStoppedRecording: (@Sendable (PipelineOutcome) -> Void)?

    private let hotkeyOption: HotkeyOption
    private nonisolated(unsafe) var stateMachine: HotkeyStateMachine
    private nonisolated(unsafe) var doubleTapDetector = DoubleTapDetector()
    private nonisolated(unsafe) var pressStartTime: TimeInterval?
    private let recorder: any AudioRecorder
    private let coordinator: PipelineCoordinator
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(recorder: AudioRecorder, coordinator: PipelineCoordinator, hotkeyOption: HotkeyOption = .rightOption) {
        self.recorder = recorder
        self.coordinator = coordinator
        self.hotkeyOption = hotkeyOption
        self.stateMachine = HotkeyStateMachine(targetKeyCode: hotkeyOption.keyCode)
    }

    deinit { stop() }

    public func start() -> Bool {
        // Right-Option pressed alone is a pure modifier key — macOS never sends
        // .keyDown/.keyUp for it, only .flagsChanged. Listening for keyDown/keyUp
        // meant this tap could never see the hotkey at all.
        let eventMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { proxy, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let listener = Unmanaged<HotkeyListener>.fromOpaque(refcon).takeUnretainedValue()
                return listener.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    public func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let keyCode = Int64(event.getIntegerValueField(.keyboardEventKeycode))
        let isDown = event.flags.contains(hotkeyOption.flagMask)
        guard let transition = stateMachine.handle(keyCode: keyCode, isDown: isDown) else {
            return Unmanaged.passUnretained(event)
        }
        let now = TimeInterval(event.timestamp) / 1_000_000_000

        switch transition {
        case .startRecording:
            pressStartTime = now
            recorder.startRecording()
            onStartedRecording?()
            return nil
        case .stopRecording:
            let samples = recorder.stopRecording()
            let pressDuration = now - (pressStartTime ?? now)
            let isDoubleTap = doubleTapDetector.handleRelease(pressDuration: pressDuration, at: now)
            let coordinator = self.coordinator
            let onDone = onStoppedRecording

            if isDoubleTap {
                Task { @MainActor in
                    onDone?(coordinator.reinsertLastTranscription())
                }
                return nil
            }

            Task { @MainActor in
                let outcome = await coordinator.handleRecordingFinished(samples: samples)
                onDone?(outcome)
            }
            return nil
        }
    }
}
