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
    public let text: String
    public let entry: DictionaryEntry?

    public init(_ text: String, entry: DictionaryEntry? = nil) {
        self.text = text
        self.entry = entry
    }
}

extension RomajiComposer {
    /// Conversion choices for the current composition: the hiragana as typed, dictionary words
    /// with that reading (kanji), the katakana, then longer words it could be the start of.
    public func candidates(using dictionary: JapaneseDictionary?) -> [Candidate] {
        guard !isEmpty else { return [] }
        let hiragana = finalizedText
        let katakana = KanaConverter.katakana(from: hiragana)
        let exact = dictionary?.entries(reading: hiragana) ?? []

        var result: [Candidate] = []
        var seen: Set<String> = []
        func add(_ text: String, _ entry: DictionaryEntry?) {
            if seen.insert(text).inserted {
                result.append(Candidate(text, entry: entry))
            }
        }

        add(hiragana, exact.first { $0.word == hiragana })
        for entry in exact {
            add(entry.word, entry)
        }
        add(katakana, exact.first { $0.word == katakana })
        for entry in dictionary?.predictions(readingPrefix: hiragana) ?? [] {
            add(entry.word, entry)
        }
        return result
    }
}
