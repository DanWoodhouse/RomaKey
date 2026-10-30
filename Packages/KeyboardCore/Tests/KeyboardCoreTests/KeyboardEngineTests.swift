import XCTest
@testable import KeyboardCore

final class KeyboardEngineTests: XCTestCase {
    private var output: RecordingOutput!

    private func makeEngine(mode: InputMode) -> KeyboardEngine {
        output = RecordingOutput()
        let engine = KeyboardEngine(mode: mode)
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
        let engine = makeEngine(mode: .english)
        let english = engine.layout.frames(width: 375, rowHeight: 54)
        for expected in [InputMode.dictionary, .japanese, .english] {
            engine.press(.languageToggle)
            XCTAssertEqual(engine.mode, expected)
            XCTAssertEqual(engine.layout.frames(width: 375, rowHeight: 54), english)
        }
        for mode in InputMode.allCases {
            engine.setMode(mode)
            XCTAssertEqual(engine.layout.frames(width: 375, rowHeight: 54), english)
        }
    }

    func testBottomRowHasNoGlobeAndAWideSpaceBar() {
        let bottom = KeyboardLayout.layout(for: .letters).rows[3]
        XCTAssertEqual(bottom.keys.map(\.kind), [.pageToggle, .languageToggle, .space, .longVowel, .returnKey])
        // 4.5 of the row's 10 units, up from 3.25 when 🌐 had its own key.
        let space = KeyboardLayout.layout(for: .letters).frames(width: 100, rowHeight: 10)[3][2]
        XCTAssertEqual(space.width, 45, accuracy: 0.001)
    }

    func testLetterRowsAreStandardQwerty() {
        let layout = KeyboardLayout.layout(for: .letters)
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
            let layout = KeyboardLayout.layout(for: page)
            for (row, frames) in zip(layout.rows, layout.frames(width: 100, rowHeight: 10)) {
                let used = frames.reduce(0) { $0 + $1.width } + 2 * row.inset * 10
                XCTAssertEqual(used, 100, accuracy: 0.001, "\(page) row doesn't fill the width")
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
        XCTAssertEqual(engine.candidates.map(\.text), ["こーひー", "コーヒー"])
        engine.selectCandidate(Candidate("コーヒー"))
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
        engine.settings.autoCapitalization = false
        engine.press(.shift)
        time += 0.2
        engine.press(.shift)
        XCTAssertEqual(engine.shift, .locked)
        engine.press(.character("a"))
        XCTAssertEqual(engine.shift, .locked)
        engine.press(.shift)
        XCTAssertEqual(engine.shift, .off)
    }

    // MARK: - 辞書 mode and kanji

    func testLanguageKeyCyclesThroughEnabledModes() {
        let engine = makeEngine(mode: .japanese)
        engine.press(.languageToggle)
        engine.press(.languageToggle)
        XCTAssertEqual(engine.mode, .dictionary)
        XCTAssertEqual(engine.label(for: .languageToggle), .text("辞"))
        engine.press(.languageToggle)
        XCTAssertEqual(engine.mode, .japanese)

        engine.settings.languageKeyModes = [.japanese, .english]
        engine.press(.languageToggle)
        engine.press(.languageToggle)
        XCTAssertEqual(engine.mode, .japanese)
    }

    func testDictionaryModeLooksUpEnglish() {
        let engine = makeEngine(mode: .dictionary)
        engine.dictionary = JapaneseDictionary(tsv: SampleDictionary.tsv)
        type("dog", into: engine)
        XCTAssertEqual(output.marked, "dog")
        XCTAssertEqual(engine.candidates.map(\.text), ["犬", "戌"])
        XCTAssertEqual(engine.candidates.first?.entry?.reading, "いぬ")

        engine.selectCandidate(engine.candidates[0])
        XCTAssertEqual(output.committed, "犬")
        XCTAssertEqual(output.marked, "")
    }

    func testDictionaryModeMultiWordAndReturn() {
        let engine = makeEngine(mode: .dictionary)
        engine.dictionary = JapaneseDictionary(tsv: SampleDictionary.tsv)
        type("thank you", into: engine)
        XCTAssertEqual(output.marked, "thank you")
        XCTAssertEqual(engine.candidates.map(\.text), ["どうも", "ありがとう"])
        // Return keeps the English as typed.
        engine.press(.returnKey)
        XCTAssertEqual(output.committed, "thank you")
    }

    func testJapaneseModeOffersKanji() {
        let engine = makeEngine(mode: .japanese)
        engine.dictionary = JapaneseDictionary(tsv: SampleDictionary.tsv)
        type("inu", into: engine)
        XCTAssertEqual(engine.candidates.map(\.text), ["いぬ", "犬", "戌", "イヌ"])
        engine.press(.returnKey)

        // Predictions: longer words starting with what's been typed so far.
        type("ta", into: engine)
        XCTAssertEqual(engine.candidates.map(\.text), ["た", "タ", "食べる"])
    }

    // MARK: - Quality of life

    func testAutoCapitalisation() {
        let engine = makeEngine(mode: .english)
        engine.textDidChange()
        XCTAssertEqual(engine.shift, .once)
        type("hi. so", into: engine)
        XCTAssertEqual(output.committed, "Hi. So")
        XCTAssertEqual(engine.shift, .off)
    }

    func testDoubleSpaceTypesFullStop() {
        let engine = makeEngine(mode: .english)
        engine.settings.autoCapitalization = false
        type("ok  ", into: engine)
        XCTAssertEqual(output.committed, "ok. ")
        engine.settings.doubleSpacePeriod = false
        type("x  ", into: engine)
        XCTAssertEqual(output.committed, "ok. x  ")
    }

    func testDeleteWord() {
        let engine = makeEngine(mode: .english)
        output.committed = "hello wide world  "
        engine.deleteWordBackward()
        XCTAssertEqual(output.committed, "hello wide ")
        engine.deleteWordBackward()
        XCTAssertEqual(output.committed, "hello ")
        output.committed = "日本語"
        engine.deleteWordBackward()
        XCTAssertEqual(output.committed, "日本")
    }

    func testSpaceReturnsToLetters() {
        let engine = makeEngine(mode: .english)
        engine.press(.pageToggle)
        engine.press(.character("4"))
        engine.press(.space)
        XCTAssertEqual(engine.page, .letters)
    }

    func testFullWidthSpaceSetting() {
        let engine = makeEngine(mode: .japanese)
        engine.settings.fullWidthSpace = true
        engine.press(.space)
        XCTAssertEqual(output.committed, "　")
    }

    func testCursorMoveConfirmsComposition() {
        let engine = makeEngine(mode: .japanese)
        type("ka", into: engine)
        engine.moveCursor(by: -1)
        XCTAssertEqual(output.committed, "か")
        XCTAssertEqual(output.cursorMoves, -1)
    }
}
