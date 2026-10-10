import XCTest
@testable import Spotty

final class MarkTests: XCTestCase {
    /// A mark dragged through `points`, one every `interval` seconds.
    private func mark(_ tool: DrawingTool, _ points: [CGPoint], shift: Bool = false,
                      style: ToolStyle = ToolStyle(color: .annotationRed, width: 4), interval: TimeInterval = 0.01) -> Mark {
        var mark = Mark(tool: tool, at: points[0], style: style, time: 0)
        for (index, point) in points.enumerated().dropFirst() { mark.add(point, at: Double(index) * interval) }
        mark.isConstrained = shift
        mark.finish()
        return mark
    }

    func testDashLengthZeroDrawsDots() {
        var dashed = ToolStyle(color: .annotationRed, width: 4, stroke: .dashed)
        XCTAssertEqual(mark(.pen, [.zero, CGPoint(x: 100, y: 0)], style: dashed).paint.dash, [8, 10], "The dash at the default length")
        dashed.strokeOptions.dashLength = 0
        XCTAssertEqual(mark(.pen, [.zero, CGPoint(x: 100, y: 0)], style: dashed).paint.dash, [0, 8], "Round caps turn zero-length dashes into dots")
        XCTAssertEqual(mark(.rectangle, [.zero, CGPoint(x: 100, y: 50)], style: dashed).paint.dash, [0, 8])
        XCTAssertEqual(mark(.pen, [.zero, CGPoint(x: 100, y: 0)]).paint.dash, [], "Solid strokes have no dashes")
    }

    func testInkThinsFastStrokesAndTapersTheEnds() {
        var ink = ToolStyle(color: .annotationRed, width: 10, stroke: .ink)
        ink.strokeOptions.thinning = 80
        ink.strokeOptions.taper = 0
        let line = (0...100).map { CGPoint(x: Double($0) * 4, y: 0) }
        let slow = mark(.pen, line, style: ink, interval: 0.02).paint
        let fast = mark(.pen, line, style: ink, interval: 0.001).paint
        XCTAssertFalse(slow.stroke); XCTAssertEqual(slow.fill, 1, "Ink is a filled outline")
        XCTAssertTrue(slow.path.contains(CGPoint(x: 200, y: 4.5)), "A slow stroke keeps nearly its full width")
        XCTAssertFalse(fast.path.contains(CGPoint(x: 200, y: 3)), "A fast stroke thins to about a fifth")
        XCTAssertTrue(fast.path.contains(CGPoint(x: 200, y: 0.5)))

        ink.strokeOptions.taper = 2
        let tapered = mark(.pen, line, style: ink, interval: 0.02).paint
        XCTAssertFalse(tapered.path.contains(CGPoint(x: 2, y: 3)), "The ends taper over two line widths")
        XCTAssertTrue(tapered.path.contains(CGPoint(x: 200, y: 4.5)))
    }

    func testCalligraphyIsWideAcrossTheNibAndThinAlongIt() {
        var calligraphy = ToolStyle(color: .annotationRed, width: 10, stroke: .calligraphy)
        calligraphy.strokeOptions.nibAngle = 90
        calligraphy.strokeOptions.nibEdge = 20
        let across = mark(.pen, (0...50).map { CGPoint(x: Double($0) * 4, y: 0) }, style: calligraphy).paint
        XCTAssertTrue(across.path.contains(CGPoint(x: 100, y: 4.5)), "A vertical nib moving sideways paints the full width")
        let along = mark(.pen, (0...50).map { CGPoint(x: 0, y: Double($0) * 4) }, style: calligraphy).paint
        XCTAssertTrue(along.path.contains(CGPoint(x: 0.9, y: 100)), "Moving along the nib leaves its edge")
        XCTAssertFalse(along.path.contains(CGPoint(x: 2, y: 100)))
    }

    func testHighlighterStrokesStraightenOnlyWhenEnabled() {
        let straightening = ToolStyle(color: .highlighterYellow, width: 16, straightenTolerance: 6)
        let wobbly = (0...20).map { CGPoint(x: Double($0) * 10, y: 100 + ($0.isMultiple(of: 2) ? 2 : -2)) }
        XCTAssertEqual(mark(.highlighter, wobbly, style: straightening).points, [wobbly.first!, wobbly.last!])
        XCTAssertEqual(mark(.highlighter, wobbly).points.count, wobbly.count, "Off by default")

        let wavy = (0...20).map { CGPoint(x: Double($0) * 10, y: 100 + ($0.isMultiple(of: 2) ? 8 : -8)) }
        XCTAssertEqual(mark(.highlighter, wavy, style: straightening).points.count, wavy.count, "Beyond the tolerance stays freehand")
        XCTAssertEqual(mark(.pen, wobbly, style: straightening).points.count, wobbly.count, "Only the highlighter straightens")
    }

    func testCurvedArrowsBendTowardTheDrag() {
        let curved = ToolStyle(color: .annotationRed, width: 4, arrow: .curved)
        let start = CGPoint.zero, end = CGPoint(x: 100, y: 0)
        let above = mark(.arrow, [start, CGPoint(x: 50, y: 40), end], style: curved).paint.path
        XCTAssertTrue(above.contains(CGPoint(x: 50, y: 40)), "The curve peaks where the drag went")
        XCTAssertFalse(above.contains(CGPoint(x: 50, y: 0)))

        let below = mark(.arrow, [start, CGPoint(x: 50, y: -30), end], style: curved).paint.path
        XCTAssertTrue(below.contains(CGPoint(x: 50, y: -30)))

        let straight = mark(.arrow, [start, CGPoint(x: 50, y: 2), end], style: curved).paint.path
        XCTAssertTrue(straight.contains(CGPoint(x: 50, y: 10)), "A nearly straight drag still bends, left of its direction")
    }

    func testArrowCornerRadiusRoundsTheHeadAndTail() {
        func arrow(radius: CGFloat) -> CGPath {
            mark(.arrow, [.zero, CGPoint(x: 100, y: 0)], style: ToolStyle(color: .annotationRed, width: 10, cornerRadius: radius)).paint.path
        }
        XCTAssertTrue(arrow(radius: 0).contains(CGPoint(x: 98, y: 0)), "Sharp tip")
        XCTAssertFalse(arrow(radius: 0).contains(CGPoint(x: -2, y: 0)), "Square tail")
        XCTAssertFalse(arrow(radius: 6).contains(CGPoint(x: 98, y: 0)), "Rounded tip")
        XCTAssertTrue(arrow(radius: 6).contains(CGPoint(x: -2, y: 0)), "Round tail")
    }

    func testShiftSnapsArrowsTo45DegreesAndShapesToSquares() {
        let arrow = mark(.arrow, [.zero, CGPoint(x: 100, y: 10)], shift: true)
        XCTAssertEqual(arrow.end.y, 0, accuracy: 0.001)
        XCTAssertEqual(arrow.end.x, hypot(100, 10), accuracy: 0.001)

        let square = mark(.rectangle, [CGPoint(x: 50, y: 50), CGPoint(x: 10, y: 80)], shift: true)
        XCTAssertEqual(square.end, CGPoint(x: 10, y: 90))
    }

    func testClicksWithoutADragLeaveNothing() {
        XCTAssertTrue(mark(.rectangle, [.zero, CGPoint(x: 2, y: 2)]).isEmpty)
        XCTAssertTrue(mark(.arrow, [.zero, CGPoint(x: 3, y: 0)]).isEmpty)
        XCTAssertTrue(mark(.pen, [.zero, CGPoint(x: 0.5, y: 0)]).isEmpty)
        XCTAssertFalse(mark(.rectangle, [.zero, CGPoint(x: 40, y: 1)]).isEmpty)
    }

    func testCornerRadiusRoundsRectanglesAndSpotlights() {
        func shape(_ tool: DrawingTool, to end: CGPoint, radius: CGFloat) -> CGPath {
            var mark = Mark(tool: tool, at: .zero, style: ToolStyle(color: .annotationRed, width: 4, cornerRadius: radius))
            mark.add(end)
            return mark.paint.path
        }
        let corner = CGPoint(x: 1, y: 1), end = CGPoint(x: 100, y: 100)
        for tool in [DrawingTool.rectangle, .spotlight] {
            XCTAssertTrue(shape(tool, to: end, radius: 0).contains(corner), "\(tool) corners are hard at zero")
            XCTAssertFalse(shape(tool, to: end, radius: 16).contains(corner), "\(tool) corners follow the radius")
        }
        XCTAssertTrue(shape(.rectangle, to: CGPoint(x: 10, y: 30), radius: 24).contains(CGPoint(x: 5, y: 15)),
                      "The radius shrinks to fit small rects")
    }

    func testSpotlightsCutAHoleInTheDimming() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let dimming = MarkGeometry.dimming(bounds, spotlight: MarkGeometry.roundedRect(CGRect(x: 20, y: 20, width: 60, height: 60), radius: 12))
        XCTAssertFalse(dimming.contains(CGPoint(x: 50, y: 50)))
        XCTAssertTrue(dimming.contains(CGPoint(x: 150, y: 150)))
    }
}
