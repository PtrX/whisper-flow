import AppKit
import WhisperFlowCore

@MainActor
final class MenuBarController {
    var onOpenSettings: (() -> Void)?
    var historyProvider: (() -> [String])?
    var onSelectHistoryEntry: ((Int) -> Void)?

    enum AppMenuState {
        case initializing
        case recording
        case processing
        case ready
        case error(String)
    }

    private let statusItem: NSStatusItem
    private var currentState: AppMenuState = .initializing {
        didSet { rebuildMenu() }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // rebuildMenu() only populates the dropdown — without setting an image/title here too,
        // the status item button is empty and renders as an invisible sliver in the menu bar
        // until updateState() first fires, which never happens while gated on permissions.
        updateIcon(currentState)
        rebuildMenu()
    }

    func updateState(_ state: AppMenuState) {
        currentState = state
        updateIcon(state)
    }

    private func updateIcon(_ state: AppMenuState) {
        let symbolName: String
        switch state {
        case .initializing, .ready: symbolName = "mic.fill"
        case .recording: symbolName = "record.circle"
        case .processing: symbolName = "waveform"
        case .error: symbolName = "exclamationmark.triangle"
        }
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WhisperFlow")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = PermissionsManager.currentStatus()

        switch status.guidance {
        case .ready:
            switch currentState {
            case .initializing:
                menu.addItem(withTitle: "Loading models…", action: nil, keyEquivalent: "")
            case .recording:
                let item = menu.addItem(withTitle: "Recording… press Right ⌥ to stop", action: nil, keyEquivalent: "")
                item.isEnabled = false
            case .processing:
                let item = menu.addItem(withTitle: "Transcribing…", action: nil, keyEquivalent: "")
                item.isEnabled = false
            case .ready:
                let item = menu.addItem(withTitle: "Ready — hold Right ⌥ to dictate", action: nil, keyEquivalent: "")
                item.isEnabled = false
            case .error(let msg):
                let item = menu.addItem(withTitle: "Error: \(msg)", action: nil, keyEquivalent: "")
                item.isEnabled = false
            }
        case .needsMicrophone:
            let item = menu.addItem(withTitle: "Grant Microphone Access…", action: #selector(requestMic), keyEquivalent: "")
            item.target = self
        case .needsAccessibility:
            let item = menu.addItem(withTitle: "Grant Accessibility Access…", action: #selector(requestAX), keyEquivalent: "")
            item.target = self
        }

        menu.addItem(.separator())
        let historyItem = menu.addItem(withTitle: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = buildHistorySubmenu()

        menu.addItem(.separator())
        let settingsItem = menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self

        menu.addItem(.separator())
        let quit = menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        statusItem.menu = menu
    }

    private func buildHistorySubmenu() -> NSMenu {
        let submenu = NSMenu()
        let entries = historyProvider?() ?? []
        if entries.isEmpty {
            let empty = submenu.addItem(withTitle: "No dictations yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
        } else {
            for (index, text) in entries.enumerated() {
                let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
                let item = submenu.addItem(withTitle: preview, action: #selector(selectHistoryEntry(_:)), keyEquivalent: "")
                item.target = self
                item.tag = index
            }
        }
        return submenu
    }

    @objc private func selectHistoryEntry(_ sender: NSMenuItem) {
        onSelectHistoryEntry?(sender.tag)
    }

    @objc private func requestMic() {
        PermissionsManager.requestMicrophoneAccess { _ in
            DispatchQueue.main.async { self.rebuildMenu() }
        }
    }

    @objc private func requestAX() {
        PermissionsManager.promptForAccessibilityAccess()
    }

    @objc private func openSettings() {
        onOpenSettings?()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
