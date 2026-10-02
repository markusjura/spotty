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
        overlay.didDraw = { [weak self] in self?.update { $0.didDraw() } }
        overlay.handleKey = { [weak self] in self?.handleKey($0) ?? false }
    }

    var isDrawing: Bool { session.isActive }

    /// From the hotkey center and the event tap.
    func handle(_ event: TriggerEvent) {
        Self.log.debug("\(String(describing: event), privacy: .public)")
        switch event {
        case .pressed(let command):
            switch command.scope {
            case .drawing:
                let startTool = preferences.drawing.resolvedStartTool
                update { $0.pressed(command, at: ProcessInfo.processInfo.systemUptime, startTool: startTool) }
            case .action: perform(command)
            case .overlay: break
            }
        case .released(let command):
            // Finish a button-drawn mark first, so the release counts as a hold that drew.
            overlay.endPointerMark()
            update { $0.released(command, at: ProcessInfo.processInfo.systemUptime) }
        case .interrupted(let command):
            update { $0.interrupted(command) }
        case .dragged(let command, let location):
            guard session.heldCommand == command, isDrawing else { return }
            overlay.dragPointerMark(to: location)
        }
    }

    /// Undo and Clear, from shortcuts and menus.
    func perform(_ command: CommandID) {
        switch command {
        case .undo: overlay.undo()
        case .clear: overlay.clear()
        default: break
        }
    }

    /// Menu items: toggles drawing with `tool`, or with the start tool for nil.
    func toggle(_ tool: DrawingTool? = nil) {
        let tool = tool ?? (isDrawing ? session.tool : preferences.drawing.resolvedStartTool)
        update { $0.toggle(tool) }
    }

    func pick(_ tool: DrawingTool) { update { $0.pick(tool) } }

    func stop() { update { $0.stop() } }

    var hasDrawings: Bool { overlay.hasDrawings }

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
            overlay.deactivate(fadeAfter: preferences.drawing.fade.interval)
        default: break
        }
    }

    /// A held mouse button leaves the keyboard free, so the overlay takes keys as when drawing is
    /// toggled on and the plain tool letters switch tools. A held key chord leaves keys with the
    /// app you are working in.
    private var isHoldingMouseButton: Bool {
        session.heldCommand.flatMap(commands.shortcut(for:))?.mouseButton != nil
    }

    private static let log = Logger(subsystem: "local.markus.Spotty", category: "drawing")

    private var markStyle: MarkStyle {
        let drawing = preferences.drawing
        // Shift draws straight lines and squares, unless it is part of the held shortcut.
        let held = session.heldCommand.flatMap(commands.shortcut(for:))
        return MarkStyle(tool: session.tool, color: drawing.color, highlighterColor: drawing.highlighterColor,
                         width: drawing.lineWidth, dimming: drawing.spotlightDimming / 100,
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
