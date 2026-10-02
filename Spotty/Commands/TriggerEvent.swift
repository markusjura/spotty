import CoreGraphics

/// A change in a global shortcut, from the hotkey center or the event tap. The slot tells apart
/// two shortcuts of one command, such as a key chord and a mouse button for Draw.
enum TriggerEvent: Equatable, Sendable {
    case pressed(ShortcutSlot)
    case released(ShortcutSlot)
    /// A held modifier-only chord turned into some other shortcut, such as ⌃⇧T for another app.
    case interrupted(ShortcutSlot)
    /// A held mouse button shortcut moved, in Core Graphics global coordinates (top-left origin).
    case dragged(ShortcutSlot, CGPoint)
}
