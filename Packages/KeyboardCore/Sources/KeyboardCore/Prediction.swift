import Foundation

/// Predictive text: the words likely to come next, shown after a word is finished.
///
/// English comes from a table of common word pairs (Google Books Ngrams, via SymSpell) and from
/// pairs you've typed, which come first. Japanese comes from pairs you've typed, then the
/// particles that usually follow a noun.
public final class NextWordPredictor {
    /// word → the words most likely to follow it, most likely first.
    private let table: [String: [String]]
    private let store: KeyValueStore
    /// "previous␟next" → times typed.
    private var counts: [String: Int]

    private static let key = "nextWords"
    private static let capacity = 5000
    private static let separator = "\u{1F}"
    private static let particles = ["は", "が", "を", "に", "の", "で", "も"]

    /// `tsv` has one word per line, a tab, then its likely next words separated by spaces.
    public init(tsv: String = "", store: KeyValueStore) {
        var table: [String: [String]] = [:]
        for line in tsv.split(separator: "\n") {
            let fields = line.split(separator: "\t")
            guard fields.count == 2 else { continue }
            table[String(fields[0])] = fields[1].split(separator: " ").map(String.init)
        }
        self.table = table
        self.store = store
        counts = store.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    /// Loads the bundled English pairs. About 300 KB, so call it off the main thread.
    public static func bundled(store: KeyValueStore) -> NextWordPredictor {
        let tsv = Bundle.module.url(forResource: "bigrams", withExtension: "tsv")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        return NextWordPredictor(tsv: tsv, store: store)
    }

    /// Remembers that `next` followed `previous`, so it's predicted first next time.
    public func learn(previous: String, next: String) {
        let previous = Self.normalized(previous)
        let next = Self.normalized(next)
        guard !previous.isEmpty, !next.isEmpty else { return }
        counts[previous + Self.separator + next, default: 0] += 1
        if counts.count > Self.capacity {
            // Forget the least-used pairs.
            for (old, _) in counts.sorted(by: { $0.value < $1.value }).prefix(counts.count - Self.capacity) {
                counts.removeValue(forKey: old)
            }
        }
        store.set(counts, forKey: Self.key)
    }

    /// Words likely to follow an English word: yours first, then common English. "i" is "I".
    public func english(after previous: String, limit: Int = 3) -> [String] {
        let previous = Self.normalized(previous)
        var words = learned(after: previous)
        for word in table[previous] ?? [] where !words.contains(word) {
            words.append(word)
        }
        return words.prefix(limit).map { word in
            word == "i" || word.hasPrefix("i'") ? "I" + word.dropFirst() : word
        }
    }

    /// Words likely to follow a Japanese word: yours first, then particles if it ends in kanji
    /// or katakana (so is probably a noun).
    public func japanese(after previous: String, limit: Int = 5) -> [String] {
        var words = learned(after: previous)
        if let last = previous.unicodeScalars.last, Self.isNounEnding(last) {
            for particle in Self.particles where !words.contains(particle) {
                words.append(particle)
            }
        }
        return Array(words.prefix(limit))
    }

    public func reset() {
        counts = [:]
        store.set(nil, forKey: Self.key)
    }

    private func learned(after previous: String) -> [String] {
        let prefix = previous + Self.separator
        return counts
            .filter { $0.key.hasPrefix(prefix) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .map { String($0.key.dropFirst(prefix.count)) }
    }

    private static func normalized(_ word: String) -> String {
        word.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private static func isNounEnding(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x30A1...0x30FA).contains(scalar.value) || scalar == "ー"
    }

    /// The word just before a single trailing space ("I like " → "like"), or nil.
    public static func wordBeforeSpace(in textBeforeCursor: String) -> String? {
        guard textBeforeCursor.hasSuffix(" "), !textBeforeCursor.hasSuffix("  ") else { return nil }
        let word = WordSuggester.currentWord(in: String(textBeforeCursor.dropLast()))
        return word.isEmpty ? nil : word
    }
}

/// Tracks the last word committed in Japanese, so the next word can be predicted, and the pair
/// learned when the next word is committed straight after it.
public struct JapanesePredictionContext {
    private var lastCommitted: String?
    /// The word just before the current composition, if it was typed straight after it.
    private var previousForComposition: String?

    public init() {}

    /// Call when a new composition (or a predicted word) starts.
    public mutating func compositionStarted(textBefore: String?) {
        previousForComposition = previous(textBefore: textBefore)
    }

    /// Call when text is committed: learns the pair, and makes `text` the word to predict after.
    public mutating func committed(_ text: String, predictor: NextWordPredictor?) {
        if let previousForComposition {
            predictor?.learn(previous: previousForComposition, next: text)
        }
        previousForComposition = nil
        lastCommitted = text
    }

    /// The last committed word, if the cursor is still right after it.
    public func previous(textBefore: String?) -> String? {
        guard let lastCommitted, let textBefore, textBefore.hasSuffix(lastCommitted) else { return nil }
        return lastCommitted
    }
}
