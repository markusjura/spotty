import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A trigger: modifiers plus a key, a mouse button, or nothing (the modifiers alone, held).
/// Key codes are layout-independent; display strings use the current ASCII-capable layout, as
/// macOS menus do.
struct Shortcut: Codable, Hashable, Sendable {
    struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        let rawValue: UInt8
        static let control = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let shift = Modifiers(rawValue: 1 << 2)
        static let command = Modifiers(rawValue: 1 << 3)

        var count: Int { rawValue.nonzeroBitCount }
    }

    /// What is pressed together with the modifiers.
    enum Input: Codable, Hashable, Sendable {
        case key(UInt16)
        /// An `NSEvent.buttonNumber` of 2 or more: middle and side buttons. Left and right clicks draw and stay free.
        case mouseButton(Int)
    }

    /// Nil for a modifier-only chord such as ⌃⇧.
    let input: Input?
    let modifiers: Modifiers

    init(input: Input?, modifiers: Modifiers) {
        self.input = input
        self.modifiers = modifiers
    }

    /// A key with modifiers, from a Carbon `kVK_*` constant.
    init(_ key: Int, _ modifiers: Modifiers = []) {
        self.init(input: .key(UInt16(key)), modifiers: modifiers)
    }

    static func modifiers(_ modifiers: Modifiers) -> Shortcut { Shortcut(input: nil, modifiers: modifiers) }
    static func mouse(_ button: Int, _ modifiers: Modifiers = []) -> Shortcut { Shortcut(input: .mouseButton(button), modifiers: modifiers) }

    /// Nil for modifier-only presses and anything other than a supported key-down event.
    init?(keyEvent event: NSEvent) {
        guard event.type == .keyDown, Self.supports(keyCode: event.keyCode),
              !event.modifierFlags.contains(.function) || Self.functionKeyCodes.contains(Int(event.keyCode))
                || Self.navigationKeyCodes.contains(Int(event.keyCode)) else { return nil }
        self.init(input: .key(event.keyCode), modifiers: Modifiers(flags: event.modifierFlags))
    }

    var keyCode: UInt16? {
        if case .key(let code) = input { code } else { nil }
    }

    var mouseButton: Int? {
        if case .mouseButton(let button) = input { button } else { nil }
    }

    var isModifierOnly: Bool { input == nil }

    /// Modifier-only chords and mouse buttons are watched with an event tap, which needs Accessibility.
    var needsEventTap: Bool { keyCode == nil }

    var hasCommandOrControl: Bool { !modifiers.isDisjoint(with: [.command, .control]) }

    var isFunctionKey: Bool { keyCode.map { Self.functionKeyCodes.contains(Int($0)) } ?? false }

    var isSupported: Bool {
        guard modifiers.rawValue & ~UInt8(15) == 0 else { return false }
        switch input {
        case .key(let code): return Self.supports(keyCode: code)
        case .mouseButton(let button): return (2...31).contains(button)
        case nil: return modifiers.count >= 2
        }
    }

    private static func supports(keyCode: UInt16) -> Bool {
        keyCode <= 126 && !modifierKeyCodes.contains(Int(keyCode))
            && ![kVK_VolumeUp, kVK_VolumeDown, kVK_Mute].contains(Int(keyCode))
    }

    static let functionKeyCodes: [Int] = [
        kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
        kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    ]

    private static let navigationKeyCodes: Set<Int> = [
        kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown, kVK_ForwardDelete,
        kVK_LeftArrow, kVK_RightArrow, kVK_UpArrow, kVK_DownArrow,
    ]

    var carbonModifiers: UInt32 {
        var result = 0
        if modifiers.contains(.control) { result |= controlKey }
        if modifiers.contains(.option) { result |= optionKey }
        if modifiers.contains(.shift) { result |= shiftKey }
        if modifiers.contains(.command) { result |= cmdKey }
        return UInt32(result)
    }

    @MainActor var displayString: String {
        let symbols = Self.symbols(modifiers)
        switch input {
        case .key(let code): return symbols + KeyNames.name(for: code)
        case .mouseButton(let button):
            let name = button == 2 ? "Middle Click" : "Mouse \(button + 1)"
            return symbols.isEmpty ? name : "\(symbols) \(name)"
        case nil: return symbols
        }
    }

    /// For SwiftUI menu items; nil when the shortcut has no menu key equivalent.
    @MainActor var keyboardShortcut: KeyboardShortcut? {
        guard let keyCode, let key = KeyNames.keyEquivalent(for: keyCode) else { return nil }
        var eventModifiers: SwiftUI.EventModifiers = []
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        return KeyboardShortcut(key, modifiers: eventModifiers)
    }

    static func symbols(_ modifiers: Modifiers) -> String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
    }

    static let modifierKeyCodes: Set<Int> = [
        kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_Option, kVK_RightOption,
        kVK_Control, kVK_RightControl, kVK_CapsLock, kVK_Function,
    ]
}

extension Shortcut.Modifiers {
    /// Keeps ⌃⌥⇧⌘ from AppKit modifier flags and drops the rest, such as Caps Lock.
    init(flags: NSEvent.ModifierFlags) {
        self = []
        if flags.contains(.control) { insert(.control) }
        if flags.contains(.option) { insert(.option) }
        if flags.contains(.shift) { insert(.shift) }
        if flags.contains(.command) { insert(.command) }
    }

    /// The same, from Core Graphics event flags.
    init(flags: CGEventFlags) {
        self = []
        if flags.contains(.maskControl) { insert(.control) }
        if flags.contains(.maskAlternate) { insert(.option) }
        if flags.contains(.maskShift) { insert(.shift) }
        if flags.contains(.maskCommand) { insert(.command) }
    }
}

/// Key names for display and menu key equivalents.
@MainActor
enum KeyNames {
    private static let special: [Int: (name: String, key: KeyEquivalent)] = [
        kVK_Return: ("↩", .return), kVK_Tab: ("⇥", .tab), kVK_Space: ("Space", .space),
        kVK_Delete: ("⌫", .delete), kVK_ForwardDelete: ("⌦", .deleteForward), kVK_Escape: ("⎋", .escape),
        kVK_LeftArrow: ("←", .leftArrow), kVK_RightArrow: ("→", .rightArrow),
        kVK_UpArrow: ("↑", .upArrow), kVK_DownArrow: ("↓", .downArrow),
        kVK_Home: ("↖", .home), kVK_End: ("↘", .end), kVK_PageUp: ("⇞", .pageUp), kVK_PageDown: ("⇟", .pageDown),
        kVK_ANSI_KeypadEnter: ("⌤", .return),
    ]

    static func name(for keyCode: UInt16) -> String {
        let code = Int(keyCode)
        if let special = special[code] { return special.name }
        if let index = Shortcut.functionKeyCodes.firstIndex(of: code) { return "F\(index + 1)" }
        return character(for: keyCode).map { String($0).uppercased() } ?? "Key \(keyCode)"
    }

    static func keyEquivalent(for keyCode: UInt16) -> KeyEquivalent? {
        let code = Int(keyCode)
        if let special = special[code] { return special.key }
        if let index = Shortcut.functionKeyCodes.firstIndex(of: code),
           let scalar = Unicode.Scalar(NSF1FunctionKey + index) {
            return KeyEquivalent(Character(scalar))
        }
        return character(for: keyCode).map { KeyEquivalent(Character($0.lowercased())) }
    }

    /// The unmodified character on the current ASCII-capable layout, like menu key equivalents.
    static func character(for keyCode: UInt16) -> Character? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes -> OSStatus in
            guard let base = bytes.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return OSStatus(paramErr) }
            return UCKeyTranslate(base, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, characters.count,
                                  &length, &characters)
        }
        guard status == noErr, length > 0,
              let text = String(utf16CodeUnits: characters, count: length).first,
              !text.isWhitespace else { return nil }
        return text
    }
}
