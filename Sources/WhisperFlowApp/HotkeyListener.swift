import AppKit
import WhisperFlowCore

public final class HotkeyListener {
    private nonisolated(unsafe) var stateMachine = HotkeyStateMachine()
    private let recorder: any AudioRecorder
    private let coordinator: PipelineCoordinator
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init(recorder: AudioRecorder, coordinator: PipelineCoordinator) {
        self.recorder = recorder
        self.coordinator = coordinator
    }

    deinit { stop() }

    public func start() -> Bool {
        let eventMask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
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
        let isDown = type == .keyDown
        guard let transition = stateMachine.handle(keyCode: keyCode, isDown: isDown) else {
            return Unmanaged.passUnretained(event)
        }
        switch transition {
        case .startRecording:
            recorder.startRecording()
            return nil
        case .stopRecording:
            let samples = recorder.stopRecording()
            let coordinator = self.coordinator
            Task { @MainActor in
                _ = await coordinator.handleRecordingFinished(samples: samples)
            }
            return nil
        }
    }
}
