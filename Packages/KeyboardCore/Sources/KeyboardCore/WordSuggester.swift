import Foundation

/// The spell checker the suggestions use. On iOS this is `UITextChecker` (see `SystemSpellChecker`
/// in the keyboard); tests use a fake.
public protocol SpellChecking: AnyObject {
    func isKnown(_ word: String) -> Bool
    /// Likely corrections for a misspelled word, best first.
    func corrections(for word: String) -> [String]
    /// Words that start with `prefix`, most likely first.
    func completions(for prefix: String) -> [String]
}

/// What the candidate bar offers for the English word being typed.
public struct WordSuggestions: Equatable {
    /// What the user typed.
    public let typed: String
    /// What space will change it to, if autocorrect would change it.
    public let autocorrection: String?
    /// Other words, best first, not repeating `typed` or `autocorrection`.
    public let alternatives: [String]
}

/// English suggestions and autocorrect, like the system keyboard's, built from the spell checker,
/// the user's text replacements (omw → On my way!) and words the user has typed before.
public final class WordSuggester {
    public var checker: SpellChecking? {
        didSet { clearCheckerCache() }
    }
    public var learned: LearnedWords
    /// iOS text replacements, shortcut → phrase.
    public var textReplacements: [String: String] = [:]
    /// Words that are always right, e.g. contact names (lowercased).
    public var knownWords: Set<String> = []

    public init(checker: SpellChecking?, learned: LearnedWords) {
        self.checker = checker
        self.learned = learned
    }

    public func suggestions(for word: String) -> WordSuggestions? {
        guard !word.isEmpty, word.contains(where: \.isLetter) else { return nil }

        let autocorrection = correction(for: word)
        var alternatives: [String] = []
        func add(_ candidate: String) {
            let candidate = Self.matchingCase(candidate, to: word)
            if candidate != word, candidate != autocorrection, !alternatives.contains(candidate) {
                alternatives.append(candidate)
            }
        }
        if autocorrection == nil, checker != nil, !isKnown(word) {
            checkerCorrections(word).prefix(2).forEach(add)
        }
        learned.completions(for: word).forEach(add)
        checkerCompletions(word).prefix(3).forEach(add)
        return WordSuggestions(typed: word, autocorrection: autocorrection, alternatives: Array(alternatives.prefix(3)))
    }

    /// What autocorrect would change `word` to, if anything.
    public func correction(for word: String) -> String? {
        if let phrase = textReplacements[word.lowercased()] {
            return phrase
        }
        // Leave short words, known words, words the user has used and anything with digits alone.
        guard word.count >= 3, !isKnown(word), !word.contains(where: \.isNumber),
              let best = checkerCorrections(word).first else { return nil }
        // Only small fixes: one typo in a short word, two in a longer one, never a different word.
        let allowed = word.count <= 4 ? 1 : 2
        guard Self.typoDistance(word.lowercased(), best.lowercased()) <= allowed else { return nil }
        return Self.matchingCase(best, to: word)
    }

    /// Edit distance where swapping two neighbouring letters (teh → the) counts as one typo.
    static func typoDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { table[i][0] = i }
        for j in 0...b.count { table[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                table[i][j] = min(table[i - 1][j] + 1, table[i][j - 1] + 1, table[i - 1][j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    table[i][j] = min(table[i][j], table[i - 2][j - 2] + 1)
                }
            }
        }
        return table[a.count][b.count]
    }

    public func isKnown(_ word: String) -> Bool {
        knownWords.contains(word.lowercased()) || learned.contains(word) || checkerKnows(word)
    }

    // MARK: - Spell checker, remembered

    // The system spell checker can take a moment, and every letter typed asks again about the
    // same word, so its answers are remembered (they only depend on the word).
    private var knownCache: [String: Bool] = [:]
    private var correctionsCache: [String: [String]] = [:]
    private var completionsCache: [String: [String]] = [:]

    private func clearCheckerCache() {
        knownCache = [:]
        correctionsCache = [:]
        completionsCache = [:]
    }

    private func remembered<Value>(_ cache: inout [String: Value], _ word: String, _ ask: () -> Value) -> Value {
        if let value = cache[word] {
            return value
        }
        if cache.count > 300 {
            cache = [:]
        }
        let value = ask()
        cache[word] = value
        return value
    }

    private func checkerKnows(_ word: String) -> Bool {
        guard let checker else { return true }
        return remembered(&knownCache, word) { checker.isKnown(word) }
    }

    private func checkerCorrections(_ word: String) -> [String] {
        guard let checker else { return [] }
        return remembered(&correctionsCache, word) { checker.corrections(for: word) }
    }

    private func checkerCompletions(_ prefix: String) -> [String] {
        guard let checker else { return [] }
        return remembered(&completionsCache, prefix) { checker.completions(for: prefix) }
    }

    /// "hel" → "hello", "Hel" → "Hello", "HEL" → "HELLO".
    static func matchingCase(_ suggestion: String, to typed: String) -> String {
        if typed.count > 1, typed == typed.uppercased(), typed != typed.lowercased() {
            return suggestion.uppercased()
        }
        if let first = typed.first, first.isUppercase, let suggestionFirst = suggestion.first {
            return suggestionFirst.uppercased() + suggestion.dropFirst()
        }
        return suggestion
    }

    /// The word just before the cursor ("I like ca" → "ca"), or "" if the cursor follows a space.
    public static func currentWord(in textBeforeCursor: String) -> String {
        String(textBeforeCursor.reversed().prefix { $0.isLetter || $0 == "'" }.reversed())
    }
}
