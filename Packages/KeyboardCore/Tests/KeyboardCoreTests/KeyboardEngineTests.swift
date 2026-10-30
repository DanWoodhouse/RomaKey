import XCTest
@testable import KeyboardCore

final class KeyboardEngineTests: XCTestCase {
    private var output: RecordingOutput!

    private func makeEngine(mode: InputMode, showsGlobe: Bool = true) -> KeyboardEngine {
        output = RecordingOutput()
        let engine = KeyboardEngine(mode: mode, showsGlobe: showsGlobe)
        engine.output = output
        return engine
    }

    private func type(_ text: String, into engine: KeyboardEngine) {
        for character in text {
            engine.press(character == " " ? .space : .character(String(character)))
        }
    }

    // MARK: - Layout stays put

    func testSwitchingLanguageNeverMovesKeys() {
        for showsGlobe in [true, false] {
            let engine = makeEngine(mode: .english, showsGlobe: showsGlobe)
            let english = engine.layout.frames(width: 375, rowHeight: 54)
            engine.press(.languageToggle)
            XCTAssertEqual(engine.mode, .japanese)
            XCTAssertEqual(engine.layout.frames(width: 375, rowHeight: 54), english)
        }
    }

    func testLetterRowsAreStandardQwerty() {
        let layout = KeyboardLayout.layout(for: .letters, showsGlobe: true)
        let letters = layout.rows.prefix(3).map { row in
            row.keys.compactMap { key -> String? in
                if case .character(let character) = key.kind { return character }
                return nil
            }.joined()
        }
        XCTAssertEqual(letters, ["qwertyuiop", "asdfghjkl", "zxcvbnm"])

        // The middle row keeps its half-key stagger: a sits between q and w.
        let frames = layout.frames(width: 100, rowHeight: 10)
        XCTAssertEqual(frames[1][0].x, 5, accuracy: 0.001)
        // z sits under s, as on a standard keyboard.
        XCTAssertEqual(frames[2][1].x, 15, accuracy: 0.001)
    }

    func testEveryRowFillsTheWidth() {
        for page in [KeyboardPage.letters, .numbers, .symbols] {
            for showsGlobe in [true, false] {
                let layout = KeyboardLayout.layout(for: page, showsGlobe: showsGlobe)
                for (row, frames) in zip(layout.rows, layout.frames(width: 100, rowHeight: 10)) {
                    let used = frames.reduce(0) { $0 + $1.width } + 2 * row.inset * 10
                    XCTAssertEqual(used, 100, accuracy: 0.001, "\(page) row doesn't fill the width")
                }
            }
        }
    }

    // MARK: - Typing

    func testEnglishTyping() {
        let engine = makeEngine(mode: .english)
        engine.press(.shift)
        type("hi there", into: engine)
        engine.press(.longVowel)
        XCTAssertEqual(output.committed, "Hi there-")
    }

    func testJapaneseComposesThenCommitsOnReturn() {
        let engine = makeEngine(mode: .japanese)
        type("ra", into: engine)
        engine.press(.longVowel)
        type("men", into: engine)
        XCTAssertEqual(output.marked, "らーめn")
        XCTAssertEqual(engine.label(for: .returnKey), .text("確定"))

        engine.press(.returnKey)
        XCTAssertEqual(output.committed, "らーめん")
        XCTAssertEqual(output.marked, "")
        XCTAssertFalse(engine.isComposing)
    }

    func testKatakanaCandidate() {
        let engine = makeEngine(mode: .japanese)
        type("ko-hi-", into: engine)
        XCTAssertEqual(engine.candidates, ["こーひー", "コーヒー"])
        engine.selectCandidate("コーヒー")
        XCTAssertEqual(output.committed, "コーヒー")
    }

    func testSwitchingLanguageCommitsComposition() {
        let engine = makeEngine(mode: .japanese)
        type("nihon", into: engine)
        engine.press(.languageToggle)
        XCTAssertEqual(output.committed, "にほん")
        XCTAssertEqual(engine.mode, .english)
    }

    func testDeleteEditsCompositionBeforeDocument() {
        let engine = makeEngine(mode: .japanese)
        output.committed = "x"
        type("ka", into: engine)
        engine.press(.delete)
        XCTAssertEqual(output.marked, "")
        XCTAssertEqual(output.committed, "x")
        engine.press(.delete)
        XCTAssertEqual(output.committed, "")
    }

    func testShiftDoubleTapLocks() {
        var time = Date(timeIntervalSinceReferenceDate: 0)
        let engine = KeyboardEngine(mode: .english, now: { time })
        engine.press(.shift)
        time += 0.2
        engine.press(.shift)
        XCTAssertEqual(engine.shift, .locked)
        engine.press(.character("a"))
        XCTAssertEqual(engine.shift, .locked)
        engine.press(.shift)
        XCTAssertEqual(engine.shift, .off)
    }
}
