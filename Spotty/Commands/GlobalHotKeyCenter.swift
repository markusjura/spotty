import Carbon.HIToolbox
import Foundation
import Observation

/// Registers the registry's global key bindings with `RegisterEventHotKey` and reports presses
/// and releases. No Accessibility or Input Monitoring permission is involved. Registrations
/// follow registry changes automatically and are suspended while a shortcut recorder is active.
/// Keep one instance for the app's lifetime; `stop()` releases every registration.
@MainActor
final class GlobalHotKeyCenter {
    private nonisolated static let signature: OSType = 0x5350_5459 // "SPTY"

    private let registry: CommandRegistry
    private let handler: @MainActor (TriggerEvent) -> Void
    private var eventHandler: EventHandlerRef?
    private var registered: [UInt32: (slot: ShortcutSlot, reference: EventHotKeyRef)] = [:]
    /// Carbon repeats presses while a key is held; only the first one counts.
    private var held: Set<UInt32> = []
    private var layoutObserver: NSObjectProtocol?

    init(registry: CommandRegistry, handler: @escaping @MainActor (TriggerEvent) -> Void) {
        self.registry = registry
        self.handler = handler
    }

    isolated deinit { stop() }

    var isRunning: Bool { eventHandler != nil }

    func start() {
        guard eventHandler == nil else { return }
        let eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            guard hotKeyID.signature == GlobalHotKeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let identifier = hotKeyID.id
            let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            // The application event target dispatches on the main thread.
            MainActor.assumeIsolated {
                Unmanaged<GlobalHotKeyCenter>.fromOpaque(userData).takeUnretainedValue().fire(identifier, isPress: isPress)
            }
            return noErr
        }, eventTypes.count, eventTypes, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard status == noErr else {
            eventHandler = nil
            registry.reportRegistration(failures: Set(registry.activeGlobalBindings.filter { !$0.value.needsEventTap }.keys))
            return
        }
        layoutObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registry.keyboardLayoutDidChange() }
        }
        synchronize()
    }

    func stop() {
        unregisterAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
        layoutObserver = nil
    }

    private func fire(_ identifier: UInt32, isPress: Bool) {
        guard let slot = registered[identifier]?.slot else { return }
        if isPress {
            guard held.insert(identifier).inserted else { return }
            handler(.pressed(slot))
        } else {
            guard held.remove(identifier) != nil else { return }
            handler(.released(slot))
        }
    }

    /// Re-registers everything; the set is small and changes only from Settings.
    private func synchronize() {
        guard isRunning else { return }
        let bindings = withObservationTracking {
            registry.activeGlobalBindings
        } onChange: { [weak self] in
            Task { @MainActor in self?.synchronize() }
        }
        // A key held across re-registration would never report its release; end it now.
        for identifier in held { if let slot = registered[identifier]?.slot { handler(.released(slot)) } }
        held.removeAll()
        unregisterAll()
        var failures: Set<ShortcutSlot> = []
        for (index, slot) in CommandID.allCases.flatMap(\.slots).enumerated() {
            guard let shortcut = bindings[slot], let keyCode = shortcut.keyCode else { continue }
            let identifier = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(UInt32(keyCode), shortcut.carbonModifiers,
                                             EventHotKeyID(signature: Self.signature, id: identifier),
                                             GetApplicationEventTarget(), 0, &reference)
            if status == noErr, let reference {
                registered[identifier] = (slot, reference)
            } else {
                failures.insert(slot)
            }
        }
        // Suspension during recording is not a failure; keep the last real result.
        if registry.recordingCommand == nil { registry.reportRegistration(failures: failures) }
    }

    private func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.reference) }
        registered.removeAll()
    }
}
