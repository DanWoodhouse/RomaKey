/// Turns typed romaji into hiragana, one character at a time.
///
/// The composition is split into `kana` (already converted) and `pending`
/// (romaji that could still become something, e.g. "k" or "ky").
public struct RomajiComposer: Equatable {
    public private(set) var kana = ""
    public private(set) var pending = ""

    public init() {}

    public var isEmpty: Bool { kana.isEmpty && pending.isEmpty }

    /// What to show while composing. A pending "nn" is shown as ん straight away.
    public var displayText: String {
        kana + (pending == "nn" ? "ん" : pending)
    }

    /// What to insert when the composition is confirmed: a trailing n becomes ん.
    public var finalizedText: String {
        var copy = self
        copy.flushPending()
        return copy.kana
    }

    public mutating func input(_ character: Character) {
        pending += character.lowercased()
        resolve()
    }

    /// Adds text verbatim (e.g. a capital letter typed with shift), with no conversion.
    public mutating func inputLiteral(_ text: String) {
        flushPending()
        kana += text
    }

    public mutating func deleteBackward() {
        if !pending.isEmpty {
            pending.removeLast()
        } else if !kana.isEmpty {
            kana.removeLast()
        }
    }

    public mutating func reset() {
        kana = ""
        pending = ""
    }

    private mutating func flushPending() {
        kana += (pending == "n" || pending == "nn") ? "ん" : pending
        pending = ""
    }

    private mutating func resolve() {
        while !pending.isEmpty {
            let isPrefix = RomajiTable.prefixes.contains(pending)
            if let output = RomajiTable.mappings[pending], !isPrefix {
                kana += output
                pending = ""
                return
            }
            if isPrefix { return }

            // `pending` can no longer become a table entry, so settle its first character.
            let characters = Array(pending)
            let first = characters[0]
            let second = characters.count > 1 ? characters[1] : nil

            if first == "n", let second {
                if second == "n" {
                    // "nn" waits for one more character: "nna" → んな, "nnk" → んk, "nnn" → んn.
                    guard characters.count > 2 else { return }
                    let third = characters[2]
                    kana += "ん"
                    pending = String(characters.dropFirst(Self.isVowel(third) || third == "y" ? 1 : 2))
                    continue
                }
                if !Self.isVowel(second) && second != "y" {
                    kana += "ん"
                    pending = String(characters.dropFirst())
                    continue
                }
            }

            if let second, Self.isSokuon(first, second) {
                kana += "っ"
                pending = String(characters.dropFirst())
                continue
            }

            kana.append(first)
            pending = String(characters.dropFirst())
        }
    }

    private static func isVowel(_ character: Character) -> Bool {
        "aiueo".contains(character)
    }

    /// A doubled consonant ("kk", "tt") or Hepburn "tch" makes a small っ.
    private static func isSokuon(_ first: Character, _ second: Character) -> Bool {
        guard first.isASCII, first.isLetter, first != "n", !isVowel(first) else { return false }
        return first == second || (first == "t" && second == "c")
    }
}

public enum KanaConverter {
    /// ひらがな → カタカナ. Anything that isn't hiragana is left alone.
    public static func katakana(from text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x3041...0x3096).contains(scalar.value) || (0x309D...0x309E).contains(scalar.value),
               let shifted = Unicode.Scalar(scalar.value + 0x60) {
                scalars.append(shifted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    /// カタカナ → ひらがな. Anything that isn't katakana is left alone.
    public static func hiragana(from text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x30A1...0x30F6).contains(scalar.value) || (0x30FD...0x30FE).contains(scalar.value),
               let shifted = Unicode.Scalar(scalar.value - 0x60) {
                scalars.append(shifted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
