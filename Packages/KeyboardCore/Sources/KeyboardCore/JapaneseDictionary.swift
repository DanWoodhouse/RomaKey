import Foundation

/// One word from the dictionary.
public struct DictionaryEntry: Hashable {
    /// Kanji spelling, if the word has one.
    public let kanji: String
    public let reading: String
    /// The word is normally written in kana even though it has a kanji spelling (ありがとう, not 有り難う).
    public let usuallyKana: Bool
    public let partOfSpeech: String
    /// Meanings separated by " | ", glosses within a meaning by "; ".
    let sensesText: String

    /// How the word is normally written.
    public var word: String {
        usuallyKana || kanji.isEmpty ? reading : kanji
    }

    /// Each meaning as a list of English glosses.
    public var senses: [[String]] {
        sensesText.components(separatedBy: " | ").map { $0.components(separatedBy: "; ") }
    }

    /// The first couple of glosses, for the candidate bar.
    public var shortMeaning: String {
        senses.first?.prefix(2).joined(separator: "; ") ?? ""
    }
}

/// A Japanese–English dictionary built from JMdict's common words, ordered most frequent first.
///
/// Searching works both ways: English → Japanese for 辞書 mode, and reading → words for kanji
/// conversion while typing Japanese.
public final class JapaneseDictionary {
    public let entries: [DictionaryEntry]

    private struct IndexItem {
        let key: String
        let entry: Int32
        /// 0 = the entry's main meaning. Higher is a weaker match.
        let weight: UInt8
    }

    /// Whole glosses ("eat", "thank you"), normalised. Sorted by key.
    private let glosses: [IndexItem]
    /// Single words from the glosses. Sorted by key.
    private let words: [IndexItem]
    /// Readings in hiragana. Sorted by key.
    private let readings: [IndexItem]

    /// Parses the tab-separated format written by `tools/build_dictionary.py`:
    /// kanji, reading, usually-kana (0/1), part of speech, senses.
    public init(tsv: String) {
        var entries: [DictionaryEntry] = []
        var glosses: [IndexItem] = []
        var words: [IndexItem] = []
        var readings: [IndexItem] = []

        for line in tsv.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 5 else { continue }
            let entry = DictionaryEntry(
                kanji: String(fields[0]),
                reading: String(fields[1]),
                usuallyKana: fields[2] == "1",
                partOfSpeech: String(fields[3]),
                sensesText: String(fields[4])
            )
            let index = Int32(entries.count)
            entries.append(entry)
            readings.append(IndexItem(key: KanaConverter.hiragana(from: entry.reading), entry: index, weight: 0))

            for (senseIndex, sense) in entry.senses.enumerated() {
                for (glossIndex, gloss) in sense.enumerated() {
                    let normalized = Self.normalize(gloss)
                    guard !normalized.isEmpty else { continue }
                    var weight: UInt8 = senseIndex == 0 ? (glossIndex == 0 ? 0 : 1) : 2
                    // Capitalised glosses are usually names or zodiac signs ("the Dog"), so rank them lower.
                    if Self.withoutArticle(gloss.trimmingCharacters(in: .whitespaces)).first?.isUppercase == true {
                        weight += 1
                    }
                    glosses.append(IndexItem(key: normalized, entry: index, weight: weight))
                    for word in Set(Self.words(in: normalized)) {
                        words.append(IndexItem(key: word, entry: index, weight: weight))
                    }
                }
            }
        }

        self.entries = entries
        self.glosses = glosses.sorted { $0.key < $1.key }
        self.words = words.sorted { $0.key < $1.key }
        self.readings = readings.sorted { $0.key < $1.key }
    }

    /// The dictionary bundled with the keyboard. Takes a moment to build, so call it off the main thread.
    public static func bundled() -> JapaneseDictionary? {
        guard let url = Bundle.module.url(forResource: "dictionary", withExtension: "tsv"),
              let tsv = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return JapaneseDictionary(tsv: tsv)
    }

    /// English → Japanese. Best matches first: exact meaning, then a word in the meaning, then
    /// meanings and words that start with what's been typed so far.
    public func search(english query: String, limit: Int = 20) -> [DictionaryEntry] {
        let normalized = Self.normalize(query)
        guard !normalized.isEmpty else { return [] }
        let isSingleWord = !normalized.contains(" ")

        var best: [Int32: (Int, UInt8)] = [:]
        func add<S: Sequence>(_ items: S, matchClass: Int) where S.Element == IndexItem {
            for item in items {
                let score = (matchClass, item.weight)
                if let existing = best[item.entry], existing <= score { continue }
                best[item.entry] = score
            }
        }

        add(Self.items(in: glosses, equalTo: normalized), matchClass: 0)
        if isSingleWord {
            add(Self.items(in: words, equalTo: normalized), matchClass: 1)
        }
        add(Self.items(in: glosses, withPrefix: normalized, limit: 2000), matchClass: 2)
        if isSingleWord {
            add(Self.items(in: words, withPrefix: normalized, limit: 2000), matchClass: 3)
        }

        return best
            .sorted { ($0.value.0, $0.value.1, $0.key) < ($1.value.0, $1.value.1, $1.key) }
            .prefix(limit)
            .map { entries[Int($0.key)] }
    }

    /// Words read exactly as `reading` (hiragana or katakana), most common first.
    public func entries(reading: String) -> [DictionaryEntry] {
        let key = KanaConverter.hiragana(from: reading)
        return Self.items(in: readings, equalTo: key).map(\.entry).sorted().map { entries[Int($0)] }
    }

    /// Longer words whose reading starts with `prefix`, most common first.
    public func predictions(readingPrefix prefix: String, limit: Int = 8) -> [DictionaryEntry] {
        let key = KanaConverter.hiragana(from: prefix)
        guard !key.isEmpty else { return [] }
        return Self.items(in: readings, withPrefix: key, limit: 2000)
            .filter { $0.key != key }
            .map(\.entry)
            .sorted()
            .prefix(limit)
            .map { entries[Int($0)] }
    }

    // MARK: - Index helpers

    private static func lowerBound(in items: [IndexItem], of key: String) -> Int {
        var low = 0
        var high = items.count
        while low < high {
            let middle = (low + high) / 2
            if items[middle].key < key {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private static func items(in items: [IndexItem], equalTo key: String) -> ArraySlice<IndexItem> {
        let start = lowerBound(in: items, of: key)
        var end = start
        while end < items.count && items[end].key == key {
            end += 1
        }
        return items[start..<end]
    }

    private static func items(in items: [IndexItem], withPrefix prefix: String, limit: Int) -> ArraySlice<IndexItem> {
        let start = lowerBound(in: items, of: prefix)
        var end = start
        while end < items.count && end - start < limit && items[end].key.hasPrefix(prefix) {
            end += 1
        }
        return items[start..<end]
    }

    // MARK: - Text helpers

    /// "To eat (something)" → "eat". Lowercased, with parentheses, leading articles and extra spaces removed.
    static func normalize(_ text: String) -> String {
        var result = text.lowercased()
        // Remove parentheses innermost first, so "dog (Canis (lupus) familiaris)" → "dog".
        while let close = result.firstIndex(of: ")"), let open = result[..<close].lastIndex(of: "(") {
            result.removeSubrange(open...close)
        }
        result = withoutArticle(result.trimmingCharacters(in: .whitespaces))
        return result.split(separator: " ").joined(separator: " ")
    }

    private static func withoutArticle(_ text: String) -> String {
        for article in ["to ", "a ", "an ", "the "] where text.lowercased().hasPrefix(article) {
            return String(text.dropFirst(article.count))
        }
        return text
    }

    private static func words(in text: String) -> [String] {
        text.split { !($0.isLetter || $0.isNumber || $0 == "'") }.map(String.init)
    }
}
