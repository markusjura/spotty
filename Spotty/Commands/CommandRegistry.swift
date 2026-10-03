import AppKit
import Carbon.HIToolbox
import Observation

/// How a command's shortcut behaves.
enum CommandScope: Sendable {
    /// Global. Tap to toggle drawing, hold to draw until release. Any shortcut kind.
    case drawing
    /// Global. Fires on press. Keys and mouse buttons only.
    case action
    /// Plain keys handled by the overlay while drawing is toggled on.
    case overlay
}

enum CommandGroup: CaseIterable, Sendable {
    case drawing, actions, whileDrawing

    var title: String {
        switch self {
        case .drawing: "Start Drawing"
        case .actions: "Actions"
        case .whileDrawing: "While Drawing"
        }
    }

    var commands: [CommandID] { CommandID.allCases.filter { $0.group == self } }
}

/// Stable IDs; custom bindings persist by raw value.
enum CommandID: String, CaseIterable, Codable, Sendable {
    case draw, drawPen, drawHighlighter, drawArrow, drawRectangle, drawSpotlight
    case toggleDrawing, undo, clear
    case pickPen, pickHighlighter, pickArrow, pickRectangle, pickSpotlight

    var title: String {
        switch self {
        case .draw: "Draw"
        case .toggleDrawing: "Toggle Drawing"
        case .undo: "Undo Last Drawing"
        case .clear: "Clear Drawings"
        default: tool!.title
        }
    }

    var group: CommandGroup {
        switch self {
        case .draw, .drawPen, .drawHighlighter, .drawArrow, .drawRectangle, .drawSpotlight: .drawing
        case .toggleDrawing, .undo, .clear: .actions
        case .pickPen, .pickHighlighter, .pickArrow, .pickRectangle, .pickSpotlight: .whileDrawing
        }
    }

    var scope: CommandScope {
        switch group {
        case .drawing: .drawing
        case .actions: .action
        case .whileDrawing: .overlay
        }
    }

    var isGlobal: Bool { scope != .overlay }

    /// Nil for `draw`, which starts with the configured start tool, and for actions.
    var tool: DrawingTool? {
        switch self {
        case .drawPen, .pickPen: .pen
        case .drawHighlighter, .pickHighlighter: .highlighter
        case .drawArrow, .pickArrow: .arrow
        case .drawRectangle, .pickRectangle: .rectangle
        case .drawSpotlight, .pickSpotlight: .spotlight
        case .draw, .toggleDrawing, .undo, .clear: nil
        }
    }

    /// Global commands take a second shortcut, so a mouse button and a key chord can both trigger them.
    var slots: [ShortcutSlot] { (0..<(isGlobal ? 2 : 1)).map { ShortcutSlot(self, $0) } }

    static func draw(_ tool: DrawingTool) -> CommandID { allCases.first { $0.scope == .drawing && $0.tool == tool }! }
    static func pick(_ tool: DrawingTool) -> CommandID { allCases.first { $0.scope == .overlay && $0.tool == tool }! }

    /// Fresh-install bindings: hold ⌃⇧ to draw, add a letter to choose the tool. The same letters
    /// pick tools while drawing is toggled on.
    var defaultShortcut: Shortcut? {
        switch self {
        case .draw: return .modifiers([.control, .shift])
        case .toggleDrawing: return Shortcut(kVK_ANSI_D, [.control, .shift])
        case .undo: return Shortcut(kVK_ANSI_Z, [.control, .shift])
        case .clear: return Shortcut(kVK_Delete, [.control, .shift])
        default:
            let letter = Self.letters[tool!]!
            return scope == .overlay ? Shortcut(letter) : Shortcut(letter, [.control, .shift])
        }
    }

    private static let letters: [DrawingTool: Int] = [
        .pen: kVK_ANSI_P, .highlighter: kVK_ANSI_H, .arrow: kVK_ANSI_A,
        .rectangle: kVK_ANSI_R, .spotlight: kVK_ANSI_S,
    ]
}

/// One of a command's shortcuts. Only the first slot has a default.
struct ShortcutSlot: Hashable, Sendable {
    let command: CommandID
    let index: Int

    init(_ command: CommandID, _ index: Int = 0) {
        self.command = command
        self.index = index
    }

    var defaultShortcut: Shortcut? { index == 0 ? command.defaultShortcut : nil }

    /// `draw` for the first slot and `draw.1` for the second, so first-slot overrides keep their old keys.
    var storageKey: String { index == 0 ? command.rawValue : "\(command.rawValue).\(index)" }

    init?(storageKey key: String) {
        // Builds 3 and 4 stored Draw's second shortcut as a separate command.
        if key == "drawAlternate" { self.init(.draw, 1); return }
        let parts = key.split(separator: ".", maxSplits: 1)
        guard let name = parts.first, let command = CommandID(rawValue: String(name)) else { return nil }
        let index = parts.count == 2 ? Int(parts[1]) : 0
        guard let index, command.slots.indices.contains(index) else { return nil }
        self.init(command, index)
    }
}

enum ShortcutProblem: Error, Equatable, Sendable {
    case unsupported
    case conflict(CommandID)
    case needsCommandOrControl
    case reserved
    case modifiersOnlyForDrawing
    case keysOnly
    case reservedForDrawing

    var message: String {
        switch self {
        case .unsupported: "Use two or more modifiers alone, a key, or a middle or side mouse button."
        case .conflict(let other): "Already used by \(other.title)."
        case .needsCommandOrControl: "Add ⌘ or ⌃, or use a function key."
        case .reserved: "macOS or standard app commands use this shortcut."
        case .modifiersOnlyForDrawing: "Modifier-only shortcuts can only start drawing."
        case .keysOnly: "Use a key here."
        case .reservedForDrawing: "Escape, Delete, ⌘Z, and ⌘⌫ are used while drawing."
        }
    }
}

/// The single source for command names, scopes, and bindings. Menus, Settings, the global
/// hotkey center, the event tap, and the overlay's key handling all read from here.
@MainActor @Observable
final class CommandRegistry {
    static let storageKey = "commands.v1.shortcuts"

    @ObservationIgnored private let defaults: UserDefaults
    private(set) var bindings: [ShortcutSlot: Shortcut]
    /// Global shortcuts whose last registration failed, typically because another app owns the key.
    private(set) var registrationFailures: Set<ShortcutSlot> = []
    /// While set, global shortcuts are suspended so the recorder receives every combination.
    var recordingCommand: CommandID?
    private(set) var keyboardLayoutVersion = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = Self.load(from: defaults)
    }

    func shortcut(for slot: ShortcutSlot) -> Shortcut? {
        _ = keyboardLayoutVersion
        return bindings[slot]
    }

    /// The shortcut to show for a command in menus and help: the first key shortcut, else the first one.
    func shortcut(for id: CommandID) -> Shortcut? {
        let shortcuts = id.slots.compactMap(shortcut(for:))
        return shortcuts.first { $0.keyCode != nil } ?? shortcuts.first
    }

    /// Valid global bindings, suspended while recording.
    var activeGlobalBindings: [ShortcutSlot: Shortcut] {
        _ = keyboardLayoutVersion
        guard recordingCommand == nil else { return [:] }
        return bindings.filter { $0.key.command.isGlobal && Self.ruleProblem($0.value, scope: $0.key.command.scope) == nil }
    }

    /// Whether any binding needs the Accessibility event tap.
    var needsEventTap: Bool { bindings.contains { $0.key.command.isGlobal && $0.value.needsEventTap } }

    /// Nil when `shortcut` may be assigned to `slot`.
    func problem(assigning shortcut: Shortcut, to slot: ShortcutSlot) -> ShortcutProblem? {
        if let rule = Self.ruleProblem(shortcut, scope: slot.command.scope) { return rule }
        if let other = bindings.first(where: { $0.key != slot && $0.value == shortcut })?.key { return .conflict(other.command) }
        return nil
    }

    /// Applies the binding, or leaves everything unchanged and returns why not. Nil clears.
    @discardableResult
    func assign(_ shortcut: Shortcut?, to slot: ShortcutSlot) -> ShortcutProblem? {
        guard let shortcut else {
            guard bindings[slot] != nil else { return nil }
            bindings[slot] = nil
            save()
            return nil
        }
        if let problem = problem(assigning: shortcut, to: slot) { return problem }
        guard bindings[slot] != shortcut else { return nil }
        bindings[slot] = shortcut
        save()
        return nil
    }

    /// Clears the group first so bindings swapped within it restore cleanly.
    @discardableResult
    func restoreDefaults(in group: CommandGroup) -> [ShortcutSlot: ShortcutProblem] {
        let slots = group.commands.flatMap(\.slots)
        for slot in slots { bindings[slot] = nil }
        var problems: [ShortcutSlot: ShortcutProblem] = [:]
        for slot in slots {
            guard let shortcut = slot.defaultShortcut else { continue }
            if let problem = problem(assigning: shortcut, to: slot) { problems[slot] = problem } else { bindings[slot] = shortcut }
        }
        save()
        return problems
    }

    /// The overlay command for a key pressed while drawing is toggled on.
    func overlayCommand(matching shortcut: Shortcut) -> CommandID? {
        bindings.first { $0.key.command.scope == .overlay && $0.value == shortcut }?.key.command
    }

    func keyboardLayoutDidChange() { keyboardLayoutVersion &+= 1 }

    func reportRegistration(failures: Set<ShortcutSlot>) {
        if registrationFailures != failures { registrationFailures = failures }
    }

    // MARK: - Rules and persistence

    /// Positional key codes of standard app commands and macOS system shortcuts.
    private static let reserved: Set<Shortcut> = [
        Shortcut(kVK_ANSI_Q, .command), Shortcut(kVK_ANSI_W, .command), Shortcut(kVK_ANSI_H, .command),
        Shortcut(kVK_ANSI_H, [.option, .command]), Shortcut(kVK_ANSI_M, .command), Shortcut(kVK_ANSI_Comma, .command),
        Shortcut(kVK_ANSI_Z, .command), Shortcut(kVK_ANSI_Z, [.shift, .command]), Shortcut(kVK_ANSI_X, .command),
        Shortcut(kVK_ANSI_C, .command), Shortcut(kVK_ANSI_V, .command), Shortcut(kVK_ANSI_A, .command),
        Shortcut(kVK_Tab, .command), Shortcut(kVK_Tab, [.shift, .command]), Shortcut(kVK_ANSI_Grave, .command),
        Shortcut(kVK_Space, .command), Shortcut(kVK_Space, .control), Shortcut(kVK_Space, [.option, .command]),
        Shortcut(kVK_Escape, [.option, .command]), Shortcut(kVK_ANSI_Q, [.control, .command]),
        Shortcut(kVK_ANSI_F, [.control, .command]),
    ]

    /// Keys the overlay itself handles while drawing is toggled on.
    private static let overlayKeys: Set<Shortcut> = [
        Shortcut(kVK_Escape), Shortcut(kVK_Delete), Shortcut(kVK_ForwardDelete),
        Shortcut(kVK_ANSI_Z, .command), Shortcut(kVK_Delete, .command),
    ]

    static func ruleProblem(_ shortcut: Shortcut, scope: CommandScope) -> ShortcutProblem? {
        guard shortcut.isSupported else { return .unsupported }
        if reserved.contains(shortcut) || isReservedCharacter(shortcut) { return .reserved }
        switch scope {
        case .overlay:
            guard shortcut.keyCode != nil else { return .keysOnly }
            return overlayKeys.contains(shortcut) ? .reservedForDrawing : nil
        case .action where shortcut.isModifierOnly:
            return .modifiersOnlyForDrawing
        case .drawing, .action:
            // Global key shortcuts need ⌘ or ⌃ so they never swallow typing; function keys stand alone.
            guard shortcut.keyCode != nil else { return nil }
            return shortcut.hasCommandOrControl || shortcut.isFunctionKey ? nil : .needsCommandOrControl
        }
    }

    /// Standard application actions follow characters on the active layout, while bindings use
    /// physical key codes. For example, German ⌘Z lives at the ANSI Y position.
    private static func isReservedCharacter(_ shortcut: Shortcut) -> Bool {
        guard let code = shortcut.keyCode, let character = KeyNames.character(for: code) else { return false }
        let key = String(character).lowercased()
        switch shortcut.modifiers {
        case .command: return ["q", "w", "h", "m", ",", "z", "x", "c", "v", "a", "`"].contains(key)
        case [.shift, .command]: return key == "z"
        case [.option, .command]: return key == "h"
        case [.control, .command]: return key == "q" || key == "f"
        default: return false
        }
    }

    /// Stores only differences from defaults, so improved defaults reach users who never customized.
    private func save() {
        var overrides: [String: Shortcut?] = [:]
        for slot in Self.allSlots where bindings[slot] != slot.defaultShortcut {
            overrides[slot.storageKey] = .some(bindings[slot])
        }
        guard let data = try? JSONEncoder().encode(overrides) else { return assertionFailure("Unencodable shortcuts") }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Overrides win over defaults on duplicates; invalid entries fall back to the default when it
    /// still fits, otherwise to unassigned.
    private static func load(from defaults: UserDefaults) -> [ShortcutSlot: Shortcut] {
        let stored = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Shortcut?].self, from: $0) } ?? [:]
        let overrides = Dictionary(stored.compactMap { key, value in ShortcutSlot(storageKey: key).map { ($0, value) } },
                                   uniquingKeysWith: { first, _ in first })
        var result: [ShortcutSlot: Shortcut] = [:]
        let customized = allSlots.filter { overrides.keys.contains($0) }
        for slot in customized + allSlots.filter({ !overrides.keys.contains($0) }) {
            // An explicitly cleared slot stays unassigned.
            let candidates: [Shortcut] = if let override = overrides[slot] {
                override.map { [$0] + [slot.defaultShortcut].compactMap { $0 } } ?? []
            } else {
                [slot.defaultShortcut].compactMap { $0 }
            }
            if let shortcut = candidates.first(where: { ruleProblem($0, scope: slot.command.scope) == nil && !result.values.contains($0) }) {
                result[slot] = shortcut
            }
        }
        return result
    }

    private static let allSlots = CommandID.allCases.flatMap(\.slots)
}
