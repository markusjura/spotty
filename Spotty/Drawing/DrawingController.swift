import AppKit
import Carbon.HIToolbox
import Observation
import OSLog

/// Turns shortcut presses into drawing: owns the session, the overlay, and the toolbar.
@MainActor @Observable
final class DrawingController {
    private(set) var session: DrawingSession

    @ObservationIgnored let preferences: AppPreferences
    @ObservationIgnored let commands: CommandRegistry
    @ObservationIgnored private let overlay = Overlay()
    @ObservationIgnored private lazy var toolbar = ToolbarPanel(controller: self)

    init(preferences: AppPreferences, commands: CommandRegistry) {
        self.preferences = preferences
        self.commands = commands
        session = DrawingSession(tool: preferences.drawing.resolvedStartTool)
        overlay.style = { [weak self] in self?.markStyle }
        overlay.fadeAfter = { [weak self] in self?.preferences.drawing.fadeAfter }
        overlay.didDraw = { [weak self] in self?.update { $0.didDraw() } }
        overlay.handleKey = { [weak self] in self?.handleKey($0) ?? false }
    }

    var isDrawing: Bool { session.isActive }

    /// From the hotkey center and the event tap.
    func handle(_ event: TriggerEvent) {
        Self.log.debug("\(String(describing: event), privacy: .public)")
        switch event {
        case .pressed(let slot):
            switch slot.command.scope {
            case .drawing:
                let startTool = preferences.drawing.resolvedStartTool
                update { $0.pressed(slot, at: ProcessInfo.processInfo.systemUptime, startTool: startTool) }
            case .action: perform(slot.command)
            case .overlay: break
            }
        case .released(let slot):
            if slot == session.heldSlot {
                // A mark drawn during the press makes the release a hold: finish a button-drawn
                // mark, and count a left drag that is still going.
                overlay.endPointerMark()
                if overlay.isDrawingMark { update { $0.didDraw() } }
            }
            update { $0.released(slot, at: ProcessInfo.processInfo.systemUptime) }
        case .interrupted(let slot):
            update { $0.interrupted(slot) }
        case .dragged(let slot, let location):
            guard session.heldSlot == slot, isDrawing else { return }
            overlay.dragPointerMark(to: location)
        }
    }

    /// Toggle Drawing, Undo, and Clear, from shortcuts and menus.
    func perform(_ command: CommandID) {
        switch command {
        case .toggleDrawing:
            let startTool = preferences.drawing.resolvedStartTool
            update { $0.toggleDrawing(startTool: startTool) }
        case .undo: overlay.undo()
        case .clear: overlay.clear()
        default: break
        }
    }

    /// Tool menu items: toggles drawing with `tool`.
    func toggle(_ tool: DrawingTool) { update { $0.toggle(tool) } }

    func pick(_ tool: DrawingTool) { update { $0.pick(tool) } }

    func stop() { update { $0.stop() } }

    /// Applies a session change to the overlay and toolbar.
    private func update(_ change: (inout DrawingSession) -> Void) {
        let old = session
        change(&session)
        guard session != old else { return }
        Self.log.debug("\(String(describing: old.mode), privacy: .public) -> \(String(describing: self.session.mode), privacy: .public), \(self.session.tool.rawValue, privacy: .public)")
        if session.isActive && session.tool != preferences.drawing.lastTool { preferences.drawing.lastTool = session.tool }
        switch (old.mode, session.mode) {
        case (.off, .holding): overlay.activate(keyboard: isHoldingMouseButton)
        case (.off, .latched): overlay.activate(keyboard: true); toolbar.show()
        case (.holding, .latched): overlay.setKeyboard(true); toolbar.show()
        case (_, .off) where old.mode != .off:
            toolbar.hide()
            overlay.deactivate()
        default: break
        }
    }

    /// A held mouse button leaves the keyboard free, so the overlay takes keys as when drawing is
    /// toggled on and the plain tool letters switch tools. A held key chord leaves keys with the
    /// app you are working in.
    private var isHoldingMouseButton: Bool {
        session.heldSlot.flatMap(commands.shortcut(for:))?.mouseButton != nil
    }

    private static let log = Logger(subsystem: "local.markus.Spotty", category: "drawing")

    private var markStyle: MarkStyle {
        let drawing = preferences.drawing
        // Shift draws straight lines and squares, unless it is part of the held shortcut.
        let held = session.heldSlot.flatMap(commands.shortcut(for:))
        return MarkStyle(tool: session.tool, style: drawing.style(for: session.tool), dimming: drawing.spotlightDimming / 100,
                         shiftConstrains: !(held?.modifiers.contains(.shift) ?? false))
    }

    /// Keys while drawing is toggled on or a mouse button is held: tool letters, Escape, and undo.
    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = Shortcut.Modifiers(flags: event.modifierFlags)
        switch (Int(event.keyCode), modifiers) {
        case (kVK_Escape, []): stop()
        case (kVK_ANSI_Z, .command), (kVK_Delete, []), (kVK_ForwardDelete, []): overlay.undo()
        case (kVK_Delete, .command): overlay.clear()
        default:
            guard let shortcut = Shortcut(keyEvent: event), let tool = commands.overlayCommand(matching: shortcut)?.tool else { return false }
            pick(tool)
        }
        return true
    }
}
