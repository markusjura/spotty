import AppKit
import ApplicationServices
import Observation

/// Watches modifier-only chords and middle or side mouse buttons through a session event tap.
/// It exists only while such a binding is assigned and Accessibility access is granted, and it
/// swallows only the mouse buttons it reports, so a bound side button never also means "Back".
/// Keyboard events always pass through unchanged.
@MainActor @Observable
final class InputTap {
    /// Whether Spotty is trusted for Accessibility. Refreshed when macOS reports a change.
    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private let registry: CommandRegistry
    @ObservationIgnored private let handler: @MainActor (TriggerEvent) -> Void
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    @ObservationIgnored private var bindings: [CommandID: Shortcut] = [:]
    /// The modifier-only chord currently held exactly.
    @ObservationIgnored private var heldChord: CommandID?
    @ObservationIgnored private var lastModifiers: Shortcut.Modifiers = []
    /// Mouse buttons whose press was reported and swallowed, so their release is too.
    @ObservationIgnored private var heldButtons: [Int: CommandID] = [:]
    @ObservationIgnored private var trustObserver: NSObjectProtocol?

    init(registry: CommandRegistry, handler: @escaping @MainActor (TriggerEvent) -> Void) {
        self.registry = registry
        self.handler = handler
    }

    func start() {
        trustObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            // The notification arrives before the new trust value is readable.
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                self?.refreshTrust()
            }
        }
        synchronize()
    }

    /// Re-reads trust, for example when Settings becomes active after a System Settings visit.
    func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
    }

    /// Shows macOS's Accessibility prompt, which links to System Settings.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    private func synchronize() {
        let (wanted, trusted) = withObservationTracking {
            (registry.activeGlobalBindings.filter { $0.value.needsEventTap }, isTrusted)
        } onChange: { [weak self] in
            Task { @MainActor in self?.synchronize() }
        }
        endHeld()
        bindings = wanted
        if wanted.isEmpty || !trusted {
            removeTap()
        } else {
            installTap(chords: wanted.values.contains(where: \.isModifierOnly), mouse: wanted.values.contains { $0.mouseButton != nil })
        }
    }

    /// Watches keys only for modifier-only chords, and buttons only for mouse shortcuts.
    private func installTap(chords: Bool, mouse: Bool) {
        removeTap()
        var mask: CGEventMask = 0
        if chords { mask |= CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue) }
        if mouse { mask |= CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue) }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            // The tap's run loop source is on the main run loop.
            let swallow = MainActor.assumeIsolated {
                Unmanaged<InputTap>.fromOpaque(userData).takeUnretainedValue().handle(type, event)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // Trust can lag behind the grant; the next trust notification retries.
            return
        }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.tap = tap
        self.source = source
    }

    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
    }

    /// Ends anything held when bindings change mid-press.
    private func endHeld() {
        if let heldChord { handler(.released(heldChord)) }
        for command in heldButtons.values { handler(.released(command)) }
        heldChord = nil
        heldButtons.removeAll()
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged:
            chordChanged(Shortcut.Modifiers(flags: event.flags))
            return false
        case .keyDown:
            // A key with the chord held is either one of Spotty's own shortcuts, such as ⌃⇧A, or
            // a shortcut for another app, which ends the chord without toggling drawing.
            if let heldChord, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let pressed = Shortcut(input: .key(UInt16(event.getIntegerValueField(.keyboardEventKeycode))),
                                       modifiers: Shortcut.Modifiers(flags: event.flags))
                if !registry.activeGlobalBindings.values.contains(pressed) {
                    self.heldChord = nil
                    handler(.interrupted(heldChord))
                }
            }
            return false
        case .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let pressed = Shortcut.mouse(button, Shortcut.Modifiers(flags: event.flags))
            guard let command = bindings.first(where: { $0.value == pressed })?.key else { return false }
            heldButtons[button] = command
            handler(.pressed(command))
            return true
        case .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard let command = heldButtons.removeValue(forKey: button) else { return false }
            handler(.released(command))
            return true
        default:
            return false
        }
    }

    /// A chord is held while the modifiers match it exactly. It starts only when pressing
    /// modifiers reaches it, not when letting go of ⌘ after ⌃⇧⌘4 leaves ⌃⇧ down. Adding a
    /// modifier interrupts it; letting go of one releases it.
    private func chordChanged(_ modifiers: Shortcut.Modifiers) {
        let previous = lastModifiers
        lastModifiers = modifiers
        if let heldChord, let chord = bindings[heldChord]?.modifiers, modifiers != chord {
            self.heldChord = nil
            handler(modifiers.isSuperset(of: chord) ? .interrupted(heldChord) : .released(heldChord))
            return
        }
        guard heldChord == nil, previous.isStrictSubset(of: modifiers),
              let command = bindings.first(where: { $0.value == .modifiers(modifiers) })?.key else { return }
        heldChord = command
        handler(.pressed(command))
    }
}
