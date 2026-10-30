import XCTest
@testable import KeyboardCore

/// Whole phrases and conjugated words (KanaKanjiConverter), with a small dictionary in the
/// format `tools/build_dictionary.py` writes, most common first.
final class ConversionTests: XCTestCase {
    private static let tsv = [
        "\tいい\t1\ti-adjective\tgood\tadj-ix",
        "私\tわたし\t0\tpronoun\tI; me\t",
        "行く\tいく\t0\tverb\tto go\tv5k-s",
        "本\tほん\t0\tnoun\tbook\t",
        "今日\tきょう\t0\tnoun\ttoday\t",
        "来る\tくる\t0\tverb\tto come\tvk",
        "高い\tたかい\t0\ti-adjective\thigh; expensive\tadj-i",
        "勉強\tべんきょう\t0\tnoun\tstudy\tvs",
        "学生\tがくせい\t0\tnoun\tstudent\t",
        "天気\tてんき\t0\tnoun\tweather\t",
        "食べる\tたべる\t0\tverb\tto eat\tv1",
        "読む\tよむ\t0\tverb\tto read\tv5m",
        "橋\tはし\t0\tnoun\tbridge\t",
        "泳ぐ\tおよぐ\t0\tverb\tto swim\tv5g",
        "箸\tはし\t0\tnoun\tchopsticks\t",
        "居る\tいる\t1\tverb\tto be\tv1",
    ].joined(separator: "\n")

    private let dictionary = JapaneseDictionary(tsv: tsv)
    private var converter: KanaKanjiConverter { KanaKanjiConverter(dictionary: dictionary) }

    private func best(_ reading: String) -> String? {
        converter.convert(reading).first?.text
    }

    func testConjugatedVerbs() {
        XCTAssertEqual(best("たべた"), "食べた")
        XCTAssertEqual(best("たべました"), "食べました")
        XCTAssertEqual(best("たべなかった"), "食べなかった")
        XCTAssertEqual(best("いった"), "行った")  // 行く: って, not いて
        XCTAssertEqual(best("いきます"), "行きます")
        XCTAssertEqual(best("ほんをよんだ"), "本を読んだ")  // む → んだ
        XCTAssertEqual(best("およいでいます"), "泳いでいます")  // ぐ → いで
    }

    func testIrregularVerbsAndSuru() {
        XCTAssertEqual(best("きた"), "来た")
        XCTAssertEqual(best("こない"), "来ない")
        XCTAssertEqual(best("べんきょうしています"), "勉強しています")
        XCTAssertEqual(best("べんきょうした"), "勉強した")
    }

    func testAdjectives() {
        XCTAssertEqual(best("たかかった"), "高かった")
        XCTAssertEqual(best("たかくない"), "高くない")
    }

    func testWholePhrases() {
        XCTAssertEqual(best("きょうはいいてんきですね"), "今日はいい天気ですね")
        XCTAssertEqual(best("わたしはがくせいです"), "私は学生です")
        XCTAssertEqual(best("はしをたべます"), "橋を食べます")
    }

    func testUnknownTextStaysKana() {
        XCTAssertEqual(best("ぴよぴよ"), "ぴよぴよ")
    }

    func testFirstWordsOfAPhrase() {
        let phrase = converter.convert("はしをたべる").first
        let first = converter.firstWords(of: "はしをたべる", best: phrase)
        XCTAssertEqual(first.prefix(2).map(\.text), ["橋", "箸"])
        XCTAssertEqual(first.first?.reading, "はし")
        // A single word has no parts.
        XCTAssertTrue(converter.firstWords(of: "たべた", best: converter.convert("たべた").first).isEmpty)
    }

    func testLearnedChoicesWin() {
        let store = MemoryStore()
        let history = ConversionHistory(store: store)
        history.record(reading: "はし", word: "箸")
        let learned = KanaKanjiConverter(dictionary: dictionary, history: history)
        XCTAssertEqual(learned.convert("はしをたべます").first?.text, "箸を食べます")
    }

    func testLiveConversionConvertsOnlyWhatItIsSureOf() {
        XCTAssertEqual(converter.liveConversion("たべた"), "食べた")
        XCTAssertEqual(converter.liveConversion("きょうはいいてんきですね"), "今日はいい天気ですね")
        // 橋 and 箸 are too close to call, so はし waits to be picked.
        XCTAssertEqual(converter.liveConversion("はしをたべます"), "はしを食べます")
        XCTAssertEqual(converter.liveConversion("ぴよぴよ"), "ぴよぴよ")
    }

    func testLiveConversionLearns() {
        let history = ConversionHistory(store: MemoryStore())
        let learning = KanaKanjiConverter(dictionary: dictionary, history: history)
        history.record(reading: "はし", word: "箸")
        XCTAssertEqual(learning.liveConversion("はしをたべます"), "箸を食べます")
        // Kana you chose stays kana, on its own and in phrases.
        history.record(reading: "たべた", word: "たべた")
        XCTAssertEqual(learning.liveConversion("たべた"), "たべた")
        history.record(reading: "はし", word: "はし")
        XCTAssertEqual(learning.liveConversion("はしをたべます"), "はしを食べます")
    }

    func testEngineShowsAndConfirmsTheLiveConversion() {
        let output = RecordingOutput()
        let engine = KeyboardEngine(mode: .japanese)
        engine.output = output
        engine.dictionary = dictionary
        "tabeta".forEach { engine.press(.character(String($0))) }
        XCTAssertEqual(output.marked, "食べた")
        engine.press(.returnKey)
        XCTAssertEqual(output.committed, "食べた")

        // Off in settings, and while typing into a search.
        engine.settings.liveConversion = false
        "tabeta".forEach { engine.press(.character(String($0))) }
        XCTAssertEqual(output.marked, "たべた")
        engine.settings.liveConversion = true
        engine.convertsAutomatically = false
        engine.press(.character("a"))
        XCTAssertEqual(output.marked, "たべたあ")
    }

    func testCandidatesOfferPhrasesThenTheFirstWord() {
        var composer = RomajiComposer()
        composer.inputLiteral("はしをたべます")
        let candidates = composer.candidates(using: dictionary)
        XCTAssertEqual(candidates.first?.text, "はしをたべます")
        XCTAssertEqual(candidates[1].text, "橋を食べます")
        let part = candidates.first { $0.part != nil }
        XCTAssertEqual(part?.text, "橋")
        XCTAssertEqual(part?.part, "はし")
    }

    func testPickingTheFirstWordLeavesTheRest() {
        let output = RecordingOutput()
        let engine = KeyboardEngine(mode: .japanese)
        engine.output = output
        engine.dictionary = dictionary
        for character in "hashiwotabemasu" {
            engine.press(.character(String(character)))
        }
        let chopsticks = engine.candidates.first { $0.part != nil && $0.text == "箸" }!
        engine.selectCandidate(chopsticks)
        XCTAssertEqual(output.committed, "箸")
        XCTAssertEqual(output.marked, "をたべます")
        XCTAssertEqual(engine.candidates[1].text, "を食べます")
    }
}
