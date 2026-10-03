import XCTest
@testable import Spotty

final class MarkTests: XCTestCase {
    private func mark(_ tool: DrawingTool, _ points: [CGPoint], shift: Bool = false,
                      style: ToolStyle = ToolStyle(color: .annotationRed, width: 4)) -> Mark {
        var mark = Mark(tool: tool, at: points[0], style: style)
        points.dropFirst().forEach { mark.add($0) }
        mark.isConstrained = shift
        mark.finish()
        return mark
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
