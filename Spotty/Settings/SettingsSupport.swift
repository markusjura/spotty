import AppKit
import SwiftUI

extension AppearancePreference {
    /// Nil follows the system appearance.
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

extension GeneralPreferences {
    var activationPolicy: NSApplication.ActivationPolicy { showsDockIcon ? .regular : .accessory }
}

/// System Settings destinations used by the Settings panes.
enum SystemSettingsLink {
    static let accessibility = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    static let privacy = URL(string: "x-apple.systempreferences:com.apple.preference.security")!

    /// Falls back to Privacy & Security if a deep link stops resolving.
    static func open(_ url: URL) {
        if !NSWorkspace.shared.open(url) { NSWorkspace.shared.open(privacy) }
    }
}
