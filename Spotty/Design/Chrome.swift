import AppKit
import SwiftUI

/// Design tokens for Spotty's floating chrome, shared with Shotty: the drawing overlay and the
/// toolbar shown while drawing is toggled on. The toolbar uses Shotty's editor bar metrics and
/// its capsule tool strip. Settings draws its own colors, in SettingsTheme.
@MainActor
enum Chrome {
    /// The drawing overlay sits just below the cursor: above app windows, full-screen apps,
    /// the menu bar, and other apps' floating panels.
    static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.cursorWindow)) - 2)
    /// The toolbar floats above the overlay.
    static let toolbarLevel = NSWindow.Level(rawValue: overlayLevel.rawValue + 1)

    static let fadeDuration: TimeInterval = 0.15
    /// Drawings fade out slower than chrome, so the eye can follow them leaving.
    static let drawingFadeDuration: TimeInterval = 0.4

    static var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}

/// Shotty's editor bar metrics: 26 pt capsule buttons filled with a light tint, and a 24 pt
/// capsule strip for the drawing tools.
enum Bar {
    static let height: CGFloat = 40
    static let buttonHeight: CGFloat = 26
    static let font = Font.system(size: 13, weight: .medium)
    static let toolHeight: CGFloat = 24
    static let toolWidth: CGFloat = 35
    static let edgeInset: CGFloat = 7
    static let groupSpacing: CGFloat = 10

    /// Button fill: white at 20% in Dark Mode, black at 10% in Light Mode.
    static let buttonFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.2) : NSColor(white: 0, alpha: 0.1)
    })
    /// Tool strip fill, half the button tint.
    static let groupFill = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(white: 1, alpha: 0.1) : NSColor(white: 0, alpha: 0.05)
    })
}

/// A 26 pt capsule: tinted by default, accent-filled when prominent.
struct BarButtonStyle: ButtonStyle {
    var isProminent = false
    var width: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Bar.font)
            .foregroundStyle(isProminent ? Color.white : .primary)
            .padding(.horizontal, width == nil ? 12 : 0)
            .frame(width: width, height: Bar.buttonHeight)
            .background(isProminent ? Color.accentColor : Bar.buttonFill, in: Capsule())
            .overlay(Capsule().fill(Color.black.opacity(configuration.isPressed ? 0.15 : 0)))
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == BarButtonStyle {
    static var bar: Self { .init() }
    static var barProminent: Self { .init(isProminent: true) }
}
