import XCTest
@testable import KeyboardCore

final class ModeWheelTests: XCTestCase {
    func testSlotsRunLeftToRight() {
        XCTAssertEqual(ModeWheel.slots, [.japanese, .english, .dictionary, .kana, .nextKeyboard])
    }

    func testShortMovementIsATap() {
        XCTAssertNil(ModeWheel.slot(dx: 0, dy: 0))
        XCTAssertNil(ModeWheel.slot(dx: 10, dy: -15))
    }

    func testDirections() {
        XCTAssertEqual(ModeWheel.slot(dx: -60, dy: 0), .japanese)
        XCTAssertEqual(ModeWheel.slot(dx: -40, dy: -40), .english)
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: -60), .dictionary)
        XCTAssertEqual(ModeWheel.slot(dx: 40, dy: -40), .kana)
        XCTAssertEqual(ModeWheel.slot(dx: 60, dy: 0), .nextKeyboard)
    }

    func testDraggingBelowTheKeyPicksTheNearestEnd() {
        XCTAssertEqual(ModeWheel.slot(dx: -30, dy: 30), .japanese)
        XCTAssertEqual(ModeWheel.slot(dx: 30, dy: 30), .nextKeyboard)
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: 40), .nextKeyboard)
    }

    /// The wheel draws each slot at its angle; dragging that way must pick it.
    func testEachSlotsDrawnDirectionPicksIt() {
        for slot in ModeWheel.slots {
            let angle = ModeWheel.angle(of: slot)
            XCTAssertEqual(ModeWheel.slot(dx: cos(angle) * 50, dy: -sin(angle) * 50), slot)
        }
    }

    /// The wheel doesn't depend on the current mode, so a direction always means the same slot.
    func testSlotsMapToModes() {
        for mode in InputMode.allCases {
            XCTAssertEqual(ModeWheelSlot(mode).inputMode, mode)
        }
        XCTAssertNil(ModeWheelSlot.kana.inputMode)
        XCTAssertNil(ModeWheelSlot.nextKeyboard.inputMode)
    }
}
