import CoreGraphics

/// A change in a global shortcut, from the hotkey center or the event tap.
enum TriggerEvent: Equatable, Sendable {
    case pressed(CommandID)
    case released(CommandID)
    /// A held modifier-only chord turned into some other shortcut, such as ⌃⇧T for another app.
    case interrupted(CommandID)
    /// A held mouse button shortcut moved, in Core Graphics global coordinates (top-left origin).
    case dragged(CommandID, CGPoint)
}
