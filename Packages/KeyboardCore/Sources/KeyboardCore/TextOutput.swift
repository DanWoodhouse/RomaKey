/// Where the engines send text. The keyboard extensions forward these to `UITextDocumentProxy`.
public protocol TextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func setMarkedText(_ text: String)
    func unmarkText()
    func moveCursor(by offset: Int)
    /// Text before the cursor, if the host app shares it. Used for auto-capitals and deleting words.
    var textBeforeCursor: String? { get }
}

public enum KeyLabel: Equatable {
    case text(String)
    /// SF Symbol name.
    case systemImage(String)
}

extension TextOutput {
    /// Shows the in-progress composition as underlined (marked) text.
    func show(_ composer: RomajiComposer) {
        if composer.isEmpty {
            setMarkedText("")
            unmarkText()
        } else {
            setMarkedText(composer.displayText)
        }
    }

    /// Replaces the marked text with `text` and confirms it.
    func commit(_ text: String) {
        setMarkedText(text)
        unmarkText()
    }
}

/// Something the candidate bar offers. Dictionary words carry their entry, for meanings and details.
public struct Candidate: Hashable {
    public enum Kind: Hashable {
        /// Kana/kanji conversion, or a 辞書 result.
        case conversion
        /// An English completion or alternative spelling.
        case word
        /// What space will change the English word to.
        case autocorrection
        /// Keep the English word exactly as typed.
        case typed
        case emoji
        /// A likely next word, shown after a word is finished (predictive text).
        case prediction
    }

    public let text: String
    public let entry: DictionaryEntry?
    public let kind: Kind
    /// For a conversion of only the start of the composition (箸 for はし in はしをたべる): the
    /// reading it covers. The rest stays in the composition, to convert next.
    public let part: String?

    public init(_ text: String, entry: DictionaryEntry? = nil, kind: Kind = .conversion, part: String? = nil) {
        self.text = text
        self.entry = entry
        self.kind = kind
        self.part = part
    }
}

extension RomajiComposer {
    /// Conversion choices for the current composition: words the user picked for this reading
    /// before, the hiragana as typed, whole-phrase conversions (今日はいい天気, 食べました),
    /// dictionary words with that reading, the katakana, matching emoji, the first word of a
    /// phrase on its own, then longer words it could be the start of.
    public func candidates(
        using dictionary: JapaneseDictionary?,
        history: ConversionHistory? = nil,
        emoji: EmojiCatalog? = nil
    ) -> [Candidate] {
        guard !isEmpty else { return [] }
        let hiragana = finalizedText
        let katakana = KanaConverter.katakana(from: hiragana)
        let exact = dictionary?.entries(reading: hiragana) ?? []
        let entry = { (word: String) in exact.first { $0.word == word || $0.kanji == word } }

        var result: [Candidate] = []
        var seen: Set<String> = []
        func add(_ text: String, _ entry: DictionaryEntry?, kind: Candidate.Kind = .conversion) {
            if seen.insert(text).inserted {
                result.append(Candidate(text, entry: entry, kind: kind))
            }
        }

        for word in history?.choices(for: hiragana) ?? [] {
            add(word, entry(word))
        }
        add(hiragana, entry(hiragana))
        // Phrases and conjugated words come first when the reading isn't a single dictionary
        // word, and after the dictionary's own words when it is.
        let converter = dictionary.map { KanaKanjiConverter(dictionary: $0, history: history) }
        let phrases = converter?.convert(hiragana) ?? []
        func addPhrases() {
            for phrase in phrases {
                add(phrase.text, phrase.segments.count == 1 ? phrase.segments[0].entry : nil)
            }
        }
        if exact.isEmpty {
            addPhrases()
        }
        for item in exact {
            add(item.word, item)
        }
        addPhrases()
        add(katakana, entry(katakana))
        for item in emoji?.suggestions(for: hiragana, limit: 2) ?? [] {
            add(item.character, nil, kind: .emoji)
        }
        for word in converter?.firstWords(of: hiragana, best: phrases.first) ?? [] where seen.insert(word.text).inserted {
            result.append(Candidate(word.text, entry: word.entry, part: word.reading))
        }
        for item in dictionary?.predictions(readingPrefix: hiragana) ?? [] {
            add(item.word, item)
        }
        return result
    }
}
