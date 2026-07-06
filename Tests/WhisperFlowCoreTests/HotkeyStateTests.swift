import Testing
@testable import WhisperFlowCore

@Suite struct HotkeyStateTests {
    @Test func rightOptionKeyDown_fromIdle_transitionsToRecording() {
        var machine = HotkeyStateMachine()
        let transition = machine.handle(keyCode: 61, isDown: true)
        #expect(transition == .startRecording)
        #expect(machine.current == .recording)
    }

    @Test func rightOptionKeyUp_fromRecording_transitionsToIdle() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(keyCode: 61, isDown: true)
        let transition = machine.handle(keyCode: 61, isDown: false)
        #expect(transition == .stopRecording)
        #expect(machine.current == .idle)
    }

    @Test func otherKeyCode_isIgnored() {
        var machine = HotkeyStateMachine()
        let transition = machine.handle(keyCode: 58, isDown: true)
        #expect(transition == nil)
        #expect(machine.current == .idle)
    }

    @Test func repeatedKeyDown_whileRecording_isIgnored() {
        var machine = HotkeyStateMachine()
        _ = machine.handle(keyCode: 61, isDown: true)
        let transition = machine.handle(keyCode: 61, isDown: true)
        #expect(transition == nil)
        #expect(machine.current == .recording)
    }

    @Test func customTargetKeyCode_triggersTransitions() {
        var machine = HotkeyStateMachine(targetKeyCode: 54)
        #expect(machine.handle(keyCode: 54, isDown: true) == .startRecording)
        #expect(machine.handle(keyCode: 54, isDown: false) == .stopRecording)
    }

    @Test func customTargetKeyCode_ignoresTheOldDefaultKey() {
        var machine = HotkeyStateMachine(targetKeyCode: 54)
        #expect(machine.handle(keyCode: 61, isDown: true) == nil)
        #expect(machine.current == .idle)
    }
}
