import XCTest
@testable import Spotty

@MainActor
final class DrawingPreferencesTests: XCTestCase {
    func testToolsFollowTheDefaultStyleUnlessOverridden() {
        var drawing = DrawingPreferences()
        drawing.lineWidth = 6
        drawing.cornerRadius = 8
        drawing[overrides: .arrow].width = 10
        drawing[overrides: .spotlight].cornerRadius = 20

        XCTAssertEqual(drawing.style(for: .pen), ToolStyle(color: .annotationRed, width: 6, cornerRadius: 8))
        XCTAssertEqual(drawing.style(for: .arrow).width, 10)
        XCTAssertEqual(drawing.style(for: .spotlight).cornerRadius, 20)
        XCTAssertEqual(drawing.style(for: .highlighter), ToolStyle(color: .highlighterYellow, width: 16, cornerRadius: 0),
                       "The highlighter keeps its own style")

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

    func testOverridesPersistAndEarlierSettingsStillLoad() throws {
        let suite = "DrawingPreferencesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }

        // Before per-tool styles, widths and radii were presets without overrides.
        defaults.set(Data(#"{"lineWidth": 6, "cornerRadius": 8}"#.utf8), forKey: "preferences.v1.drawing")
        let preferences = AppPreferences(defaults: defaults)
        XCTAssertEqual(preferences.drawing.style(for: .rectangle).width, 6)
        XCTAssertEqual(preferences.drawing.cornerRadius, 8)

        preferences.drawing[overrides: .rectangle].cornerRadius = 12
        preferences.drawing[overrides: .pen].width = 99
        XCTAssertNil(preferences.drawing.overrides[.pen], "Out of range values are rejected")

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.drawing.style(for: .rectangle).cornerRadius, 12)
        XCTAssertEqual(reloaded.drawing.style(for: .spotlight).cornerRadius, 8)
    }
}
