import XCTest
@testable import Spotty

@MainActor
final class DrawingPreferencesTests: XCTestCase {
    func testToolsCombineTheDefaultStyleWithTheirOwnOptions() {
        var drawing = DrawingPreferences()
        drawing.lineWidth = 6
        drawing[overrides: .arrow].width = 10
        drawing.arrowStyle = .curved
        drawing.rectangleStyle = .tinted
        drawing.rectangleCornerRadius = 8

        XCTAssertEqual(drawing.style(for: .pen), ToolStyle(color: .annotationRed, width: 6))
        XCTAssertEqual(drawing.style(for: .arrow), ToolStyle(color: .annotationRed, width: 10, cornerRadius: 2, arrow: .curved))
        XCTAssertEqual(drawing.style(for: .rectangle), ToolStyle(color: .annotationRed, width: 6, cornerRadius: 8, isTinted: true))
        XCTAssertEqual(drawing.style(for: .highlighter), ToolStyle(color: .highlighterYellow, width: 16, hasFlatTips: true),
                       "The highlighter keeps its own style and doesn't straighten by default")

        drawing[overrides: .arrow].width = nil
        XCTAssertEqual(drawing.style(for: .arrow).width, 6)
        XCTAssertNil(drawing.overrides[.arrow], "Clearing the last override removes the entry")
    }

    func testToolbarColorChangesTheToolsOwnColorOrTheDefault() {
        var drawing = DrawingPreferences()
        drawing[overrides: .arrow].color = .annotationBlue

        drawing.setColor(.black, for: .pen)
        XCTAssertEqual(drawing.style(for: .rectangle).color, .black, "Following tools share the default color")
        XCTAssertEqual(drawing.style(for: .arrow).color, .annotationBlue)

        drawing.setColor(.white, for: .arrow)
        XCTAssertEqual(drawing.style(for: .arrow).color, .white)
        XCTAssertEqual(drawing.color, .black)

        drawing.setColor(.annotationRed, for: .highlighter)
        XCTAssertEqual(drawing.highlighterColor, .annotationRed)
    }

    func testBuild11CornerRadiiMoveToRectanglesAndSpotlights() throws {
        let suite = "DrawingPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // Build 11 kept one corner radius in the default style, which tools could override.
        defaults.set(Data(#"{"lineWidth": 6, "cornerRadius": 8, "overrides": {"spotlight": {"cornerRadius": 20}}}"#.utf8),
                     forKey: "preferences.v1.drawing")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.drawing.style(for: .rectangle).cornerRadius, 8)
        XCTAssertEqual(preferences.drawing.style(for: .spotlight).cornerRadius, 20)
        XCTAssertEqual(preferences.drawing.lineWidth, 6)
        XCTAssertNil(preferences.drawing.overrides[.spotlight], "Leftover radius overrides are dropped")

        preferences.drawing.rectangleCornerRadius = 12
        preferences.drawing[overrides: .pen].width = 99
        XCTAssertNil(preferences.drawing.overrides[.pen], "Out of range values are rejected")

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.drawing.rectangleCornerRadius, 12, "Saved radii are not migrated again")
        XCTAssertEqual(reloaded.drawing.spotlightCornerRadius, 20)
    }
}
