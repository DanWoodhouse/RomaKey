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

/// Words the bundled dictionary lacked, the person's own words, and phrases learned in parts.
final class OwnWordsTests: XCTestCase {
    func testSuffixesWithASoundChangeConvert() throws {
        let bundled = try XCTUnwrap(JapaneseDictionary.bundled())
        let converter = KanaKanjiConverter(dictionary: bundled)
        // 済み reads ずみ after a noun: both readings are in the dictionary now.
        XCTAssertEqual(converter.convert("かくにんずみ").first?.text, "確認済み")
        XCTAssertTrue(bundled.entries(reading: "すみ").contains { $0.word == "済み" })
        XCTAssertTrue(bundled.entries(reading: "じゅう").contains { $0.word == "中" })
    }

    func testAGodanStemWorksAsANoun() {
        let dictionary = JapaneseDictionary(tsv: "読む\tよむ\t0\tverb\tto read\tv5m\n町\tまち\t0\tnoun\ttown\t\n待つ\tまつ\t0\tverb\tto wait\tv5t")
        let converter = KanaKanjiConverter(dictionary: dictionary)
        XCTAssertTrue(converter.convert("よみ").map(\.text).contains("読み"))
        // A real noun with the same reading still comes first.
        XCTAssertEqual(converter.convert("まち").first?.text, "町")
    }

    func testOwnWordsComeFirstAndWorkInsidePhrases() {
        let dictionary = JapaneseDictionary(tsv: "行く\tいく\t0\tverb\tto go\tv5k-s")
        dictionary.userWords = UserWord.table([UserWord(reading: "らーめんや", word: "ラーメン屋")])
        var composer = RomajiComposer()
        for character in "ra-menya" { composer.input(character) }
        XCTAssertEqual(composer.candidates(using: dictionary).first?.text, "ラーメン屋")
        XCTAssertEqual(KanaKanjiConverter(dictionary: dictionary).convert("らーめんやにいく").first?.text, "ラーメン屋に行く")
    }

    func testReadingsCanBeTypedInRomajiOrKatakana() {
        XCTAssertEqual(UserWord.normalizedReading("kakuninzumi"), "かくにんずみ")
        XCTAssertEqual(UserWord.normalizedReading("カクニン"), "かくにん")
        XCTAssertNil(UserWord.normalizedReading("確認"))
        XCTAssertNil(UserWord.normalizedReading(" "))
    }

    func testOnlyKanaTextReplacementsBecomeWords() {
        let table = UserWord.table([], replacements: [("omw", "On my way!"), ("かくにんずみ", "確認済み")])
        XCTAssertEqual(table, ["かくにんずみ": ["確認済み"]])
    }

    func testAPhraseConvertedInPartsIsRememberedWhole() {
        let history = ConversionHistory(store: MemoryStore())
        history.recordPart(reading: "かくにん", word: "確認")
        history.finishPhrase(reading: "ずみ", word: "済み")
        XCTAssertEqual(history.choices(for: "かくにんずみ"), ["確認済み"])
        XCTAssertEqual(history.choices(for: "かくにん"), ["確認"])

        // A phrase given up on isn't glued onto the next one.
        history.recordPart(reading: "はし", word: "箸")
        history.abandonPhrase()
        history.finishPhrase(reading: "ほん", word: "本")
        XCTAssertTrue(history.choices(for: "はしほん").isEmpty)
    }

    func testLearnedPhrasesWorkInsideLongerReadings() {
        let dictionary = JapaneseDictionary(tsv: "です\tです\t1\texpression\tis\t")
        let history = ConversionHistory(store: MemoryStore())
        history.record(reading: "かくにんずみ", word: "確認済み")
        XCTAssertEqual(KanaKanjiConverter(dictionary: dictionary, history: history).convert("かくにんずみです").first?.text, "確認済みです")
    }
}

/// The memory-mapped lexicon of rarer words (ExtendedLexicon).
final class ExtendedLexiconTests: XCTestCase {
    /// A lexicon file in the format `tools/build_dictionary.py` writes.
    private func lexicon(_ lines: [(String, [String])]) -> ExtendedLexicon? {
        let sorted = lines.sorted { Array($0.0.utf8).lexicographicallyPrecedes(Array($1.0.utf8)) }
        var text = Data()
        var offsets: [UInt32] = []
        for (reading, words) in sorted {
            offsets.append(UInt32(text.count))
            let parts = [reading] + words.map { "\($0)\u{1F}0\u{1F}noun\u{1F}meaning" }
            text.append(Data((parts.joined(separator: "\t") + "\n").utf8))
        }
        var data = Data("RKLX".utf8)
        for number in [UInt32(1), UInt32(sorted.count), UInt32(sorted.map(\.0.count).max() ?? 0)] + offsets {
            withUnsafeBytes(of: number.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(text)
        return ExtendedLexicon(data: data)
    }

    func testFindsReadingsAndKnowsWhenToStopLooking() throws {
        let lexicon = try XCTUnwrap(lexicon([("はいとく", ["背徳"]), ("はいとくかん", ["背徳感"]), ("かん", ["棺"])]))
        XCTAssertEqual(lexicon.longestReading, 6)
        XCTAssertEqual(lexicon.lookup("はいとく").words.map(\.text), ["背徳"])
        XCTAssertTrue(lexicon.lookup("はいとく").continues)  // はいとくかん starts with it
        XCTAssertFalse(lexicon.lookup("はいとくかん").continues)
        XCTAssertTrue(lexicon.lookup("はい").words.isEmpty)
        XCTAssertTrue(lexicon.lookup("はい").continues)
        XCTAssertFalse(lexicon.lookup("ほ").continues)
        XCTAssertEqual(lexicon.lookup("かん").words.first?.entry.shortMeaning, "meaning")
        XCTAssertTrue(lexicon.lookup("ん").words.isEmpty)
    }

    func testRejectsOtherFiles() {
        XCTAssertNil(ExtendedLexicon(data: Data("not a lexicon".utf8)))
    }

    func testRareWordsConvertWithoutBeatingCommonOnes() throws {
        let dictionary = try XCTUnwrap(JapaneseDictionary.bundled())
        dictionary.extended = try XCTUnwrap(ExtendedLexicon.bundled())
        let converter = KanaKanjiConverter(dictionary: dictionary)
        XCTAssertEqual(converter.convert("はいとく").first?.text, "背徳")
        XCTAssertEqual(converter.convert("はいとくかん").first?.text, "背徳感")
        XCTAssertEqual(converter.convert("きょうはいいてんきですね").first?.text, "今日はいい天気ですね")
        XCTAssertEqual(converter.convert("かいしゃにいきます").first?.text, "会社に行きます")
    }
}
