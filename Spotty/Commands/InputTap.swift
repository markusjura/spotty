import AppKit
import ApplicationServices
import Observation

/// Watches modifier-only chords and middle or side mouse buttons through a session event tap.
/// It exists only while such a binding is assigned and Accessibility access is granted, and it
/// swallows only the mouse buttons it reports, so a bound side button never also means "Back".
/// Dragging with a bound button held is reported too, so the button can draw on its own.
/// Keyboard events always pass through unchanged.
@MainActor @Observable
final class InputTap {
    /// Whether Spotty is trusted for Accessibility. Refreshed when macOS reports a change.
    private(set) var isTrusted = AXIsProcessTrusted()

    @ObservationIgnored private let registry: CommandRegistry
    @ObservationIgnored private let handler: @MainActor (TriggerEvent) -> Void
    @ObservationIgnored private var tap: CFMachPort?
    @ObservationIgnored private var source: CFRunLoopSource?
    /// The bindings the tap watches: modifier-only chords and mouse buttons.
    @ObservationIgnored private var bindings: [ShortcutSlot: Shortcut] = [:]
    /// Every active global shortcut, so a key pressed with a chord held can tell Spotty's own
    /// shortcuts from other apps' without recomputing the registry's bindings per key.
    @ObservationIgnored private var globalShortcuts: Set<Shortcut> = []
    /// The modifier-only chord currently held exactly.
    @ObservationIgnored private var heldChord: ShortcutSlot?
    @ObservationIgnored private var lastModifiers: Shortcut.Modifiers = []
    /// Mouse buttons whose press was reported and swallowed, so their release is too.
    @ObservationIgnored private var heldButtons: [Int: ShortcutSlot] = [:]
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
    /// Also retries a tap that failed to install while trust was still settling.
    func refreshTrust() {
        let trusted = AXIsProcessTrusted()
        if trusted != isTrusted { isTrusted = trusted }
        if trusted, tap == nil, !bindings.isEmpty { installTap() }
    }

    /// Shows macOS's Accessibility prompt, which links to System Settings.
    func requestAccess() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(options)
    }

    private func synchronize() {
        let (active, trusted) = withObservationTracking {
            (registry.activeGlobalBindings, isTrusted)
        } onChange: { [weak self] in
            Task { @MainActor in self?.synchronize() }
        }
        endHeld()
        bindings = active.filter { $0.value.needsEventTap }
        globalShortcuts = Set(active.values)
        if bindings.isEmpty || !trusted { removeTap() } else { installTap() }
    }

    /// Watches keys only for modifier-only chords, and buttons only for mouse shortcuts.
    private func installTap() {
        removeTap()
        let chords = bindings.values.contains(where: \.isModifierOnly), mouse = bindings.values.contains { $0.mouseButton != nil }
        var mask: CGEventMask = 0
        if chords { mask |= CGEventMask(1 << CGEventType.flagsChanged.rawValue) | CGEventMask(1 << CGEventType.keyDown.rawValue) }
        if mouse {
            mask |= CGEventMask(1 << CGEventType.otherMouseDown.rawValue) | CGEventMask(1 << CGEventType.otherMouseUp.rawValue)
                | CGEventMask(1 << CGEventType.otherMouseDragged.rawValue)
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: { _, type, event, userData in
            guard let userData else { return Unmanaged.passUnretained(event) }
            // The tap's run loop source is on the main run loop.
            let swallow = MainActor.assumeIsolated {
                Unmanaged<InputTap>.fromOpaque(userData).takeUnretainedValue().handle(type, event)
            }
            return swallow ? nil : Unmanaged.passUnretained(event)
        }, userInfo: Unmanaged.passUnretained(self).toOpaque()) else {
            // Trust can lag behind the grant; the next trust refresh retries.
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
        for slot in heldButtons.values { handler(.released(slot)) }
        heldChord = nil
        heldButtons.removeAll()
    }

    /// Returns true to swallow the event.
    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // Releases may have passed unseen while disabled, so end held gestures and start over.
            endHeld()
            lastModifiers = Shortcut.Modifiers(flags: CGEventSource.flagsState(.combinedSessionState))
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
                if !globalShortcuts.contains(pressed) {
                    self.heldChord = nil
                    handler(.interrupted(heldChord))
                }
            }
            return false
        case .otherMouseDown:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            let pressed = Shortcut.mouse(button, Shortcut.Modifiers(flags: event.flags))
            guard let slot = bindings.first(where: { $0.value == pressed })?.key else { return false }
            heldButtons[button] = slot
            handler(.pressed(slot))
            return true
        case .otherMouseDragged:
            // Moving with a bound button held draws, so the button works on its own, without a left drag.
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard let slot = heldButtons[button] else { return false }
            handler(.dragged(slot, event.location))
            return true
        case .otherMouseUp:
            let button = Int(event.getIntegerValueField(.mouseEventButtonNumber))
            guard let slot = heldButtons.removeValue(forKey: button) else { return false }
            handler(.released(slot))
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
              let slot = bindings.first(where: { $0.value == .modifiers(modifiers) })?.key else { return }
        heldChord = slot
        handler(.pressed(slot))
    }
}
