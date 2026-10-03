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

/// Pen strokes and rectangle outlines.
enum StrokePattern: String, Codable, CaseIterable, Sendable { case solid, dashed, dotted }
enum HighlighterTip: String, Codable, CaseIterable, Sendable { case round, flat }
/// Open draws the head as two strokes; curved bends toward where the drag went.
enum ArrowStyle: String, Codable, CaseIterable, Sendable { case standard, open, double, curved }
/// Tinted adds a light fill inside the outline.
enum RectangleStyle: String, Codable, CaseIterable, Sendable { case outline, dashed, tinted }

/// Default-style values one tool sets apart. Nil follows the default style.
struct StyleOverrides: Codable, Hashable, Sendable {
    var color: RGBAColor?
    var width: Double?

    var isEmpty: Bool { self == StyleOverrides() }
}

/// How a tool's new marks look, resolved from the default style and the tool's own options.
/// Each tool reads only the fields that apply to it.
struct ToolStyle: Equatable, Sendable {
    var color: RGBAColor
    var width: Double
    /// Rectangles, spotlights, and arrow heads and tails. Zero draws hard corners.
    var cornerRadius = 0.0
    /// Pens and rectangles.
    var pattern = StrokePattern.solid
    var arrow = ArrowStyle.standard
    /// Rectangles: a light fill inside the outline.
    var isTinted = false
    /// Highlighters: square stroke ends instead of round ones.
    var hasFlatTips = false
    /// Highlighters: how far a stroke may waver and still straighten into a line; nil keeps it freehand.
    var straightenTolerance: Double?
}

struct DrawingPreferences: Codable, Equatable, Sendable {
    static let widthRange = 1.0...24.0
    static let highlighterWidthRange = 4.0...48.0
    static let cornerRadiusRange = 0.0...40.0
    static let arrowCornerRadiusRange = 0.0...12.0
    static let straightenToleranceRange = 2.0...20.0
    static let dimmingRange = 20.0...80.0
    static let fadeDelayRange = 0.5...600.0

    /// The tool Draw starts with; nil starts with the last used tool.
    var startTool: DrawingTool?
    /// Remembered across launches for `startTool == nil`.
    var lastTool = DrawingTool.highlighter
    /// Off keeps drawings until cleared.
    var fadesDrawings = true
    /// Seconds each drawing stays after you finish it.
    var fadeDelay = 2.0

    // The default style, shared by pen, arrow, and rectangle.
    var color = RGBAColor.annotationRed
    var lineWidth = 4.0
    /// Pen, arrow, and rectangle values that differ from the default style.
    var overrides: [DrawingTool: StyleOverrides] = [:]

    var penPattern = StrokePattern.solid

    /// The highlighter has its own color and width, drawn translucent like a marker.
    var highlighterColor = RGBAColor.highlighterYellow
    var highlighterWidth = 16.0
    var highlighterTip = HighlighterTip.flat
    var straightensHighlighter = false
    var straightenTolerance = 6.0

    var arrowStyle = ArrowStyle.standard
    var arrowCornerRadius = 2.0

    var rectangleStyle = RectangleStyle.outline
    var rectangleCornerRadius = 0.0

    var spotlightCornerRadius = 0.0
    /// How dark the screen gets around spotlights, in percent.
    var spotlightDimming = 50.0

    var isValid: Bool {
        color.isValid && highlighterColor.isValid && Self.widthRange.contains(lineWidth)
            && Self.highlighterWidthRange.contains(highlighterWidth)
            && overrides.values.allSatisfy { custom in
                custom.color?.isValid ?? true && custom.width.map(Self.widthRange.contains) ?? true
            }
            && Self.straightenToleranceRange.contains(straightenTolerance)
            && Self.arrowCornerRadiusRange.contains(arrowCornerRadius)
            && Self.cornerRadiusRange.contains(rectangleCornerRadius) && Self.cornerRadiusRange.contains(spotlightCornerRadius)
            && Self.dimmingRange.contains(spotlightDimming) && Self.fadeDelayRange.contains(fadeDelay)
    }

    /// How new marks of `tool` look.
    func style(for tool: DrawingTool) -> ToolStyle {
        let custom = self[overrides: tool]
        var style = ToolStyle(color: custom.color ?? color, width: custom.width ?? lineWidth)
        switch tool {
        case .pen:
            style.pattern = penPattern
        case .highlighter:
            style = ToolStyle(color: highlighterColor, width: highlighterWidth, hasFlatTips: highlighterTip == .flat,
                              straightenTolerance: straightensHighlighter ? straightenTolerance : nil)
        case .arrow:
            style.arrow = arrowStyle
            style.cornerRadius = arrowCornerRadius
        case .rectangle:
            style.pattern = rectangleStyle == .dashed ? .dashed : .solid
            style.isTinted = rectangleStyle == .tinted
            style.cornerRadius = rectangleCornerRadius
        case .spotlight:
            style.cornerRadius = spotlightCornerRadius
        }
        return style
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

    /// Build 11 kept one corner radius in the default style, which tools could override. Rectangles
    /// and spotlights now keep their own, starting from the radius they drew with.
    static func migrate(_ stored: [String: Any]) -> [String: Any] {
        var stored = stored
        guard let radius = stored.removeValue(forKey: "cornerRadius") as? Double else { return stored }
        let overrides = stored["overrides"] as? [String: [String: Any]] ?? [:]
        for (tool, key) in [(DrawingTool.rectangle, "rectangleCornerRadius"), (.spotlight, "spotlightCornerRadius")] where stored[key] == nil {
            stored[key] = overrides[tool.rawValue]?["cornerRadius"] as? Double ?? radius
        }
        // Overrides no longer hold a radius; drop entries left empty without it.
        stored["overrides"] = overrides.compactMapValues { custom in
            let rest = custom.filter { $0.key != "cornerRadius" }
            return rest.isEmpty ? nil : rest
        }
        return stored
    }
}
