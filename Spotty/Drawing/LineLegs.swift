import CoreGraphics

/// The legs of a line tool stroke, built point by point while it is drawn. The current leg follows
/// the pointer while the stroke stays within `tolerance` of a straight path. When the stroke turns
/// away, the leg ends where it was last drawn and the next leg starts there, so a finished leg never
/// moves.
struct LineLegs: Equatable, Sendable {
    let angle: StraightenAngle
    let tolerance: CGFloat
    /// The start, then the end of each finished leg.
    private(set) var corners: [CGPoint]
    /// Where the current leg ends.
    private(set) var end: CGPoint
    /// Where the pointer was when the current leg began.
    private var origin: CGPoint
    /// Where the pointer was last.
    private var last: CGPoint
    /// The pointer's path along the current leg, from `tolerance` past `origin`. Nearer points may
    /// still be rounding the corner or steadying the start, so they don't count.
    private var path: [CGPoint] = []

    init(start: CGPoint, angle: StraightenAngle, tolerance: CGFloat) {
        self.angle = angle
        self.tolerance = tolerance
        corners = [start]
        end = start
        origin = start
        last = start
    }

    /// The corners and the current end, in drawing order.
    var points: [CGPoint] { corners + [end] }

    mutating func add(_ point: CGPoint) {
        let corner = corners[corners.count - 1]
        // A leg shorter than the tolerance may still change direction, so it never turns a corner.
        if !isStraight(to: point), hypot(end.x - corner.x, end.y - corner.y) >= tolerance {
            // The leg ends where it was drawn for the last point, so the pointer turned there.
            corners.append(end)
            origin = last
            path = []
        }
        if hypot(point.x - origin.x, point.y - origin.y) >= tolerance { path.append(point) }
        last = point
        let start = corners[corners.count - 1]
        end = angle == .axes ? MarkGeometry.leveled(from: start, to: point).end : point
    }

    /// Whether the leg's path stays within the tolerance of the straight line from `origin` to
    /// `point`. Axis legs check the pointer's own path too, so a line drifting off level only turns
    /// where it bends.
    private func isStraight(to point: CGPoint) -> Bool {
        let dx = point.x - origin.x, dy = point.y - origin.y, length = hypot(dx, dy)
        // Too near where the leg began to say which way the stroke heads.
        guard length >= tolerance else { return true }
        return path.allSatisfy { abs(($0.x - origin.x) * dy - ($0.y - origin.y) * dx) / length <= tolerance }
    }
}
