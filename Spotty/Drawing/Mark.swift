import CoreGraphics

/// One drawing in view points. Shapes use their first and last point; freehand tools and curved
/// arrows use all, a curved arrow to find which way to bend.
struct Mark: Equatable, Sendable {
    let tool: DrawingTool
    var points: [CGPoint]
    let style: ToolStyle
    /// Shift: straight freehand lines, 45° arrows, and squares.
    var isConstrained = false

    init(tool: DrawingTool, at point: CGPoint, style: ToolStyle) {
        self.tool = tool
        points = [point]
        self.style = style
    }

    var start: CGPoint { points[0] }
    var width: CGFloat { style.width }

    /// The drag end, adjusted for Shift.
    var end: CGPoint {
        let end = points[points.count - 1]
        guard isConstrained else { return end }
        switch tool {
        case .rectangle, .spotlight: return MarkGeometry.squared(from: start, to: end)
        case .arrow, .pen, .highlighter: return MarkGeometry.snapped(from: start, to: end)
        }
    }

    /// Whether the mark keeps every dragged point.
    private var keepsPath: Bool {
        tool == .pen || tool == .highlighter || (tool == .arrow && style.arrow == .curved)
    }

    mutating func add(_ point: CGPoint) {
        guard keepsPath else { points = [start, point]; return }
        // Skip sub-point jitter; it only adds path segments.
        if let last = points.last, hypot(point.x - last.x, point.y - last.y) < 1 { return }
        points.append(point)
    }

    /// Too small to keep, like a click without a drag.
    var isEmpty: Bool {
        switch tool {
        case .pen, .highlighter: return points.count < 2
        case .arrow: return hypot(end.x - start.x, end.y - start.y) < 8
        case .rectangle, .spotlight:
            let rect = MarkGeometry.rect(start, end)
            return rect.width < 4 && rect.height < 4
        }
    }

    /// Straightens a highlighter stroke that was meant as a line, as along a line of text, when
    /// the highlighter straightens strokes.
    mutating func finish() {
        guard tool == .highlighter, let tolerance = style.straightenTolerance, !isConstrained, points.count > 2,
              MarkGeometry.isNearlyStraight(points, tolerance: tolerance) else { return }
        points = [start, points[points.count - 1]]
    }

    /// How to draw the mark in its color and width. Spotlights cut the dimming with `path` instead.
    var paint: Paint {
        let width = style.width
        switch tool {
        case .pen, .highlighter:
            let path: CGPath
            if isConstrained || points.count == 2 {
                let line = CGMutablePath(); line.move(to: start); line.addLine(to: end)
                path = line
            } else {
                path = MarkGeometry.smoothPath(points)
            }
            if tool == .highlighter { return Paint(path: path, cap: style.hasFlatTips ? .butt : .round) }
            return Paint(path: path, dash: style.pattern.dash(width: width))
        case .arrow:
            let bend = style.arrow == .curved ? MarkGeometry.bend(from: start, to: end, along: points) : nil
            return Paint(path: MarkGeometry.arrow(from: start, to: end, width: width, style: style.arrow, bend: bend,
                                                  cornerRadius: style.cornerRadius), fill: 1, stroke: false)
        case .rectangle:
            let rounded = style.cornerRadius > 0
            return Paint(path: MarkGeometry.roundedRect(MarkGeometry.rect(start, end), radius: style.cornerRadius),
                         fill: style.isTinted ? 0.2 : 0, dash: style.pattern.dash(width: width),
                         cap: style.pattern == .solid ? .round : .butt, join: rounded ? .round : .miter)
        case .spotlight:
            return Paint(path: MarkGeometry.roundedRect(MarkGeometry.rect(start, end), radius: style.cornerRadius), fill: 1, stroke: false)
        }
    }
}

/// How a mark paints its path with its color and width.
struct Paint {
    var path: CGPath
    /// Fill opacity relative to the mark's color; zero leaves the inside clear.
    var fill = 0.0
    var stroke = true
    /// Dash and gap lengths; empty for a solid stroke.
    var dash: [CGFloat] = []
    var cap = CGLineCap.round
    var join = CGLineJoin.round
}

extension StrokePattern {
    /// Dash lengths for a stroke `width` wide. Round caps add half a width to each end of a dash.
    func dash(width: CGFloat) -> [CGFloat] {
        switch self {
        case .solid: []
        case .dashed: [width * 2, width * 2.5]
        case .dotted: [0, width * 2]
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

    /// The control point of a curved arrow. The curve peaks as far from the straight line as the
    /// drag went, on the same side. A nearly straight drag bends by a tenth of the length, toward
    /// the left of the drag direction, as in Shotty.
    static func bend(from start: CGPoint, to end: CGPoint, along path: [CGPoint]) -> CGPoint {
        let dx = end.x - start.x, dy = end.y - start.y, length = hypot(dx, dy)
        let middle = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        guard length > 0 else { return middle }
        // Points sit at `start + normal * offset` along the line.
        let normal = CGPoint(x: dy / length, y: -dx / length)
        let offset = { (p: CGPoint) in ((p.x - start.x) * dy - (p.y - start.y) * dx) / length }
        let farthest = path.map(offset).max { abs($0) < abs($1) } ?? 0
        // A quadratic peaks halfway between the chord's middle and its control point.
        let control = abs(farthest) < max(8, length * 0.06) ? -length * 0.2 : min(max(farthest * 2, -length), length)
        return CGPoint(x: middle.x + normal.x * control, y: middle.y + normal.y * control)
    }

    /// A filled arrow outline with Shotty's proportions: a head 3.5 widths long and 3 wide.
    /// `cornerRadius` rounds the head's corners, and any radius gives the tail a round end.
    /// `bend` is the control point of a curved shaft.
    static func arrow(from start: CGPoint, to end: CGPoint, width: CGFloat, style: ArrowStyle = .standard,
                      bend: CGPoint? = nil, cornerRadius: CGFloat = 0) -> CGPath {
        let headLength = max(9, width * 3.5), halfWidth = max(4, width * 1.5)
        let cap: CGLineCap = cornerRadius > 0 ? .round : .butt
        let length = hypot(end.x - start.x, end.y - start.y)
        // Shafts end inside the head, so their ends never show beside it.
        let tuck = headLength / 2

        if style == .open {
            let angle = atan2(end.y - start.y, end.x - start.x)
            let wings = headPoints(at: end, angle: angle, length: headLength, halfWidth: halfWidth)
            let lines = CGMutablePath()
            lines.move(to: start); lines.addLine(to: end)
            lines.move(to: wings[1]); lines.addLine(to: end); lines.addLine(to: wings[2])
            return lines.copy(strokingWithWidth: width, lineCap: cap, lineJoin: cornerRadius > 0 ? .round : .miter, miterLimit: 10)
        }

        if let bend {
            let angle = atan2(end.y - bend.y, end.x - bend.x)
            let head = roundedPolygon(headPoints(at: end, angle: angle, length: headLength, halfWidth: halfWidth), radius: cornerRadius)
            guard length > headLength else { return head }
            // The part of the curve from the start to `tuck` short of the tip.
            let t = quadParameter(start, bend, end, distanceFromEnd: tuck)
            let control = CGPoint(x: start.x + (bend.x - start.x) * t, y: start.y + (bend.y - start.y) * t)
            let shaftEnd = quadPoint(start, bend, end, t)
            let shaft = CGMutablePath()
            shaft.move(to: start); shaft.addQuadCurve(to: shaftEnd, control: control)
            return shaft.copy(strokingWithWidth: width, lineCap: cap, lineJoin: .round, miterLimit: 10).union(head)
        }

        let angle = atan2(end.y - start.y, end.x - start.x)
        let along = { (from: CGPoint, distance: CGFloat) in
            CGPoint(x: from.x + cos(angle) * distance, y: from.y + sin(angle) * distance)
        }
        var heads = roundedPolygon(headPoints(at: end, angle: angle, length: headLength, halfWidth: halfWidth), radius: cornerRadius)
        var shaftStart = start
        if style == .double {
            let tail = roundedPolygon(headPoints(at: start, angle: angle + .pi, length: headLength, halfWidth: halfWidth), radius: cornerRadius)
            heads = heads.union(tail)
            shaftStart = along(start, tuck)
            guard length > headLength * 2 else { return heads }
        }
        guard length > headLength else { return heads }
        let shaft = CGMutablePath()
        shaft.move(to: shaftStart); shaft.addLine(to: along(end, -tuck))
        return shaft.copy(strokingWithWidth: width, lineCap: style == .double ? .butt : cap, lineJoin: .round, miterLimit: 10).union(heads)
    }

    /// The tip and the two base corners of a head pointing along `angle`.
    private static func headPoints(at tip: CGPoint, angle: CGFloat, length: CGFloat, halfWidth: CGFloat) -> [CGPoint] {
        let base = CGPoint(x: tip.x - cos(angle) * length, y: tip.y - sin(angle) * length)
        return [tip, CGPoint(x: base.x - sin(angle) * halfWidth, y: base.y + cos(angle) * halfWidth),
                CGPoint(x: base.x + sin(angle) * halfWidth, y: base.y - cos(angle) * halfWidth)]
    }

    /// A triangle with corners rounded by `radius`, keeping its outer size: the triangle shrinks
    /// toward its incenter, then a round stroke grows it back.
    private static func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> CGPath {
        let polygon = { (points: [CGPoint]) -> CGPath in
            let path = CGMutablePath(); path.addLines(between: points); path.closeSubpath(); return path
        }
        let (a, b, c) = (points[0], points[1], points[2])
        let sideA = hypot(b.x - c.x, b.y - c.y), sideB = hypot(a.x - c.x, a.y - c.y), sideC = hypot(a.x - b.x, a.y - b.y)
        let perimeter = sideA + sideB + sideC
        let area = abs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2
        let inradius = 2 * area / perimeter
        let radius = min(radius, inradius * 0.8)
        guard radius > 0 else { return polygon(points) }
        let center = CGPoint(x: (sideA * a.x + sideB * b.x + sideC * c.x) / perimeter,
                             y: (sideA * a.y + sideB * b.y + sideC * c.y) / perimeter)
        let scale = (inradius - radius) / inradius
        let inner = polygon(points.map { CGPoint(x: center.x + ($0.x - center.x) * scale, y: center.y + ($0.y - center.y) * scale) })
        return inner.copy(strokingWithWidth: radius * 2, lineCap: .round, lineJoin: .round, miterLimit: 10).union(inner)
    }

    private static func quadPoint(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * control.x + t * t * b.x, y: u * u * a.y + 2 * u * t * control.y + t * t * b.y)
    }

    /// The curve parameter whose point lies `distance` from the end, by bisection.
    private static func quadParameter(_ a: CGPoint, _ control: CGPoint, _ b: CGPoint, distanceFromEnd distance: CGFloat) -> CGFloat {
        var low: CGFloat = 0, high: CGFloat = 1
        for _ in 0..<20 {
            let t = (low + high) / 2, p = quadPoint(a, control, b, t)
            if hypot(b.x - p.x, b.y - p.y) > distance { low = t } else { high = t }
        }
        return low
    }

    /// The radius shrinks to fit small rects; zero gives hard corners.
    static func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let radius = min(radius, rect.width / 2, rect.height / 2)
        return CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The dimmed area: everything in `bounds` outside the spotlight.
    static func dimming(_ bounds: CGRect, spotlight: CGPath) -> CGPath {
        CGPath(rect: bounds, transform: nil).subtracting(spotlight)
    }
}
