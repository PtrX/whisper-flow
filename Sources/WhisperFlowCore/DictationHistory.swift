public struct DictationHistory: Sendable {
    public static let maxEntries = 10

    private var entries: [String] = []

    public init() {}

    public var all: [String] { entries }

    public mutating func record(_ text: String) {
        entries.insert(text, at: 0)
        if entries.count > Self.maxEntries {
            entries.removeLast(entries.count - Self.maxEntries)
        }
    }
}
