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
    case draw, drawAlternate, drawPen, drawHighlighter, drawArrow, drawRectangle, drawEllipse, drawSpotlight
    case undo, clear
    case pickPen, pickHighlighter, pickArrow, pickRectangle, pickEllipse, pickSpotlight

    var title: String {
        switch self {
        case .draw: "Draw"
        case .drawAlternate: "Draw (Alternate)"
        case .undo: "Undo Last Drawing"
        case .clear: "Clear Drawings"
        default: tool!.title
        }
    }

    var group: CommandGroup {
        switch self {
        case .draw, .drawAlternate, .drawPen, .drawHighlighter, .drawArrow, .drawRectangle, .drawEllipse, .drawSpotlight: .drawing
        case .undo, .clear: .actions
        case .pickPen, .pickHighlighter, .pickArrow, .pickRectangle, .pickEllipse, .pickSpotlight: .whileDrawing
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

    /// Nil for `draw` and `drawAlternate`, which start with the configured start tool, and for actions.
    var tool: DrawingTool? {
        switch self {
        case .drawPen, .pickPen: .pen
        case .drawHighlighter, .pickHighlighter: .highlighter
        case .drawArrow, .pickArrow: .arrow
        case .drawRectangle, .pickRectangle: .rectangle
        case .drawEllipse, .pickEllipse: .ellipse
        case .drawSpotlight, .pickSpotlight: .spotlight
        case .draw, .drawAlternate, .undo, .clear: nil
        }
    }

    static func draw(_ tool: DrawingTool) -> CommandID { allCases.first { $0.scope == .drawing && $0.tool == tool }! }
    static func pick(_ tool: DrawingTool) -> CommandID { allCases.first { $0.scope == .overlay && $0.tool == tool }! }

    /// Fresh-install bindings: hold ⌃⇧ to draw, add a letter to choose the tool. The same letters
    /// pick tools while drawing is toggled on. The alternate Draw shortcut, typically a mouse
    /// button, starts unassigned.
    var defaultShortcut: Shortcut? {
        switch self {
        case .draw: return .modifiers([.control, .shift])
        case .drawAlternate: return nil
        case .undo: return Shortcut(kVK_ANSI_Z, [.control, .shift])
        case .clear: return Shortcut(kVK_Delete, [.control, .shift])
        default:
            let letter = Self.letters[tool!]!
            return scope == .overlay ? Shortcut(letter) : Shortcut(letter, [.control, .shift])
        }
    }

    private static let letters: [DrawingTool: Int] = [
        .pen: kVK_ANSI_P, .highlighter: kVK_ANSI_H, .arrow: kVK_ANSI_A,
        .rectangle: kVK_ANSI_R, .ellipse: kVK_ANSI_O, .spotlight: kVK_ANSI_S,
    ]
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
    private(set) var bindings: [CommandID: Shortcut]
    /// Global commands whose last registration failed, typically because another app owns the key.
    private(set) var registrationFailures: Set<CommandID> = []
    /// While set, global shortcuts are suspended so the recorder receives every combination.
    var recordingCommand: CommandID?
    private(set) var keyboardLayoutVersion = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        bindings = Self.load(from: defaults)
    }

    func shortcut(for id: CommandID) -> Shortcut? {
        _ = keyboardLayoutVersion
        return bindings[id]
    }

    /// Valid global bindings, suspended while recording.
    var activeGlobalBindings: [CommandID: Shortcut] {
        _ = keyboardLayoutVersion
        guard recordingCommand == nil else { return [:] }
        return bindings.filter { $0.key.isGlobal && Self.ruleProblem($0.value, scope: $0.key.scope) == nil }
    }

    /// Whether any binding needs the Accessibility event tap.
    var needsEventTap: Bool { bindings.contains { $0.key.isGlobal && $0.value.needsEventTap } }

    /// Nil when `shortcut` may be assigned to `id`.
    func problem(assigning shortcut: Shortcut, to id: CommandID) -> ShortcutProblem? {
        if let rule = Self.ruleProblem(shortcut, scope: id.scope) { return rule }
        if let other = bindings.first(where: { $0.key != id && $0.value == shortcut })?.key { return .conflict(other) }
        return nil
    }

    /// Applies the binding, or leaves everything unchanged and returns why not. Nil clears.
    @discardableResult
    func assign(_ shortcut: Shortcut?, to id: CommandID) -> ShortcutProblem? {
        guard let shortcut else {
            guard bindings[id] != nil else { return nil }
            bindings[id] = nil
            save()
            return nil
        }
        if let problem = problem(assigning: shortcut, to: id) { return problem }
        guard bindings[id] != shortcut else { return nil }
        bindings[id] = shortcut
        save()
        return nil
    }

    /// Clears the group first so bindings swapped within it restore cleanly.
    @discardableResult
    func restoreDefaults(in group: CommandGroup) -> [CommandID: ShortcutProblem] {
        for id in group.commands { bindings[id] = nil }
        var problems: [CommandID: ShortcutProblem] = [:]
        for id in group.commands {
            guard let shortcut = id.defaultShortcut else { continue }
            if let problem = problem(assigning: shortcut, to: id) { problems[id] = problem } else { bindings[id] = shortcut }
        }
        save()
        return problems
    }

    /// The overlay command for a key pressed while drawing is toggled on.
    func overlayCommand(matching shortcut: Shortcut) -> CommandID? {
        bindings.first { $0.key.scope == .overlay && $0.value == shortcut }?.key
    }

    func keyboardLayoutDidChange() { keyboardLayoutVersion &+= 1 }

    func reportRegistration(failures: Set<CommandID>) {
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
        for id in CommandID.allCases where bindings[id] != id.defaultShortcut {
            overrides[id.rawValue] = .some(bindings[id])
        }
        guard let data = try? JSONEncoder().encode(overrides) else { return assertionFailure("Unencodable shortcuts") }
        defaults.set(data, forKey: Self.storageKey)
    }

    /// Overrides win over defaults on duplicates; invalid entries fall back to the default when it
    /// still fits, otherwise to unassigned.
    private static func load(from defaults: UserDefaults) -> [CommandID: Shortcut] {
        let stored = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode([String: Shortcut?].self, from: $0) } ?? [:]
        let overrides = Dictionary(uniqueKeysWithValues: stored.compactMap { key, value in CommandID(rawValue: key).map { ($0, value) } })
        var result: [CommandID: Shortcut] = [:]
        let customized = CommandID.allCases.filter { overrides.keys.contains($0) }
        for id in customized + CommandID.allCases.filter({ !overrides.keys.contains($0) }) {
            // An explicitly cleared command stays unassigned.
            let candidates: [Shortcut] = if let override = overrides[id] {
                override.map { [$0] + [id.defaultShortcut].compactMap { $0 } } ?? []
            } else {
                [id.defaultShortcut].compactMap { $0 }
            }
            if let shortcut = candidates.first(where: { ruleProblem($0, scope: id.scope) == nil && !result.values.contains($0) }) {
                result[id] = shortcut
            }
        }
        return result
    }
}
