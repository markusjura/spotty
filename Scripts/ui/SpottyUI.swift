import AppKit
import CoreGraphics

// Drives Spotty with posted input and reports its windows as text. Computer Use cannot hold
// a key or a mouse button while dragging, which every hold-to-draw check needs.
// Posting events needs Accessibility access for the app running this tool, such as the terminal.
//
// Usage:
//   spotty-ui windows                 Spotty's on-screen windows: id, layer, bounds, alpha
//   spotty-ui run "<steps>"           Posts steps separated by ';' in one process:
//     mods ctrl,shift                 sets held modifiers (posts flagsChanged); `mods` alone releases them
//     key a | keydown a | keyup a     a key with the held modifiers (letters, digits, esc, delete, space)
//     drag x,y x,y                    a left-button drag in global points from the top left of the main display
//     click x,y                       a left click
//     button 3 down|up                a middle (2) or side (3, 4) mouse button
//     wait 0.3                        seconds

let arguments = Array(CommandLine.arguments.dropFirst())
let source = CGEventSource(stateID: .hidSystemState)
var flags: CGEventFlags = []

let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14,
    "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
    "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
    "esc": 53, "delete": 51, "space": 49, "return": 36, "f18": 79,
]
let modifierKeys: [String: (CGEventFlags, CGKeyCode)] = [
    "ctrl": (.maskControl, 59), "shift": (.maskShift, 56), "option": (.maskAlternate, 58), "cmd": (.maskCommand, 55),
]

func post(_ event: CGEvent?) {
    event?.post(tap: .cghidEventTap)
    usleep(8_000)
}

func point(_ text: Substring) -> CGPoint {
    let parts = text.split(separator: ",").compactMap { Double($0) }
    return CGPoint(x: parts[0], y: parts[1])
}

func mouse(_ type: CGEventType, _ at: CGPoint, button: CGMouseButton = .left, number: Int64 = 0) {
    let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: at, mouseButton: button)
    event?.flags = flags
    if number > 0 { event?.setIntegerValueField(.mouseEventButtonNumber, value: number) }
    post(event)
}

func key(_ name: Substring, down: Bool) {
    guard let code = keyCodes[String(name)] else { fatalError("Unknown key \(name)") }
    let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down)
    event?.flags = flags
    post(event)
}

/// Presses or releases modifiers one at a time, as a keyboard does.
func setModifiers(_ names: [Substring]) {
    let wanted = names.compactMap { modifierKeys[String($0)] }
    let target = wanted.reduce(CGEventFlags()) { $0.union($1.0) }
    for (flag, code) in modifierKeys.values where flags.contains(flag) != target.contains(flag) {
        if target.contains(flag) { flags.insert(flag) } else { flags.remove(flag) }
        let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: target.contains(flag))
        event?.type = .flagsChanged
        event?.flags = flags
        post(event)
    }
}

func run(_ steps: String) {
    for step in steps.split(separator: ";") {
        let words = step.split(separator: " ")
        guard let command = words.first else { continue }
        switch command {
        case "mods": setModifiers(words.count > 1 ? words[1].split(separator: ",") : [])
        case "key": key(words[1], down: true); key(words[1], down: false)
        case "keydown": key(words[1], down: true)
        case "keyup": key(words[1], down: false)
        case "wait": usleep(useconds_t((Double(words[1]) ?? 0) * 1_000_000))
        case "click":
            let at = point(words[1])
            mouse(.mouseMoved, at); mouse(.leftMouseDown, at); mouse(.leftMouseUp, at)
        case "drag":
            let from = point(words[1]), to = point(words[2])
            mouse(.mouseMoved, from)
            mouse(.leftMouseDown, from)
            for index in 1...20 {
                let t = CGFloat(index) / 20
                mouse(.leftMouseDragged, CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t))
            }
            mouse(.leftMouseUp, to)
        case "button":
            let number = Int64(words[1]) ?? 2
            let at = CGEvent(source: nil)?.location ?? .zero
            mouse(words[2] == "down" ? .otherMouseDown : .otherMouseUp, at, button: .center, number: number)
        default: fatalError("Unknown step \(step)")
        }
    }
}

func windows() {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    for window in list where window[kCGWindowOwnerName as String] as? String == "Spotty" {
        let bounds = window[kCGWindowBounds as String] as? [String: Double] ?? [:]
        print("id \(window[kCGWindowNumber as String] ?? 0) layer \(window[kCGWindowLayer as String] ?? 0)",
              "bounds \(Int(bounds["X"] ?? 0)),\(Int(bounds["Y"] ?? 0)) \(Int(bounds["Width"] ?? 0))x\(Int(bounds["Height"] ?? 0))",
              "alpha \(window[kCGWindowAlpha as String] ?? 0)", "name \(window[kCGWindowName as String] ?? "")")
    }
}

switch arguments.first {
case "windows": windows()
case "run" where arguments.count == 2: run(arguments[1])
default:
    print("Usage: spotty-ui windows | spotty-ui run \"mods ctrl,shift; drag 400,400 600,500; mods\"")
    exit(1)
}
