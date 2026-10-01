import CoreGraphics

/// One drawing in view points. Shapes use their first and last point; freehand tools use all.
struct Mark: Equatable, Sendable {
    let tool: DrawingTool
    var points: [CGPoint]
    let color: RGBAColor
    let width: CGFloat
    /// Shift: straight freehand lines, 45° arrows, squares, and circles.
    var isConstrained = false

    init(tool: DrawingTool, at point: CGPoint, color: RGBAColor, width: CGFloat) {
        self.tool = tool
        points = [point]
        self.color = color
        self.width = width
    }

    var start: CGPoint { points[0] }

    /// The drag end, adjusted for Shift.
    var end: CGPoint {
        let end = points[points.count - 1]
        guard isConstrained else { return end }
        switch tool {
        case .rectangle, .ellipse, .spotlight: return MarkGeometry.squared(from: start, to: end)
        case .arrow, .pen, .highlighter: return MarkGeometry.snapped(from: start, to: end)
        }
    }

    mutating func add(_ point: CGPoint) {
        switch tool {
        case .pen, .highlighter:
            // Skip sub-point jitter; it only adds path segments.
            if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
            points.append(point)
        default:
            points = [start, point]
        }
    }

    /// Too small to keep, like a click without a drag.
    var isEmpty: Bool {
        switch tool {
        case .pen, .highlighter: return points.count < 2
        case .arrow: return hypot(end.x - start.x, end.y - start.y) < 8
        case .rectangle, .ellipse, .spotlight:
            let rect = MarkGeometry.rect(start, end)
            return rect.width < 4 && rect.height < 4
        }
    }

    /// Straightens a highlighter stroke that was meant as a line, as along a line of text.
    mutating func finish() {
        guard tool == .highlighter, !isConstrained, points.count > 2,
              MarkGeometry.isNearlyStraight(points, tolerance: max(4, width * 0.3)) else { return }
        points = [start, points[points.count - 1]]
    }

    /// Highlighter strokes are translucent and four times as wide.
    var strokeWidth: CGFloat { tool == .highlighter ? width * 4 : width }

    /// What to draw: a stroked path, or a filled one for arrows. Spotlights cut the dimming instead.
    var shape: (path: CGPath, filled: Bool) {
        switch tool {
        case .pen, .highlighter:
            if isConstrained || points.count == 2 {
                let path = CGMutablePath(); path.move(to: start); path.addLine(to: end)
                return (path, false)
            }
            return (MarkGeometry.smoothPath(points), false)
        case .arrow:
            return (MarkGeometry.arrow(from: start, to: end, width: width), true)
        case .rectangle:
            let rect = MarkGeometry.rect(start, end)
            let radius = min(width * 1.5, rect.width / 2, rect.height / 2)
            return (CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil), false)
        case .ellipse:
            return (CGPath(ellipseIn: MarkGeometry.rect(start, end), transform: nil), false)
        case .spotlight:
            return (MarkGeometry.spotlight(MarkGeometry.rect(start, end)), true)
        }
    }
}

enum MarkGeometry {
    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    /// The end of a square drag: the longer side wins, keeping the drag's direction.
    static func squared(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let side = max(abs(end.x - start.x), abs(end.y - start.y))
        return CGPoint(x: start.x + (end.x >= start.x ? side : -side), y: start.y + (end.y >= start.y ? side : -side))
    }

    /// The end snapped to the nearest 45° direction, keeping the length.
    static func snapped(from start: CGPoint, to end: CGPoint) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y
        let step = CGFloat.pi / 4
        let angle = (atan2(dy, dx) / step).rounded() * step
        let length = hypot(dx, dy)
        return CGPoint(x: start.x + cos(angle) * length, y: start.y + sin(angle) * length)
    }

    /// Whether every point lies within `tolerance` of the line from the first to the last point.
    static func isNearlyStraight(_ points: [CGPoint], tolerance: CGFloat) -> Bool {
        guard let first = points.first, let last = points.last else { return false }
        let dx = last.x - first.x, dy = last.y - first.y
        let length = hypot(dx, dy)
        // Short strokes are scribbles, not lines.
        guard length >= 24 else { return false }
        return points.allSatisfy { abs(($0.x - first.x) * dy - ($0.y - first.y) * dx) / length <= tolerance }
    }

    /// Quadratic curves through the midpoints of consecutive points, which hides mouse sampling corners.
    static func smoothPath(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 2 else {
            points.dropFirst().forEach { path.addLine(to: $0) }
            return path
        }
        for index in 1..<(points.count - 1) {
            let point = points[index], next = points[index + 1]
            path.addQuadCurve(to: CGPoint(x: (point.x + next.x) / 2, y: (point.y + next.y) / 2), control: point)
        }
        path.addLine(to: points[points.count - 1])
        return path
    }

    /// A filled arrow outline: a round-capped shaft that stops at the head's base, plus the head.
    /// Proportions match Shotty's arrows.
    static func arrow(from start: CGPoint, to end: CGPoint, width: CGFloat) -> CGPath {
        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength = max(9, width * 3.5), halfWidth = max(4, width * 1.5)
        let base = CGPoint(x: end.x - cos(angle) * headLength, y: end.y - sin(angle) * headLength)
        let head = CGMutablePath()
        head.move(to: end)
        head.addLine(to: CGPoint(x: base.x - sin(angle) * halfWidth, y: base.y + cos(angle) * halfWidth))
        head.addLine(to: CGPoint(x: base.x + sin(angle) * halfWidth, y: base.y - cos(angle) * halfWidth))
        head.closeSubpath()
        guard hypot(end.x - start.x, end.y - start.y) > headLength else { return head }
        let shaft = CGMutablePath()
        shaft.move(to: start)
        shaft.addLine(to: base)
        return shaft.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10).union(head)
    }

    static let spotlightRadius: CGFloat = 12

    static func spotlight(_ rect: CGRect) -> CGPath {
        let radius = min(spotlightRadius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The dimmed area: everything in `bounds` outside the spotlights.
    static func dimming(_ bounds: CGRect, spotlights: [CGPath]) -> CGPath {
        guard let first = spotlights.first else { return CGPath(rect: bounds, transform: nil) }
        let holes = spotlights.dropFirst().reduce(first) { $0.union($1) }
        return CGPath(rect: bounds, transform: nil).subtracting(holes)
    }
}
