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
        XCTAssertNil(registry.shortcut(for: ShortcutSlot(.draw, 1)), "Second shortcuts start unassigned")
        XCTAssertEqual(CommandID.allCases.filter { registry.shortcut(for: $0) == nil }, [], "Every default is valid and unique")
    }

    func testRulesDependOnWhatTheShortcutDoes() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertNil(registry.problem(assigning: .mouse(3), to: ShortcutSlot(.draw)))
        XCTAssertNil(registry.problem(assigning: .mouse(4, [.option]), to: ShortcutSlot(.undo)))
        XCTAssertNil(registry.problem(assigning: Shortcut(kVK_F18), to: ShortcutSlot(.drawPen)), "Function keys stand alone")
        XCTAssertNil(registry.problem(assigning: .modifiers([.option, .command]), to: ShortcutSlot(.drawRectangle)))

        XCTAssertEqual(registry.problem(assigning: .modifiers([.shift]), to: ShortcutSlot(.draw)), .unsupported, "Shift alone would fire while typing")
        XCTAssertEqual(registry.problem(assigning: .mouse(0), to: ShortcutSlot(.draw)), .unsupported, "Left click draws")
        XCTAssertEqual(registry.problem(assigning: .modifiers([.option, .command]), to: ShortcutSlot(.clear)), .modifiersOnlyForDrawing)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_ANSI_D, [.shift]), to: ShortcutSlot(.draw)), .needsCommandOrControl)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_ANSI_Q, .command), to: ShortcutSlot(.draw)), .reserved)
        XCTAssertEqual(registry.problem(assigning: .mouse(3), to: ShortcutSlot(.pickPen)), .keysOnly)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_Escape), to: ShortcutSlot(.pickPen)), .reservedForDrawing)
        XCTAssertEqual(registry.problem(assigning: Shortcut(kVK_ANSI_A, [.control, .shift]), to: ShortcutSlot(.drawPen)), .conflict(.drawArrow))
        XCTAssertEqual(registry.problem(assigning: .modifiers([.control, .shift]), to: ShortcutSlot(.draw, 1)), .conflict(.draw))
    }

    func testCustomBindingsPersistAsOverridesAndRestoreCleanly() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertNil(registry.assign(.mouse(3), to: ShortcutSlot(.draw)))
        XCTAssertNil(registry.assign(nil, to: ShortcutSlot(.drawSpotlight)))

        let reloaded = CommandRegistry(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: .draw), .mouse(3))
        XCTAssertNil(reloaded.shortcut(for: .drawSpotlight), "A cleared binding stays cleared")

        reloaded.restoreDefaults(in: .drawing)
        XCTAssertEqual(CommandRegistry(defaults: defaults).shortcut(for: .draw), .modifiers([.control, .shift]))
    }

    /// Draw keeps its key chord and gains a mouse button; menus show the key.
    func testASecondShortcutTriggersTheSameCommandAndPersists() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertNil(registry.assign(.mouse(5), to: ShortcutSlot(.draw, 1)))
        XCTAssertEqual(registry.activeGlobalBindings[ShortcutSlot(.draw)], .modifiers([.control, .shift]))
        XCTAssertEqual(registry.activeGlobalBindings[ShortcutSlot(.draw, 1)], .mouse(5))
        XCTAssertEqual(registry.shortcut(for: .drawArrow), Shortcut(kVK_ANSI_A, [.control, .shift]))

        let reloaded = CommandRegistry(defaults: defaults)
        XCTAssertEqual(reloaded.shortcut(for: ShortcutSlot(.draw, 1)), .mouse(5))
        reloaded.restoreDefaults(in: .drawing)
        XCTAssertNil(CommandRegistry(defaults: defaults).shortcut(for: ShortcutSlot(.draw, 1)))
    }

    /// Builds 3 and 4 stored Draw's mouse button as a separate drawAlternate command.
    func testTheOldAlternateDrawCommandMovesIntoDrawsSecondShortcut() throws {
        let stored: [String: Shortcut?] = ["draw": .modifiers([.control, .option, .command]), "drawAlternate": .mouse(5)]
        defaults.set(try JSONEncoder().encode(stored), forKey: CommandRegistry.storageKey)
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertEqual(registry.shortcut(for: ShortcutSlot(.draw)), .modifiers([.control, .option, .command]))
        XCTAssertEqual(registry.shortcut(for: ShortcutSlot(.draw, 1)), .mouse(5))
    }

    func testRecordingSuspendsGlobalBindings() {
        let registry = CommandRegistry(defaults: defaults)
        XCTAssertFalse(registry.activeGlobalBindings.isEmpty)
        XCTAssertNil(registry.activeGlobalBindings[ShortcutSlot(.pickPen)], "Overlay keys are not global")
        XCTAssertEqual(CommandID.pickPen.slots.count, 1, "Overlay keys take one shortcut")
        registry.recordingCommand = .draw
        XCTAssertTrue(registry.activeGlobalBindings.isEmpty)
    }
}
