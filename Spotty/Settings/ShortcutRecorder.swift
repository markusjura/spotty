import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Native push button that records one shortcut. Click, Space, or Return starts recording;
/// Escape cancels, Delete clears. While recording it accepts a key with modifiers, two or more
/// modifiers pressed and let go together, or a middle or side mouse button. The registry
/// suspends global shortcuts meanwhile, so existing bindings can be re-recorded.
struct ShortcutRecorder: NSViewRepresentable {
    let commands: CommandRegistry
    let command: CommandID
    let onResult: (ShortcutProblem?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.commandTitle = command.title
        button.shortcut = commands.shortcut(for: command)
        button.onRecordingChange = { [commands, command] isRecording in
            if isRecording { commands.recordingCommand = command }
            else if commands.recordingCommand == command { commands.recordingCommand = nil }
        }
        button.onRecord = { [commands, command, onResult] shortcut in
            onResult(commands.assign(shortcut, to: command))
        }
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.stopRecording() }
}

final class ShortcutRecorderButton: NSButton {
    var onRecord: ((Shortcut?) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var commandTitle = "" { didSet { refresh() } }
    var shortcut: Shortcut? { didSet { if shortcut != oldValue { refresh() } } }
    private var isRecording = false
    private var resignObservation: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var liveModifiers: Shortcut.Modifiers = []
    /// Every modifier held since the last time none were, for modifier-only chords.
    private var chord: Shortcut.Modifiers = []

    init() {
        super.init(frame: .zero)
        bezelStyle = .push
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        toolTip = "Click to record a key, a modifier combination, or a mouse button. Escape cancels; Delete clears."
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 150, height: super.intrinsicContentSize.height) }

    @objc private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        guard let window, window.makeFirstResponder(self) else { return }
        isRecording = true
        resignObservation = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopRecording() }
        }
        // Middle and side buttons may be pressed anywhere over the window.
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, isRecording else { return event }
            finish(.mouse(event.buttonNumber, Shortcut.Modifiers(flags: event.modifierFlags)))
            return nil
        }
        liveModifiers = []
        chord = []
        onRecordingChange?(true)
        refresh()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        if let resignObservation { NotificationCenter.default.removeObserver(resignObservation) }
        resignObservation = nil
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
        onRecordingChange?(false)
        refresh()
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    /// Command-key combinations arrive here before menus handle them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func flagsChanged(with event: NSEvent) {
        guard isRecording else { return super.flagsChanged(with: event) }
        liveModifiers = Shortcut.Modifiers(flags: event.modifierFlags)
        chord.formUnion(liveModifiers)
        if liveModifiers.isEmpty {
            // Letting go of two or more modifiers records them as a chord; a single one is just a slip.
            if chord.count >= 2 { return finish(.modifiers(chord)) }
            chord = []
        }
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        stopRecording()
        return super.resignFirstResponder()
    }

    private func record(_ event: NSEvent) {
        let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift])
        switch Int(event.keyCode) {
        case kVK_Escape where plain:
            stopRecording()
        case kVK_Delete where plain, kVK_ForwardDelete where plain:
            finish(nil)
        default:
            guard let shortcut = Shortcut(keyEvent: event) else { return NSSound.beep() }
            finish(shortcut)
        }
    }

    private func finish(_ shortcut: Shortcut?) {
        stopRecording()
        onRecord?(shortcut)
    }

    private func refresh() {
        let value: String
        if isRecording {
            value = liveModifiers.isEmpty ? "Type Shortcut…" : Shortcut.symbols(liveModifiers) + "…"
        } else {
            value = shortcut?.displayString ?? "Record Shortcut"
        }
        title = value
        setAccessibilityLabel("\(commandTitle) shortcut")
        setAccessibilityValue(isRecording ? "Recording" : (shortcut == nil ? "None" : value))
    }
}
