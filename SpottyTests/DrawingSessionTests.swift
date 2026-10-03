import XCTest
@testable import Spotty

final class DrawingSessionTests: XCTestCase {
    private let quick = DrawingSession.tapInterval / 2
    private let long = DrawingSession.tapInterval * 2

    func testHoldingDrawsUntilRelease() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.drawArrow), at: 0, startTool: .pen)
        XCTAssertEqual(session.mode, .holding)
        XCTAssertEqual(session.tool, .arrow)
        session.released(ShortcutSlot(.drawArrow), at: long)
        XCTAssertEqual(session.mode, .off)
    }

    func testTapTogglesOnAndASecondTapTogglesOff() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .highlighter)
        session.released(ShortcutSlot(.draw), at: quick)
        XCTAssertEqual(session.mode, .latched)
        XCTAssertEqual(session.tool, .highlighter, "Draw starts with the start tool")

        session.pressed(ShortcutSlot(.draw), at: 1, startTool: .highlighter)
        session.released(ShortcutSlot(.draw), at: 1 + quick)
        XCTAssertEqual(session.mode, .off)
    }

    func testToggleDrawingTurnsDrawingOnAndOffWithoutHolding() {
        var session = DrawingSession(tool: .pen)
        session.toggleDrawing(startTool: .highlighter)
        XCTAssertEqual(session.mode, .latched)
        XCTAssertEqual(session.tool, .highlighter)
        session.toggleDrawing(startTool: .highlighter)
        XCTAssertEqual(session.mode, .off)
    }

    /// Hold ⌃⇧ and press D: drawing stays on after letting go of ⌃⇧.
    func testToggleDrawingWhileHoldingKeepsDrawingOn() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.drawArrow), at: 0, startTool: .pen)
        session.toggleDrawing(startTool: .pen)
        session.released(ShortcutSlot(.drawArrow), at: long)
        XCTAssertEqual(session.mode, .latched)
        XCTAssertEqual(session.tool, .arrow)
    }

    func testAQuickPressThatDrewIsAHold() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .pen)
        session.didDraw()
        session.released(ShortcutSlot(.draw), at: quick)
        XCTAssertEqual(session.mode, .off)
    }

    /// Hold ⌃⇧, press A for the arrow, draw, let go of everything.
    func testASecondShortcutWhileHoldingSwitchesToolsAndTheFirstOneEndsIt() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .pen)
        session.pressed(ShortcutSlot(.drawArrow), at: 0.5, startTool: .pen)
        XCTAssertEqual(session.tool, .arrow)
        session.released(ShortcutSlot(.drawArrow), at: 0.6)
        XCTAssertEqual(session.mode, .holding, "Only the first shortcut of a gesture ends it")
        session.didDraw()
        session.released(ShortcutSlot(.draw), at: 2)
        XCTAssertEqual(session.mode, .off)
    }

    /// A quick ⌃⇧A tap with ⌃⇧ itself bound to Draw toggles the arrow on.
    func testAQuickChordTogglesOnWithTheChosenTool() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .pen)
        session.pressed(ShortcutSlot(.drawArrow), at: 0.05, startTool: .pen)
        session.released(ShortcutSlot(.drawArrow), at: 0.1)
        session.released(ShortcutSlot(.draw), at: quick)
        XCTAssertEqual(session.mode, .latched)
        XCTAssertEqual(session.tool, .arrow)
    }

    func testWhileToggledOnAnotherToolSwitchesAndTheSameToolTurnsOff() {
        var session = DrawingSession(tool: .pen)
        session.toggle(.rectangle)
        XCTAssertEqual(session.mode, .latched)

        // ⌃⇧ then A, quickly: switches instead of turning off.
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .pen)
        session.pressed(ShortcutSlot(.drawArrow), at: 0.05, startTool: .pen)
        session.released(ShortcutSlot(.drawArrow), at: 0.1)
        session.released(ShortcutSlot(.draw), at: quick)
        XCTAssertEqual(session.mode, .latched)
        XCTAssertEqual(session.tool, .arrow)

        session.pressed(ShortcutSlot(.drawArrow), at: 1, startTool: .pen)
        session.released(ShortcutSlot(.drawArrow), at: 1 + quick)
        XCTAssertEqual(session.mode, .off)
    }

    func testHoldingWhileToggledOnKeepsDrawingOn() {
        var session = DrawingSession(tool: .pen)
        session.toggle(.pen)
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .pen)
        session.released(ShortcutSlot(.draw), at: long)
        XCTAssertEqual(session.mode, .latched)
    }

    func testAnInterruptedChordEndsHeldDrawingWithoutToggling() {
        var session = DrawingSession(tool: .pen)
        session.pressed(ShortcutSlot(.draw), at: 0, startTool: .pen)
        session.interrupted(ShortcutSlot(.draw))
        XCTAssertEqual(session.mode, .off)
        session.released(ShortcutSlot(.draw), at: quick)
        XCTAssertEqual(session.mode, .off)
    }

    func testRepeatedPressesAndStrayReleasesAreIgnored() {
        var session = DrawingSession(tool: .pen)
        session.released(ShortcutSlot(.draw), at: 0)
        XCTAssertEqual(session.mode, .off)
        session.pressed(ShortcutSlot(.drawPen), at: 0, startTool: .pen)
        session.pressed(ShortcutSlot(.drawPen), at: 0.2, startTool: .pen)
        session.released(ShortcutSlot(.drawPen), at: 0.25)
        XCTAssertEqual(session.mode, .latched, "A repeated press does not restart the tap timer")
    }
}
