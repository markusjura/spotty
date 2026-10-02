/// The drawing tools, in toolbar and menu order.
enum DrawingTool: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case pen, highlighter, arrow, rectangle, spotlight

    var title: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .arrow: "Arrow"
        case .rectangle: "Rectangle"
        case .spotlight: "Spotlight"
        }
    }

    var symbol: String {
        switch self {
        case .pen: "scribble"
        case .highlighter: "highlighter"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .spotlight: "rectangle.center.inset.filled"
        }
    }
}
