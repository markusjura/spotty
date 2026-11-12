/// The drawing tools, in toolbar and menu order.
enum DrawingTool: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case pen, line, highlighter, arrow, rectangle, spotlight

    var title: String {
        switch self {
        case .pen: "Pen"
        case .line: "Line"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .spotlight: "Spotlight"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "scribble"
        case .line: "line.diagonal"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .spotlight: "rectangle.center.inset.filled"
        }
    }
}
