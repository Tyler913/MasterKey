import AppKit
import SwiftUI
import BridgeCore

/// Captures only keyboard events directed at MasterKey while its recorder is active.
struct ShortcutRecorder: NSViewRepresentable {
    @Binding var configuration: Configuration

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.font = .systemFont(ofSize: NSFont.systemFontSize)
        button.setAccessibilityIdentifier("shortcutRecorder")
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.storedTitle = configuration.outputTitle
        button.setAccessibilityLabel(L10n.text(.recordShortcut))
        button.setAccessibilityHelp(L10n.text(.recordShortcutHint))
        button.onCommit = { captured in configuration = captured.applying(to: configuration) }
        button.refreshTitle()
    }
}

final class RecorderButton: NSButton {
    var storedTitle = ""
    var onCommit: ((CapturedShortcut) -> Void)?
    private var capture = ShortcutCapture()
    private var monitor: Any?
    private var recording = false

    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        target = self
        action = #selector(toggleRecording)
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }

    @objc private func toggleRecording() {
        if recording { stopRecording(); return }
        capture = ShortcutCapture()
        recording = true
        window?.makeFirstResponder(self)
        title = L10n.text(.pressShortcut)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak self] event in
            guard let self, self.recording, event.window === self.window else { return event }
            if event.type == .flagsChanged {
                if self.capture.modifierChanged(keyCode: event.keyCode) {
                    let modifiers = self.capture.modifierTitle
                    self.title = modifiers.isEmpty ? L10n.text(.pressShortcut) : modifiers + " + …"
                    return nil
                }
                if event.keyCode == 63 { self.title = L10n.text(.useFnMode); return nil }
            } else if event.type == .keyDown {
                if event.keyCode == 53 { self.stopRecording(); return nil }
                if let shortcut = self.capture.shortcut(for: event.keyCode, flags: UInt64(event.modifierFlags.rawValue)) {
                    self.stopRecording()
                    self.onCommit?(shortcut)
                } else { self.title = L10n.text(.unsupportedShortcutKey) }
                return nil
            }
            return event
        }
    }

    func refreshTitle() { if !recording { title = storedTitle } }

    private func stopRecording() {
        recording = false
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        title = storedTitle
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopRecording() }
    }
}
