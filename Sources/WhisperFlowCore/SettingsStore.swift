import Foundation

public struct SettingsStore: @unchecked Sendable {
    public static let defaultOllamaModel = "qwen3:4b"
    public static let defaultCleanupTimeout: TimeInterval = 3.0

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var ollamaModel: String {
        get {
            let value = defaults.string(forKey: "ollamaModel")?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty ? Self.defaultOllamaModel : value
        }
        nonmutating set { defaults.set(newValue, forKey: "ollamaModel") }
    }

    public var cleanupTimeout: TimeInterval {
        get {
            defaults.object(forKey: "cleanupTimeout") == nil
                ? Self.defaultCleanupTimeout
                : defaults.double(forKey: "cleanupTimeout")
        }
        nonmutating set { defaults.set(newValue, forKey: "cleanupTimeout") }
    }

    public var cleanupEnabled: Bool {
        get {
            defaults.object(forKey: "cleanupEnabled") == nil
                ? true
                : defaults.bool(forKey: "cleanupEnabled")
        }
        nonmutating set { defaults.set(newValue, forKey: "cleanupEnabled") }
    }

    public var hotkeyOption: HotkeyOption {
        get {
            guard let raw = defaults.string(forKey: "hotkeyOption"),
                  let option = HotkeyOption(rawValue: raw) else {
                return .rightOption
            }
            return option
        }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "hotkeyOption") }
    }
}
