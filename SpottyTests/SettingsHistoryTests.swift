import XCTest
@testable import Spotty

final class SettingsHistoryTests: XCTestCase {
    func testBackAndForwardRetraceVisitsAndANewVisitClearsForward() {
        var history = SettingsHistory()
        XCTAssertNil(history.back(from: .general))

        history.visit(.drawing, from: .general)
        history.visit(.drawing, from: .drawing)
        history.visit(.shortcuts, from: .drawing)
        XCTAssertEqual(history.back(from: .shortcuts), .drawing)
        XCTAssertEqual(history.back(from: .drawing), .general)
        XCTAssertFalse(history.canGoBack)
        XCTAssertEqual(history.forward(from: .general), .drawing)

        history.visit(.permissions, from: .drawing)
        XCTAssertFalse(history.canGoForward)
        XCTAssertEqual(history.back(from: .permissions), .drawing)
    }
}
