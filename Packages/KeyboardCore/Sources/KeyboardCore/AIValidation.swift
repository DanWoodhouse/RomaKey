import Foundation

/// One fix from a grammar check.
public struct GrammarCorrection: Equatable {
    public let original: String
    public let fix: String
    public let reason: String

    public init(original: String, fix: String, reason: String) {
        self.original = original
        self.fix = fix
        self.reason = reason
    }
}

public enum GrammarOutcome: Equatable {
    case noMistakes
    case corrected(text: String, corrections: [GrammarCorrection])
    /// The model rewrote the text instead of fixing it, so nothing is shown.
    case unreliable
}

public struct Explanation: Equatable {
    /// Nil if the model's reading wasn't pure hiragana.
    public let reading: String?
    public let meaning: String
    public let notes: [String]
}

public struct Translation: Equatable {
    public let japanese: String
    /// Nil if the model's reading wasn't pure hiragana.
    public let reading: String?
}

/// Checks the model's output before anyone sees it. A small model sometimes rewrites instead of
/// fixing, answers instead of translating, or invents readings. These checks catch the obvious
/// cases, so the keyboard shows nothing rather than something wrong.
public enum AIValidation {
    public static func grammar(input: String, corrected: String, corrections: [GrammarCorrection]) -> GrammarOutcome {
        let corrected = corrected.trimmingCharacters(in: .whitespacesAndNewlines)
        if corrected.isEmpty || AIText.normalized(corrected) == AIText.normalized(input) {
            return .noMistakes
        }
        // A real fix changes a little of the text; a rewrite changes most of it.
        guard AIText.similarity(input, corrected) >= 0.4,
              AIText.containsJapanese(input) == AIText.containsJapanese(corrected) else {
            return .unreliable
        }
        // Only keep explanations that point at text that's actually there.
        let grounded = corrections.filter { !$0.original.isEmpty && input.contains($0.original) && $0.original != $0.fix }
        return .corrected(text: corrected, corrections: grounded)
    }

    public static func translation(japanese: String, reading: String) -> Translation? {
        let japanese = japanese.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIText.containsJapanese(japanese), !AIText.containsLatinLetters(japanese) else { return nil }
        return Translation(japanese: japanese, reading: AIText.isHiraganaReading(reading) ? reading : nil)
    }

    public static func rewrite(input: String, output: String) -> String? {
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIText.containsJapanese(output), !output.isEmpty else { return nil }
        // Politeness changes endings, not content: the length stays in the same ballpark.
        let ratio = Double(output.count) / Double(max(input.count, 1))
        guard (0.5...2.5).contains(ratio) else { return nil }
        return AIText.normalized(output) == AIText.normalized(input) ? nil : output
    }

    public static func explanation(reading: String, meaning: String, notes: [String]) -> Explanation? {
        let meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIText.containsLatinLetters(meaning) else { return nil }
        return Explanation(
            reading: AIText.isHiraganaReading(reading) ? reading : nil,
            meaning: meaning,
            notes: notes.prefix(3).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        )
    }

    /// An English rewrite stays in English and keeps roughly the same content: not a
    /// translation, not an answer, not the same text again.
    public static func englishRewrite(input: String, output: String) -> String? {
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIText.containsLatinLetters(output), !AIText.containsJapanese(output) else { return nil }
        let ratio = Double(output.count) / Double(max(input.count, 1))
        guard (0.2...3).contains(ratio) else { return nil }
        return AIText.normalized(output) == AIText.normalized(input) ? nil : output
    }

    /// A translation into English must be English.
    public static func englishTranslation(_ english: String) -> String? {
        let english = english.trimmingCharacters(in: .whitespacesAndNewlines)
        guard AIText.containsLatinLetters(english), !AIText.containsJapanese(english) else { return nil }
        return english
    }

    /// A conversion may only turn readings into kanji: every kana in the output must appear, in
    /// order, in the input. That rules out added, dropped, translated or answered text.
    public static func kanjiConversion(input: String, output: String) -> String? {
        let output = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !output.isEmpty, !AIText.containsLatinLetters(output) || AIText.containsLatinLetters(input) else { return nil }
        let source = Array(KanaConverter.hiragana(from: input))
        var position = 0
        for character in KanaConverter.hiragana(from: output) where AIText.isKana(character) {
            guard let found = source[position...].firstIndex(of: character) else { return nil }
            position = found + 1
        }
        return output
    }
}

/// Small text helpers shared by the prompts, validation and evaluation.
public enum AIText {
    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { isKanaScalar($0) || isKanjiScalar($0) }
    }

    public static func containsLatinLetters(_ text: String) -> Bool {
        text.unicodeScalars.contains { ("a"..."z").contains($0) || ("A"..."Z").contains($0) }
    }

    static func isKana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy(isKanaScalar)
    }

    /// Hiragana (and ー) plus punctuation and spaces: what a reading should look like.
    static func isHiraganaReading(_ text: String) -> Bool {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        return text.unicodeScalars.allSatisfy { scalar in
            (0x3041...0x309F).contains(scalar.value) || scalar.value == 0x30FC
                || "、。？！・「」 ?!,.　".unicodeScalars.contains(scalar)
        }
    }

    private static func isKanaScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x309F).contains(scalar.value) || (0x30A0...0x30FF).contains(scalar.value)
    }

    private static func isKanjiScalar(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) || scalar.value == 0x3005
    }

    /// For comparing answers: no spaces, no final punctuation, lowercased.
    public static func normalized(_ text: String) -> String {
        var result = text.lowercased().filter { !$0.isWhitespace }
        while let last = result.last, "。．.！!？?、,".contains(last) {
            result.removeLast()
        }
        return result
    }

    /// 1 for identical texts, 0 for completely different ones (by edit distance).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let a = Array(a), b = Array(b)
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        // Levenshtein distance, one row at a time.
        var previous = Array(0...b.count)
        for i in a.indices {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (a[i] == b[j] ? 0 : 1))
            }
            previous = current
        }
        return 1 - Double(previous[b.count]) / Double(longest)
    }
}
