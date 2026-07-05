import Testing
@testable import WhisperFlowCore

struct PermissionsManagerTests {

    @Test func allGranted_producesReadyMessage() {
        let status = PermissionsStatus(microphoneGranted: true, accessibilityGranted: true)
        #expect(status.guidance == .ready)
    }

    @Test func missingMicrophone_producesMicrophoneGuidance() {
        let status = PermissionsStatus(microphoneGranted: false, accessibilityGranted: true)
        #expect(status.guidance == .needsMicrophone)
    }

    @Test func missingAccessibility_producesAccessibilityGuidance() {
        let status = PermissionsStatus(microphoneGranted: true, accessibilityGranted: false)
        #expect(status.guidance == .needsAccessibility)
    }

    @Test func missingBoth_prioritizesMicrophoneGuidance() {
        let status = PermissionsStatus(microphoneGranted: false, accessibilityGranted: false)
        #expect(status.guidance == .needsMicrophone)
    }
}
