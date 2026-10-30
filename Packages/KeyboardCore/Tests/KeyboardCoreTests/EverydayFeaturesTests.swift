import XCTest
@testable import KeyboardCore

/// Stands in for UITextChecker.
private final class FakeSpellChecker: SpellChecking {
    let words: Set<String> = ["the", "hello", "help", "helpful", "cat", "like", "i", "teh"]

    func isKnown(_ word: String) -> Bool {
        word.lowercased() != "teh" && words.contains(word.lowercased())
    }

    func corrections(for word: String) -> [String] {
        switch word.lowercased() {
        case "teh": return ["the", "ten"]
        case "helo": return ["hello", "help"]
        case "xqzv": return ["sex"]  // a "correction" too different to trust
        default: return []
        }
    }

    func completions(for prefix: String) -> [String] {
        words.filter { $0.hasPrefix(prefix.lowercased()) && $0 != prefix.lowercased() }.sorted()
    }
}

private let emojiTSV = """
😀\t0\t1\t\tgrinning face\tgrinning face smile happy\tにっこり笑う顔\tにこにこ 笑顔 えがお
🐱\t3\t0.6\t\tcat face\tcat face kitten\tネコの顔\tネコ ねこ 猫
🐈\t3\t0.7\t\tcat\tcat\tネコ\tネコ ねこ 猫
👍\t1\t0.6\t👍🏻 👍🏼 👍🏽 👍🏾 👍🏿\tthumbs up\tthumbs up like yes\tサムズアップ\tいいね グッド ぐっど
🫨\t0\t15\t\tshaking face\tshaking face\t震える顔\tふるえる
"""

final class EmojiTests: XCTestCase {
    func testSearchInEnglishAndJapanese() {
        let catalog = EmojiCatalog(tsv: emojiTSV)
        // 🐈 is named just "cat", so it beats 🐱 "cat face".
        XCTAssertEqual(catalog.search("cat").map(\.character), ["🐈", "🐱"])
        XCTAssertEqual(catalog.search("ネコ").map(\.character), ["🐈", "🐱"], "katakana matches hiragana keywords")
        XCTAssertEqual(catalog.search("ca").map(\.character), ["🐈", "🐱"], "prefix while typing")
        XCTAssertEqual(catalog.search("cat face").map(\.character), ["🐱"], "every word must match")
        XCTAssertTrue(catalog.search("zebra").isEmpty)
    }

    func testSuggestionsNeedAWholeWord() {
        let catalog = EmojiCatalog(tsv: emojiTSV)
        XCTAssertEqual(catalog.suggestions(for: "Cat").map(\.character), ["🐈", "🐱"])
        XCTAssertEqual(catalog.suggestions(for: "ねこ").map(\.character), ["🐈", "🐱"])
        XCTAssertTrue(catalog.suggestions(for: "ca").isEmpty)
        XCTAssertTrue(catalog.suggestions(for: "c").isEmpty)
    }

    func testSkinTonesAndVersions() {
        let catalog = EmojiCatalog(tsv: emojiTSV, maxVersion: 14)
        XCTAssertFalse(catalog.emoji.contains { $0.character == "🫨" }, "too new for this phone")
        let thumbs = catalog.emoji.first { $0.character == "👍" }!
        XCTAssertEqual(thumbs.withSkinTone(3), "👍🏽")
        XCTAssertEqual(thumbs.withSkinTone(0), "👍")
        XCTAssertEqual(catalog.emoji(in: .animals).count, 2)
        XCTAssertEqual(EmojiCatalog.maxSupportedVersion(iOSMajor: 18, minor: 4), 16.0)
        XCTAssertEqual(EmojiCatalog.maxSupportedVersion(iOSMajor: 17, minor: 0), 15.0)
    }

    func testBundledEmoji() throws {
        let catalog = try XCTUnwrap(EmojiCatalog.bundled())
        XCTAssertGreaterThan(catalog.emoji.count, 1800)
        XCTAssertEqual(catalog.suggestions(for: "ねこ").first?.character, "🐈")
        XCTAssertEqual(catalog.suggestions(for: "dog").first?.character, "🐕", "named dog, not 🦴 tagged dog")
        XCTAssertEqual(catalog.suggestions(for: "sushi").first?.character, "🍣")
        XCTAssertEqual(catalog.suggestions(for: "love").first?.character, "❤️", "hand-picked favourite")
        XCTAssertEqual(catalog.suggestions(for: "にほん").first?.character, "🇯🇵")
        XCTAssertEqual(catalog.suggestions(for: "coffee").first?.character, "\u{2615}")
    }

    func testAccentsAndKaomoji() {
        XCTAssertTrue(Accents.alternatives(for: "e").contains("é"))
        XCTAssertTrue(Accents.alternatives(for: "E").contains("É"))
        XCTAssertTrue(Accents.alternatives(for: "q").isEmpty)
        XCTAssertGreaterThan(Kaomoji.categories.flatMap(\.faces).count, 40)
    }
}

final class LearningTests: XCTestCase {
    func testLearnedWords() {
        let store = MemoryStore()
        let learned = LearnedWords(store: store)
        learned.learn("Kyoto")
        learned.learn("kyoto")
        learned.learn("kyushu")
        learned.learn("a1")  // not a word
        XCTAssertTrue(learned.contains("KYOTO"))
        XCTAssertFalse(learned.contains("a1"))
        XCTAssertEqual(learned.completions(for: "ky"), ["kyoto", "kyushu"])
        XCTAssertTrue(LearnedWords(store: store).contains("kyoto"), "saved")
        learned.reset()
        XCTAssertFalse(LearnedWords(store: store).contains("kyoto"))
    }

    func testConversionHistoryPutsTheUsualChoiceFirst() {
        let store = MemoryStore()
        let history = ConversionHistory(store: store)
        history.record(reading: "きかい", word: "機械")
        history.record(reading: "きかい", word: "機会")
        XCTAssertEqual(history.choices(for: "きかい"), ["機会", "機械"])
        XCTAssertEqual(ConversionHistory(store: store).choices(for: "きかい"), ["機会", "機械"], "saved")

        var composer = RomajiComposer()
        "kikai".forEach { composer.input($0) }
        XCTAssertEqual(composer.candidates(using: nil, history: history).prefix(3).map(\.text), ["機会", "機械", "きかい"])
    }

    func testRecentEmoji() {
        let recent = RecentEmoji(store: MemoryStore())
        recent.use("🐱")
        recent.use("👍")
        recent.use("🐱")
        XCTAssertEqual(recent.items, ["🐱", "👍"])
    }
}

final class WordSuggesterTests: XCTestCase {
    private func makeSuggester() -> WordSuggester {
        let suggester = WordSuggester(checker: FakeSpellChecker(), learned: LearnedWords(store: MemoryStore()))
        suggester.textReplacements = ["omw": "On my way!"]
        return suggester
    }

    func testAutocorrection() {
        let suggester = makeSuggester()
        XCTAssertEqual(suggester.correction(for: "teh"), "the")
        XCTAssertEqual(suggester.correction(for: "Teh"), "The", "keeps the capital")
        XCTAssertNil(suggester.correction(for: "hello"), "known word")
        XCTAssertNil(suggester.correction(for: "xqzv"), "too different to trust")
        XCTAssertEqual(suggester.correction(for: "omw"), "On my way!", "text replacement")
        suggester.learned.learn("teh")
        XCTAssertNil(suggester.correction(for: "teh"), "the user's own word")
    }

    func testSuggestions() {
        let suggester = makeSuggester()
        XCTAssertEqual(suggester.suggestions(for: "hel")?.alternatives, ["hello", "help", "helpful"])
        XCTAssertEqual(suggester.suggestions(for: "Hel")?.alternatives.first, "Hello")
        XCTAssertEqual(suggester.suggestions(for: "helo")?.autocorrection, "hello")
        XCTAssertFalse(suggester.suggestions(for: "helo")!.alternatives.contains("hello"), "no repeats")
        XCTAssertNil(suggester.suggestions(for: ""))
        XCTAssertEqual(WordSuggester.typoDistance("teh", "the"), 1, "a swap is one typo")
        XCTAssertEqual(WordSuggester.typoDistance("helo", "hello"), 1)
        XCTAssertEqual(WordSuggester.typoDistance("xqzv", "sex"), 4)
        XCTAssertEqual(WordSuggester.currentWord(in: "I like ca"), "ca")
        XCTAssertEqual(WordSuggester.currentWord(in: "I like "), "")
        XCTAssertEqual(WordSuggester.currentWord(in: "don'"), "don'")
    }
}

final class EverydayEngineTests: XCTestCase {
    private var output: RecordingOutput!

    private func makeEngine(mode: InputMode) -> KeyboardEngine {
        output = RecordingOutput()
        let engine = KeyboardEngine(mode: mode)
        engine.output = output
        engine.settings.autoCapitalization = false
        engine.suggester = WordSuggester(checker: FakeSpellChecker(), learned: LearnedWords(store: MemoryStore()))
        engine.emojiCatalog = EmojiCatalog(tsv: emojiTSV)
        engine.history = ConversionHistory(store: MemoryStore())
        return engine
    }

    private func type(_ text: String, into engine: KeyboardEngine) {
        for character in text {
            engine.press(character == " " ? .space : .character(String(character)))
        }
    }

    func testAutocorrectOnSpaceAndUndoWithDelete() {
        let engine = makeEngine(mode: .english)
        type("teh", into: engine)
        XCTAssertEqual(engine.candidates.map(\.text).prefix(2), ["teh", "the"])
        XCTAssertEqual(engine.candidates[1].kind, .autocorrection)
        engine.press(.space)
        XCTAssertEqual(output.committed, "the ")
        engine.press(.delete)
        XCTAssertEqual(output.committed, "teh", "delete straight after undoes it")
        engine.press(.space)
        XCTAssertEqual(output.committed, "teh ", "and it's now a known word")
    }

    func testAutocorrectCanBeTurnedOff() {
        let engine = makeEngine(mode: .english)
        engine.settings.autocorrect = false
        type("teh ", into: engine)
        XCTAssertEqual(output.committed, "teh ")
    }

    func testPickingASuggestion() {
        let engine = makeEngine(mode: .english)
        type("I hel", into: engine)
        let help = engine.candidates.first { $0.text == "help" }!
        engine.selectCandidate(help)
        XCTAssertEqual(output.committed, "I help ")
    }

    func testEmojiSuggestionGoesAfterTheWord() {
        let engine = makeEngine(mode: .english)
        type("cat", into: engine)
        let cat = engine.candidates.first { $0.kind == .emoji }!
        XCTAssertEqual(cat.text, "🐈")
        engine.selectCandidate(cat)
        XCTAssertEqual(output.committed, "cat 🐈")
    }

    func testJapaneseEmojiAndLearnedKanji() {
        let engine = makeEngine(mode: .japanese)
        type("neko", into: engine)
        XCTAssertTrue(engine.candidates.contains { $0.text == "🐈" && $0.kind == .emoji })
        engine.selectCandidate(Candidate("猫"))
        XCTAssertEqual(output.committed, "猫")
        type("neko", into: engine)
        XCTAssertEqual(engine.candidates.first?.text, "猫", "the word picked last time comes first")
    }

    func testInsertDirectlyConfirmsComposition() {
        let engine = makeEngine(mode: .japanese)
        type("ka", into: engine)
        engine.insertDirectly("(^_^)")
        XCTAssertEqual(output.committed, "か(^_^)")
    }
}
