import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Button that records one shortcut, drawn like Raycast's hotkey recorder: plain text at rest, a
/// thin border on hover, a thick border while recording, and a clear button on hover once a
/// shortcut is set. Click, Space, or Return starts recording; Escape cancels, Delete or the clear
/// button clears. While recording it accepts a key with modifiers, two or more
/// modifiers pressed and let go together, or a middle or side mouse button. The registry
/// suspends global shortcuts meanwhile, so existing bindings can be re-recorded.
struct ShortcutRecorder: NSViewRepresentable {
    let commands: CommandRegistry
    let slot: ShortcutSlot
    let onResult: (ShortcutProblem?) -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton { ShortcutRecorderButton() }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        button.commandTitle = slot.index == 0 ? slot.command.title : "\(slot.command.title) second"
        button.placeholder = slot.index == 0 ? "Record Shortcut" : "Add Shortcut"
        button.shortcut = commands.shortcut(for: slot)
        button.onRecordingChange = { [commands, slot] isRecording in
            if isRecording { commands.recordingCommand = slot.command }
            else if commands.recordingCommand == slot.command { commands.recordingCommand = nil }
        }
        button.onRecord = { [commands, slot, onResult] shortcut in
            onResult(commands.assign(shortcut, to: slot))
        }
    }

    static func dismantleNSView(_ button: ShortcutRecorderButton, coordinator: ()) { button.stopRecording() }
}

final class ShortcutRecorderButton: NSButton {
    var onRecord: ((Shortcut?) -> Void)?
    var onRecordingChange: ((Bool) -> Void)?
    var commandTitle = "" { didSet { refresh() } }
    var placeholder = "Record Shortcut" { didSet { if placeholder != oldValue { refresh() } } }
    var shortcut: Shortcut? { didSet { if shortcut != oldValue { refresh() } } }
    private var isRecording = false
    private var resignObservation: NSObjectProtocol?
    private var mouseMonitor: Any?
    private var liveModifiers: Shortcut.Modifiers = []
    /// Every modifier held since the last time none were, for modifier-only chords.
    private var chord: Shortcut.Modifiers = []
    private var isHovering = false { didSet { needsDisplay = true } }

    // Raycast's hotkey recorder colors, except the recording border.
    private static let valueColor = NSColor.settings(light: 0x000000, dark: 0xFFFFFF)
    private static let placeholderColor = NSColor.settings(light: 0x959595, dark: 0x757575)
    private static let hoverBorder = NSColor.settings(light: 0xC7C7C7, dark: 0x474747)
    /// The accent color, like the other selected controls, so recording reads clearly as active.
    private static let recordingBorder = NSColor.controlAccentColor
    private static let clearColor = NSColor.settings(light: 0x707070, dark: 0x979797)
    private static let font = NSFont.systemFont(ofSize: 13)
    /// The visible box is 142 × 26 pt; the view is 1 pt larger on each side for the recording border.
    private static let boxInset: CGFloat = 1
    private static let textInset: CGFloat = 8

    init() {
        super.init(frame: .zero)
        isBordered = false
        // The recording border marks focus instead.
        focusRingType = .none
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(toggleRecording)
        toolTip = "Click to record a key, a modifier combination, or a mouse button. Escape cancels; Delete clears."
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: 144, height: 28) }

    private var box: NSRect { bounds.insetBy(dx: Self.boxInset, dy: Self.boxInset) }

    /// The clear button's hit area, present while hovering a set shortcut.
    private var clearRect: NSRect? {
        guard isHovering, !isRecording, shortcut != nil else { return nil }
        return NSRect(x: box.maxX - 24, y: box.minY, width: 24, height: box.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: box, xRadius: 5, yRadius: 5)
        if isRecording {
            // Centered on the box edge, so it reaches 1 pt outside, as in Raycast.
            Self.recordingBorder.setStroke(); path.lineWidth = 2; path.stroke()
        } else if isHovering {
            let inner = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), xRadius: 4.5, yRadius: 4.5)
            Self.hoverBorder.setStroke(); inner.lineWidth = 1; inner.stroke()
        }
        let color = isRecording || shortcut == nil ? Self.placeholderColor : Self.valueColor
        let text = NSAttributedString(string: title, attributes: [.font: Self.font, .foregroundColor: color])
        let size = text.size()
        text.draw(at: NSPoint(x: box.minX + Self.textInset, y: box.midY - size.height / 2))
        if let clearRect, let mark = NSImage(systemSymbolName: "xmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .medium).applying(.init(paletteColors: [Self.clearColor]))) {
            mark.draw(in: NSRect(x: clearRect.maxX - Self.textInset - mark.size.width, y: clearRect.midY - mark.size.height / 2,
                                 width: mark.size.width, height: mark.size.height))
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovering = true }
    override func mouseExited(with event: NSEvent) { isHovering = false }

    override func mouseDown(with event: NSEvent) {
        if let clearRect, clearRect.contains(convert(event.locationInWindow, from: nil)) {
            onRecord?(nil)
            return
        }
        super.mouseDown(with: event)
    }

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
            value = shortcut?.displayString ?? placeholder
        }
        title = value
        needsDisplay = true
        setAccessibilityLabel("\(commandTitle) shortcut")
        setAccessibilityValue(isRecording ? "Recording" : (shortcut == nil ? "None" : value))
    }
}
