import Foundation

/// Tap-or-hold activation, shared by every drawing shortcut.
///
/// - Hold a shortcut to draw until you let go.
/// - Tap it (press and release within `tapInterval`, without drawing) to toggle drawing on;
///   tap it again to turn drawing off.
/// - While one shortcut is held, pressing another switches tools: hold ⌃⇧, then press A for
///   the arrow. The first shortcut of a gesture decides when it ends.
/// - While toggled on, a tool shortcut for a different tool switches to it instead of ending.
///
/// A pure value: callers pass time in and apply the resulting mode and tool.
struct DrawingSession: Equatable, Sendable {
    enum Mode: Equatable, Sendable {
        case off
        /// Drawing while a shortcut is held.
        case holding
        /// Toggled on until tapped again or Escape.
        case latched
    }

    static let tapInterval: TimeInterval = 0.3

    private(set) var mode = Mode.off
    private(set) var tool: DrawingTool
    /// The shortcut that started the current gesture.
    private var press: Press?

    private struct Press: Equatable, Sendable {
        let slot: ShortcutSlot
        let start: TimeInterval
        var drew = false
        var switchedTool = false
    }

    init(tool: DrawingTool) {
        self.tool = tool
    }

    var isActive: Bool { mode != .off }

    /// The shortcut held for the current gesture, if any.
    var heldSlot: ShortcutSlot? { press?.slot }

    /// `startTool` is the tool for `.draw`, which names no tool itself.
    mutating func pressed(_ slot: ShortcutSlot, at time: TimeInterval, startTool: DrawingTool) {
        guard press?.slot != slot else { return }
        if press != nil {
            switchTool(to: slot.command.tool)
            return
        }
        press = Press(slot: slot, start: time)
        switch mode {
        case .off:
            mode = .holding
            tool = slot.command.tool ?? startTool
        case .latched:
            switchTool(to: slot.command.tool)
        case .holding:
            assertionFailure("Holding without a press")
        }
    }

    mutating func released(_ slot: ShortcutSlot, at time: TimeInterval) {
        guard let press, press.slot == slot else { return }
        self.press = nil
        let tapped = !press.drew && time - press.start < Self.tapInterval
        switch mode {
        case .holding: mode = tapped ? .latched : .off
        case .latched: if tapped && !press.switchedTool { mode = .off }
        case .off: break
        }
    }

    /// The held shortcut turned out to be part of another app's shortcut.
    mutating func interrupted(_ slot: ShortcutSlot) {
        guard press?.slot == slot else { return }
        press = nil
        if mode == .holding { mode = .off }
    }

    /// A finished mark makes the current press a hold, never a tap.
    mutating func didDraw() {
        press?.drew = true
    }

    /// Picks a tool from the toolbar or a key while drawing.
    mutating func pick(_ tool: DrawingTool) {
        self.tool = tool
    }

    /// Menu items toggle like a tap.
    mutating func toggle(_ tool: DrawingTool) {
        press = nil
        if mode == .off || self.tool != tool { mode = .latched; self.tool = tool } else { mode = .off }
    }

    mutating func stop() {
        press = nil
        mode = .off
    }

    private mutating func switchTool(to newTool: DrawingTool?) {
        guard let newTool, newTool != tool else { return }
        tool = newTool
        press?.switchedTool = true
    }
}
