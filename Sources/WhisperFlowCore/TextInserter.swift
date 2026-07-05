import AppKit
import ApplicationServices

public protocol TextInserter: Sendable {
    func insert(text: String) throws
}

public struct CompositeTextInserter: TextInserter, @unchecked Sendable {
    private let primary: (String) throws -> Void
    private let fallback: (String) throws -> Void

    public init(primary: @escaping (String) throws -> Void, fallback: @escaping (String) throws -> Void) {
        self.primary = primary
        self.fallback = fallback
    }

    public func insert(text: String) throws {
        do {
            try primary(text)
        } catch {
            try fallback(text)
        }
    }
}

public enum AXInsertError: Error {
    case noFocusedElement
    case notSettable
}

public enum AXTextInserter {
    public static func insert(text: String) throws {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedElementRef: CFTypeRef?
        let focusResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElementRef)
        guard focusResult == .success, let focusedElement = focusedElementRef else {
            throw AXInsertError.noFocusedElement
        }
        let element = focusedElement as! AXUIElement

        let setResult = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        guard setResult == .success else {
            throw AXInsertError.notSettable
        }
    }
}

public enum ClipboardTextInserter {
    public static func insert(text: String) throws {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let previousContents {
                pasteboard.clearContents()
                pasteboard.setString(previousContents, forType: .string)
            }
        }
    }
}

public extension CompositeTextInserter {
    static func production() -> CompositeTextInserter {
        CompositeTextInserter(
            primary: { try AXTextInserter.insert(text: $0) },
            fallback: { try ClipboardTextInserter.insert(text: $0) }
        )
    }
}
