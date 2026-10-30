import XCTest
@testable import KeyboardCore

final class FlickKeyboardEngineTests: XCTestCase {
    private var output: RecordingOutput!
    private var engine: FlickKeyboardEngine!

    override func setUp() {
        output = RecordingOutput()
        engine = FlickKeyboardEngine()
        engine.output = output
    }

    /// The key on the current page whose label is `label`.
    private func key(_ label: String) -> FlickKeyKind {
        let kinds = engine.layout.cells.map(\.kind)
        guard let kind = kinds.first(where: { engine.label(for: $0) == .text(label) }) else {
            fatalError("No key labelled \(label) on \(engine.page)")
        }
        return kind
    }

    func testFlickDirections() {
        engine.press(key("か"), direction: .center)
        engine.press(key("か"), direction: .left)
        engine.press(key("か"), direction: .up)
        engine.press(key("か"), direction: .right)
        engine.press(key("か"), direction: .down)
        XCTAssertEqual(output.marked, "かきくけこ")
    }

    func testFlickingAWord() {
        // こんにちは
        engine.press(key("か"), direction: .down)
        engine.press(key("わ"), direction: .up)
        engine.press(key("な"), direction: .left)
        engine.press(key("た"), direction: .left)
        engine.press(key("は"), direction: .center)
        XCTAssertEqual(output.marked, "こんにちは")
        engine.press(.returnKey)
        XCTAssertEqual(output.committed, "こんにちは")
    }

    func testRepeatedTapsCycle() {
        let a = key("あ")
        engine.press(a)
        engine.press(a)
        engine.press(a)
        XCTAssertEqual(output.marked, "う")
        engine.press(.reverseCycle)
        XCTAssertEqual(output.marked, "い")
    }

    func testAdvanceLetsTheSameKanaRepeat() {
        let a = key("あ")
        engine.press(a)
        engine.press(.advance)
        engine.press(a)
        XCTAssertEqual(output.marked, "ああ")
        XCTAssertEqual(output.cursorMoves, 0)
    }

    func testAdvanceMovesCursorWhenIdle() {
        engine.press(.advance)
        XCTAssertEqual(output.cursorMoves, 1)
    }

    func testModifierKey() {
        engine.press(key("は"))
        engine.press(.modifier)
        XCTAssertEqual(output.marked, "ば")
        engine.press(.modifier)
        XCTAssertEqual(output.marked, "ぱ")
        engine.press(.modifier)
        XCTAssertEqual(output.marked, "は")

        engine.press(key("た"), direction: .up)
        engine.press(.modifier)
        XCTAssertEqual(output.marked, "はっ")
    }

    func testFlickingNowhereTypesNothing() {
        engine.press(key("わ"), direction: .down)
        XCTAssertFalse(engine.isComposing)
    }

    func testAlphabetPageTypesDirectly() {
        engine.press(key("あ"))
        engine.press(.pageCycle)
        XCTAssertEqual(output.committed, "あ")
        XCTAssertEqual(engine.page, .alphabet)

        engine.press(key("GHI"), direction: .up)
        engine.press(key("GHI"))
        engine.press(.caseToggle)
        XCTAssertEqual(output.committed, "あiG")
    }

    func testPagesCycleBackToKana() {
        engine.press(.pageCycle)
        engine.press(.pageCycle)
        XCTAssertEqual(engine.page, .numbers)
        engine.press(key("2"), direction: .left)
        XCTAssertEqual(output.committed, "¥")
        engine.press(.pageCycle)
        XCTAssertEqual(engine.page, .kana)
    }

    func testKatakanaCandidate() {
        engine.press(key("か"), direction: .left)
        engine.press(key("ら"), direction: .center)
        XCTAssertEqual(engine.candidates, ["きら", "キラ"])
    }

    func testDirectionFromDrag() {
        XCTAssertEqual(FlickDirection(dx: 5, dy: -5), .center)
        XCTAssertEqual(FlickDirection(dx: -30, dy: 10), .left)
        XCTAssertEqual(FlickDirection(dx: 4, dy: -40), .up)
        XCTAssertEqual(FlickDirection(dx: 30, dy: 0), .right)
        XCTAssertEqual(FlickDirection(dx: 0, dy: 25), .down)
    }

    func testGridFillsTheKeyboard() {
        for page in [FlickPage.kana, .alphabet, .numbers] {
            let layout = FlickLayout.layout(for: page)
            XCTAssertEqual(layout.cells.count, 19)
            let area = layout.frames(width: 100, rowHeight: 10).reduce(0) { $0 + $1.width * $1.height }
            XCTAssertEqual(area, 100 * 40, accuracy: 0.001)
        }
    }
}
