import CoreGraphics
import Foundation

// Typed, persisted preference sections. Each section is one Codable value stored by
// AppPreferences; `isValid` rejects writes that would leave the app unusable.

enum AppearancePreference: String, Codable, CaseIterable, Sendable {
    case system, light, dark
}

struct GeneralPreferences: Codable, Equatable, Sendable {
    var appearance = AppearancePreference.system
    var showsMenuBarIcon = true
    var showsDockIcon = false

    /// Both icons may be hidden; reopening Spotty from Finder or Spotlight shows Settings.
    var isValid: Bool { true }
}

/// An sRGB color with components in 0...1, independent of the app appearance.
struct RGBAColor: Codable, Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha = 1.0

    static let white = RGBAColor(red: 1, green: 1, blue: 1)
    static let black = RGBAColor(red: 0, green: 0, blue: 0)
    static let annotationRed = RGBAColor(red: 0.976, green: 0.204, blue: 0.259)
    static let annotationBlue = RGBAColor(red: 0, green: 0.48, blue: 1)
    static let highlighterYellow = RGBAColor(red: 1, green: 0.882, blue: 0)

    /// Shotty's annotation colors, in menu order.
    static let palette: [(name: String, color: RGBAColor)] = [
        ("Black", .black), ("Red", .annotationRed), ("Orange", RGBAColor(red: 1, green: 0.549, blue: 0)),
        ("Yellow", .highlighterYellow), ("Green", RGBAColor(red: 0.25, green: 0.84, blue: 0.32)),
        ("Teal", RGBAColor(red: 0.18, green: 0.81, blue: 0.76)), ("Blue", .annotationBlue),
        ("Purple", RGBAColor(red: 0.54, green: 0.32, blue: 1)), ("Pink", RGBAColor(red: 1, green: 0.18, blue: 0.42)),
        ("White", .white),
    ]

    var isValid: Bool { [red, green, blue, alpha].allSatisfy { (0...1).contains($0) } }

    var cgColor: CGColor {
        CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [red, green, blue, alpha])!
    }

    func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(red: red, green: green, blue: blue, alpha: alpha) }

    /// Converts any color to sRGB; nil when the color cannot be represented.
    init?(_ color: CGColor) {
        guard let converted = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 4 else { return nil }
        self.init(red: min(max(components[0], 0), 1), green: min(max(components[1], 0), 1),
                  blue: min(max(components[2], 0), 1), alpha: min(max(components[3], 0), 1))
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// Values one tool sets apart from the default style. Nil follows the default style.
struct StyleOverrides: Codable, Hashable, Sendable {
    var color: RGBAColor?
    var width: Double?
    var cornerRadius: Double?

    var isEmpty: Bool { self == StyleOverrides() }
}

/// The look of a tool's new marks, with its overrides applied over the default style.
struct ToolStyle: Equatable, Sendable {
    var color: RGBAColor
    var width: Double
    var cornerRadius: Double
}

struct DrawingPreferences: Codable, Equatable, Sendable {
    static let widthRange = 1.0...24.0
    static let highlighterWidthRange = 4.0...48.0
    static let cornerRadiusRange = 0.0...40.0
    static let dimmingRange = 20.0...80.0
    static let fadeDelayRange = 0.5...600.0

    /// The tool Draw starts with; nil starts with the last used tool.
    var startTool: DrawingTool?
    /// Remembered across launches for `startTool == nil`.
    var lastTool = DrawingTool.highlighter

    // The default style. Pen, arrow, and rectangle use all of it; spotlights use the corner radius.
    var color = RGBAColor.annotationRed
    var lineWidth = 4.0
    /// In points. Zero draws hard corners.
    var cornerRadius = 0.0
    /// Pen, arrow, rectangle, and spotlight values that differ from the default style.
    var overrides: [DrawingTool: StyleOverrides] = [:]

    /// The highlighter has its own style, drawn translucent like a marker.
    var highlighterColor = RGBAColor.highlighterYellow
    var highlighterWidth = 16.0
    /// How dark the screen gets around spotlights, in percent.
    var spotlightDimming = 50.0

    /// Off keeps drawings until cleared.
    var fadesDrawings = true
    /// Seconds each drawing stays after you finish it.
    var fadeDelay = 2.0

    var isValid: Bool {
        color.isValid && highlighterColor.isValid && Self.widthRange.contains(lineWidth)
            && Self.highlighterWidthRange.contains(highlighterWidth) && Self.cornerRadiusRange.contains(cornerRadius)
            && overrides.values.allSatisfy { custom in
                custom.color?.isValid ?? true && custom.width.map(Self.widthRange.contains) ?? true
                    && custom.cornerRadius.map(Self.cornerRadiusRange.contains) ?? true
            }
            && Self.dimmingRange.contains(spotlightDimming) && Self.fadeDelayRange.contains(fadeDelay)
    }

    /// How new marks of `tool` look.
    func style(for tool: DrawingTool) -> ToolStyle {
        if tool == .highlighter { return ToolStyle(color: highlighterColor, width: highlighterWidth, cornerRadius: 0) }
        let custom = overrides[tool]
        return ToolStyle(color: custom?.color ?? color, width: custom?.width ?? lineWidth,
                         cornerRadius: custom?.cornerRadius ?? cornerRadius)
    }

    /// The toolbar's color menu. A tool with its own color changes only that; otherwise the
    /// default color changes, for every tool that follows it.
    mutating func setColor(_ newColor: RGBAColor, for tool: DrawingTool) {
        if tool == .highlighter {
            highlighterColor = newColor
        } else if overrides[tool]?.color != nil {
            overrides[tool]?.color = newColor
        } else {
            color = newColor
        }
    }

    /// One tool's overrides. Clearing the last one removes the tool's entry.
    subscript(overrides tool: DrawingTool) -> StyleOverrides {
        get { overrides[tool] ?? StyleOverrides() }
        set { overrides[tool] = newValue.isEmpty ? nil : newValue }
    }

    /// How long a finished drawing stays; nil keeps it until cleared.
    var fadeAfter: Duration? { fadesDrawings ? .seconds(fadeDelay) : nil }

    /// The tool Draw starts with now.
    var resolvedStartTool: DrawingTool { startTool ?? lastTool }
}
