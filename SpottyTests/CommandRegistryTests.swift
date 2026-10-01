import Carbon.HIToolbox
import XCTest
@testable import Spotty

@MainActor
final class CommandRegistryTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "CommandRegistryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testDefaultsHoldControlShiftAndAddALetterPerTool() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertEqual(registry.shortcut(for: .draw), .modifiers([.control, .shift]))
        XCTAssertEqual(registry.shortcut(for: .drawArrow), Shortcut(kVK_ANSI_A, [.control, .shift]))
        XCTAssertEqual(registry.shortcut(for: .pickArrow), Shortcut(kVK_ANSI_A))
        XCTAssertTrue(registry.needsEventTap)
        XCTAssertEqual(CommandID.allCases.filter { registry.shortcut(for: $0) == nil }, [], "Every default is valid and unique")
    }

    func testRulesDependOnWhatTheShortcutDoes() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertNil(registry.problem(assigning: .mouse(3), to: .draw))
        XCTAssertNil(registry.problem(assigning: .mouse(4, [.option]), to: .undo))
        XCTAssertNil(registry.problem(assigning: Shortcut(kVK_F18), to: .drawPen), "Function keys stand alone")
        XCTAssertNil(registry.problem(assigning: .modifiers([.option, .command]), to: .drawRectangle))

        XCTAssertEqual(registry.problem(assigning: .modifiers([.shift]), to: .draw), .unsupported, "Shift alone would fire while typing")
        XCTAssertEqual(registry.problem(assigning: .mouse(0), to: .draw), .unsupported, "Left click draws")
        XCTAssertEqual(registry.problem(assigning: .modifiers([.option, .command]), to: .clear), .modifiersOnlyForDrawing)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_ANSI_D, [.shift]), to: .draw), .needsCommandOrControl)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_ANSI_Q, .command), to: .draw), .reserved)
        XCTAssertEqual(registry.problem(assigning: .mouse(3), to: .pickPen), .keysOnly)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_Escape), to: .pickPen), .reservedForDrawing)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_ANSI_A, [.control, .shift]), to: .drawPen), .conflict(.drawArrow))
    }

    func testCustomBindingsPersistAsOverridesAndRestoreCleanly() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertNil(registry.assign(.mouse(3), to: .draw))
        XCTAssertNil(registry.assign(nil, to: .drawSpotlight))

        let reloaded = CommandRegistry(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .draw), .mouse(3))
        XCTAssertNil(reloaded.shortcut(for: .drawSpotlight), "A cleared binding stays cleared")

        reloaded.restoreDefaults(in: .drawing)
        XCTAssertEqual(CommandRegistry(defaults: defaults).shortcut(for: .draw), .modifiers([.control, .shift]))
    }

    func testRecordingSuspendsGlobalBindings() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertFalse(registry.activeGlobalBindings.isEmpty)
        XCTAssertNil(registry.activeGlobalBindings[.pickPen], "Overlay keys are not global")
        registry.recordingCommand = .draw
        XCTAssertTrue(registry.activeGlobalBindings.isEmpty)
    }
}
