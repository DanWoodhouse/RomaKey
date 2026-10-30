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

    /// Removes the start of the composition once it's converted (`reading`, in hiragana),
    /// leaving the rest to convert next.
    public mutating func removeFirst(_ reading: String) {
        flushPending()
        kana = String(kana.dropFirst(reading.count))
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

    /// かな → Hepburn romaji, for learners: ねこ → neko, がっこう → gakkou, まっちゃ → matcha,
    /// きんえん → kin'en, コーヒー → koohii. Anything that isn't kana is left alone.
    public static func romaji(from text: String) -> String {
        let kana = Array(hiragana(from: text))
        var result = ""
        var doubleNext = false
        var index = 0
        while index < kana.count {
            let character = kana[index]
            if character == "っ" {
                doubleNext = true
                index += 1
                continue
            }
            var piece: String
            var length = 1
            if index + 1 < kana.count, let pair = romajiPairs[String(kana[index...index + 1])] {
                piece = pair
                length = 2
            } else if character == "ー", let vowel = result.last(where: { "aeiou".contains($0) }) {
                piece = String(vowel)
            } else {
                piece = romajiSingles[character] ?? String(character)
            }
            if doubleNext, let first = piece.first, first.isLetter, !"aeiou".contains(first) {
                piece = (piece.hasPrefix("ch") ? "t" : String(first)) + piece
            }
            doubleNext = false
            // ん before a vowel or y: kin'en, not kinen.
            if character == "ん", index + 1 < kana.count,
               let next = romajiSingles[kana[index + 1]]?.first, "aeiouy".contains(next) {
                piece = "n'"
            }
            result += piece
            index += length
        }
        return result
    }

    private static let romajiSingles: [Character: String] = {
        let kana = "あいうえおかきくけこがぎぐげごさしすせそざじずぜぞたちつてとだぢづでどなにぬねのはひふへほ"
            + "ばびぶべぼぱぴぷぺぽまみむめもやゆよらりるれろわゐゑをんぁぃぅぇぉゃゅょゎゔ"
        let romaji = "a i u e o ka ki ku ke ko ga gi gu ge go sa shi su se so za ji zu ze zo ta chi tsu te to "
            + "da ji zu de do na ni nu ne no ha hi fu he ho ba bi bu be bo pa pi pu pe po ma mi mu me mo "
            + "ya yu yo ra ri ru re ro wa i e o n a i u e o ya yu yo wa vu"
        return Dictionary(uniqueKeysWithValues: zip(kana, romaji.split(separator: " ").map(String.init)))
    }()

    /// きゃ → kya, しゅ → shu, ふぁ → fa, …
    private static let romajiPairs: [String: String] = {
        var pairs: [String: String] = [
            "ふぁ": "fa", "ふぃ": "fi", "ふぇ": "fe", "ふぉ": "fo", "てぃ": "ti", "でぃ": "di",
            "しぇ": "she", "じぇ": "je", "ちぇ": "che", "うぃ": "wi", "うぇ": "we", "うぉ": "wo",
            "ゔぁ": "va", "ゔぃ": "vi", "ゔぇ": "ve", "ゔぉ": "vo", "とぅ": "tu", "どぅ": "du", "つぁ": "tsa",
        ]
        let stems: [(String, String)] = [
            ("き", "ky"), ("ぎ", "gy"), ("し", "sh"), ("じ", "j"), ("ち", "ch"), ("ぢ", "j"), ("に", "ny"),
            ("ひ", "hy"), ("び", "by"), ("ぴ", "py"), ("み", "my"), ("り", "ry"),
        ]
        for (kana, stem) in stems {
            for (small, vowel) in [("ゃ", "a"), ("ゅ", "u"), ("ょ", "o")] {
                pairs[kana + small] = stem + vowel
            }
        }
        return pairs
    }()

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
