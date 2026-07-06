import AppKit
import SwiftUI
import WhisperFlowCore

struct SettingsView: View {
    let settings: SettingsStore
    let onHotkeyChange: (HotkeyOption) -> Void

    @State private var model: String
    @State private var timeout: Double
    @State private var cleanupEnabled: Bool
    @State private var hotkey: HotkeyOption

    init(settings: SettingsStore, onHotkeyChange: @escaping (HotkeyOption) -> Void) {
        self.settings = settings
        self.onHotkeyChange = onHotkeyChange
        _model = State(initialValue: settings.ollamaModel)
        _timeout = State(initialValue: settings.cleanupTimeout)
        _cleanupEnabled = State(initialValue: settings.cleanupEnabled)
        _hotkey = State(initialValue: settings.hotkeyOption)
    }

    var body: some View {
        Form {
            Picker("Push-to-talk key", selection: $hotkey) {
                ForEach(HotkeyOption.allCases, id: \.self) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .onChange(of: hotkey) { _, newValue in
                settings.hotkeyOption = newValue
                onHotkeyChange(newValue)
            }

            Toggle("AI cleanup (via Ollama)", isOn: $cleanupEnabled)
                .onChange(of: cleanupEnabled) { _, newValue in
                    settings.cleanupEnabled = newValue
                }

            TextField("Ollama model", text: $model)
                .onChange(of: model) { _, newValue in
                    settings.ollamaModel = newValue
                }
                .disabled(!cleanupEnabled)

            HStack {
                Text("Cleanup timeout")
                Slider(value: $timeout, in: 1...10, step: 0.5)
                    .onChange(of: timeout) { _, newValue in
                        settings.cleanupTimeout = newValue
                    }
                Text(String(format: "%.1f s", timeout))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            .disabled(!cleanupEnabled)
        }
        .padding(20)
        .frame(width: 400)
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let settings: SettingsStore
    private let onHotkeyChange: (HotkeyOption) -> Void

    init(settings: SettingsStore, onHotkeyChange: @escaping (HotkeyOption) -> Void) {
        self.settings = settings
        self.onHotkeyChange = onHotkeyChange
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = SettingsView(settings: settings, onHotkeyChange: onHotkeyChange)
        let win = NSWindow(contentViewController: NSHostingController(rootView: view))
        win.title = "WhisperFlow Settings"
        win.styleMask = [.titled, .closable]
        win.isReleasedWhenClosed = false
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
