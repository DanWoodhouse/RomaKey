import XCTest
@testable import KeyboardCore

final class ModeWheelTests: XCTestCase {
    func testSlots() {
        XCTAssertEqual(ModeWheel.slots, [.japanese, .english, .dictionary, .kana])
    }

    func testShortMovementIsATap() {
        XCTAssertNil(ModeWheel.slot(dx: 0, dy: 0))
        XCTAssertNil(ModeWheel.slot(dx: 10, dy: -15))
        XCTAssertNil(ModeWheel.slot(dx: 20, dy: -20))
        XCTAssertNil(ModeWheel.slot(dx: 25, dy: -5))
        XCTAssertNil(ModeWheel.slot(dx: 5, dy: 15))
    }

    func testDirections() {
        XCTAssertEqual(ModeWheel.slot(dx: -60, dy: 0), .japanese)
        XCTAssertEqual(ModeWheel.slot(dx: 60, dy: 0), .english)
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: -60), .dictionary)
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: 60), .kana)
    }

    /// The axis that moved more wins, so a slightly crooked swipe still lands.
    func testDiagonalsGoToTheStrongerAxis() {
        XCTAssertEqual(ModeWheel.slot(dx: -50, dy: -30), .japanese)
        XCTAssertEqual(ModeWheel.slot(dx: 30, dy: -50), .dictionary)
        XCTAssertEqual(ModeWheel.slot(dx: 20, dy: 40), .kana)
    }

    /// The mode key is on the bottom row, so there's less room to drag down.
    func testDownNeedsLessDistance() {
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: 22), .kana)
        XCTAssertNil(ModeWheel.slot(dx: 22, dy: 0))
    }

    func testOnlyKanaNeedsAPause() {
        XCTAssertEqual(ModeWheel.slots.filter(\.needsDeliberatePick), [.kana])
    }

    /// The wheel draws each slot at its angle; dragging that way must pick it.
    func testEachSlotsDrawnDirectionPicksIt() {
        for leftHanded in [false, true] {
            for slot in ModeWheel.slots {
                let angle = ModeWheel.angle(of: slot, leftHanded: leftHanded)
                XCTAssertEqual(ModeWheel.slot(dx: cos(angle) * 50, dy: -sin(angle) * 50, leftHanded: leftHanded), slot)
            }
        }
    }

    func testLeftHandedSwapsLeftAndRight() {
        XCTAssertEqual(ModeWheel.slot(dx: 60, dy: 0, leftHanded: true), .japanese)
        XCTAssertEqual(ModeWheel.slot(dx: -60, dy: 0, leftHanded: true), .english)
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: -60, leftHanded: true), .dictionary)
        XCTAssertEqual(ModeWheel.slot(dx: 0, dy: 60, leftHanded: true), .kana)
    }

    /// The wheel doesn't depend on the current mode, so a direction always means the same slot.
    func testSlotsMapToModes() {
        for mode in InputMode.allCases {
            XCTAssertEqual(ModeWheelSlot(mode).inputMode, mode)
        }
        XCTAssertNil(ModeWheelSlot.kana.inputMode)
    }
}
