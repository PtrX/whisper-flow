import AVFoundation
@preconcurrency import ApplicationServices

public enum PermissionGuidance: Equatable {
    case ready
    case needsMicrophone
    case needsAccessibility
}

public struct PermissionsStatus: Equatable {
    public let microphoneGranted: Bool
    public let accessibilityGranted: Bool

    public init(microphoneGranted: Bool, accessibilityGranted: Bool) {
        self.microphoneGranted = microphoneGranted
        self.accessibilityGranted = accessibilityGranted
    }

    public var guidance: PermissionGuidance {
        if !microphoneGranted { return .needsMicrophone }
        if !accessibilityGranted { return .needsAccessibility }
        return .ready
    }
}

public enum PermissionsManager {
    public static func currentStatus() -> PermissionsStatus {
        let micGranted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let axGranted = AXIsProcessTrusted()
        return PermissionsStatus(microphoneGranted: micGranted, accessibilityGranted: axGranted)
    }

    public static func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
    }

    public static func promptForAccessibilityAccess() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
