import AppKit
import WhisperFlowCore

@MainActor
final class MenuBarController {
    enum AppMenuState {
        case initializing
        case ready
        case error(String)
    }

    private let statusItem: NSStatusItem
    private var currentState: AppMenuState = .initializing {
        didSet { rebuildMenu() }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "WhisperFlow")
        image?.isTemplate = true
        statusItem.button?.image = image
        rebuildMenu()
    }

    func updateState(_ state: AppMenuState) {
        currentState = state
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = PermissionsManager.currentStatus()

        switch status.guidance {
        case .ready:
            switch currentState {
            case .initializing:
                menu.addItem(withTitle: "Loading models…", action: nil, keyEquivalent: "")
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
        let quit = menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.target = self

        statusItem.menu = menu
    }

    @objc private func requestMic() {
        PermissionsManager.requestMicrophoneAccess { _ in
            DispatchQueue.main.async { self.rebuildMenu() }
        }
    }

    @objc private func requestAX() {
        PermissionsManager.promptForAccessibilityAccess()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
