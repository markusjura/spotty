import XCTest
@testable import Spotty

final class MarkTests: XCTestCase {
    private func mark(_ tool: DrawingTool, _ points: [CGPoint], shift: Bool = false) -> Mark {
        var mark = Mark(tool: tool, at: points[0], color: .annotationRed, width: 4)
        points.dropFirst().forEach { mark.add($0) }
        mark.isConstrained = shift
        mark.finish()
        return mark
    }

    func testANearlyStraightHighlighterStrokeSnapsToALine() {
        let wobbly = (0...20).map { CGPoint(x: Double($0) * 10, y: 100 + ($0.isMultiple(of: 2) ? 2 : -2)) }
        XCTAssertEqual(mark(.highlighter, wobbly).points, [wobbly.first!, wobbly.last!])

        let curve = (0...20).map { CGPoint(x: Double($0) * 10, y: 100 + Double($0 * $0)) }
        XCTAssertEqual(mark(.highlighter, curve).points.count, curve.count, "Curves stay freehand")
        XCTAssertEqual(mark(.pen, wobbly).points.count, wobbly.count, "Only the highlighter straightens")
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
        XCTAssertFalse(mark(.ellipse, [.zero, CGPoint(x: 40, y: 1)]).isEmpty)
    }

    func testSpotlightsCutHolesInTheDimming() {
        let bounds = CGRect(x: 0, y: 0, width: 200, height: 200)
        let dimming = MarkGeometry.dimming(bounds, spotlights: [
            MarkGeometry.spotlight(CGRect(x: 20, y: 20, width: 60, height: 60)),
            MarkGeometry.spotlight(CGRect(x: 50, y: 50, width: 60, height: 60)),
        ])
        XCTAssertFalse(dimming.contains(CGPoint(x: 50, y: 50)))
        XCTAssertFalse(dimming.contains(CGPoint(x: 70, y: 70)), "Overlapping spotlights stay bright")
        XCTAssertTrue(dimming.contains(CGPoint(x: 150, y: 150)))
    }
}
