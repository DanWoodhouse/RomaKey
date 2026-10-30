public enum InputMode: String, CaseIterable {
    case japanese
    case english
    /// Type English, pick a Japanese word from the dictionary.
    case dictionary
}

public enum KeyboardPage: Equatable {
    case letters
    case numbers
    case symbols
}

public enum KeyKind: Hashable {
    case character(String)
    case shift
    case delete
    /// "123" / "ABC" in the bottom row.
    case pageToggle
    /// "#+=" / "123" on the numbers and symbols pages.
    case symbolsToggle
    /// The mode key: tap to step through the modes, or press and drag for the mode wheel
    /// (あ, EN, 辞, かな). There's no 🌐 key (iOS shows one under the keyboard), so the space bar is wider.
    case languageToggle
    case space
    /// ー in Japanese, - in English. Always present, so nothing moves when switching language.
    case longVowel
    case returnKey
}

public enum KeyWidth: Hashable {
    /// Fraction of a row, where a row is `KeyboardLayout.unitsPerRow` wide.
    case units(Double)
    /// Shares whatever space is left in the row.
    case flexible
}

public struct Key: Hashable {
    public let kind: KeyKind
    public let width: KeyWidth

    public init(_ kind: KeyKind, width: KeyWidth = .units(1)) {
        self.kind = kind
        self.width = width
    }
}

public struct KeyRow: Hashable {
    public let keys: [Key]
    /// Empty space at each end of the row, in units.
    public let inset: Double

    public init(_ keys: [Key], inset: Double = 0) {
        self.keys = keys
        self.inset = inset
    }
}

public struct KeyFrame: Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
}

/// Where every key goes. Deliberately takes no `InputMode`: switching between English
/// and Japanese can only change key labels, never key positions.
public struct KeyboardLayout: Hashable {
    public static let unitsPerRow = 10.0

    public let rows: [KeyRow]

    public static func layout(for page: KeyboardPage) -> KeyboardLayout {
        switch page {
        case .letters:
            return KeyboardLayout(rows: [
                characterRow("qwertyuiop"),
                characterRow("asdfghjkl", inset: 0.5),
                KeyRow([Key(.shift, width: .units(1.5))]
                    + characterKeys("zxcvbnm")
                    + [Key(.delete, width: .units(1.5))]),
                bottomRow,
            ])
        case .numbers:
            return KeyboardLayout(rows: [
                characterRow("1234567890"),
                characterRow("-/:;()¥&@\""),
                punctuationRow,
                bottomRow,
            ])
        case .symbols:
            return KeyboardLayout(rows: [
                characterRow("[]{}#%^*+="),
                characterRow("_\\|~<>$€£•"),
                punctuationRow,
                bottomRow,
            ])
        }
    }

    /// What a letter types when swiped up (or held): q–p give 1–0, the other letters symbols,
    /// as on Gboard (a → @ … m → ?). Shown as a small hint in the key's corner.
    public static func secondary(for letter: String) -> String? {
        secondaries[letter.lowercased()]
    }

    private static let secondaries: [String: String] = Dictionary(uniqueKeysWithValues: zip(
        "qwertyuiopasdfghjklzxcvbnm".map(String.init),
        "1234567890@#$_&-+()*\"':;!?".map(String.init)
    ))

    /// The ー/- key's swipe-up and hold options: the label shown, and the character typed. In
    /// Japanese the composer turns the typed romaji punctuation into 、。！？〜.
    public static func punctuation(japanese: Bool) -> [(label: String, typed: String)] {
        let typed = [",", ".", "!", "?", "~"]
        let labels = japanese ? ["、", "。", "！", "？", "〜"] : typed
        return Array(zip(labels, typed))
    }

    /// The key name the secondary settings use for the ー/- key.
    public static let longVowelKeyName = "ー"

    /// Lays the rows out in a `width`-wide area, top to bottom.
    public func frames(width: Double, rowHeight: Double) -> [[KeyFrame]] {
        let unit = width / Self.unitsPerRow
        return rows.enumerated().map { index, row in
            var fixedUnits = 0.0
            var flexibleCount = 0
            for key in row.keys {
                switch key.width {
                case .units(let units): fixedUnits += units
                case .flexible: flexibleCount += 1
                }
            }
            let spare = max(Self.unitsPerRow - 2 * row.inset - fixedUnits, 0)
            let flexibleUnits = flexibleCount > 0 ? spare / Double(flexibleCount) : 0

            var x = row.inset * unit
            return row.keys.map { key in
                let units: Double
                switch key.width {
                case .units(let fixed): units = fixed
                case .flexible: units = flexibleUnits
                }
                let frame = KeyFrame(x: x, y: Double(index) * rowHeight, width: units * unit, height: rowHeight)
                x += units * unit
                return frame
            }
        }
    }

    private static func characterKeys(_ characters: String, width: Double = 1) -> [Key] {
        characters.map { Key(.character(String($0)), width: .units(width)) }
    }

    private static func characterRow(_ characters: String, inset: Double = 0) -> KeyRow {
        KeyRow(characterKeys(characters), inset: inset)
    }

    private static let punctuationRow = KeyRow(
        [Key(.symbolsToggle, width: .units(1.5))]
            + characterKeys(".,?!'", width: 1.4)
            + [Key(.delete, width: .units(1.5))]
    )

    /// The same on every phone: no globe key, as iOS shows 🌐 under the keyboard.
    private static let bottomRow = KeyRow([
        Key(.pageToggle, width: .units(1.25)),
        Key(.languageToggle, width: .units(1.25)),
        Key(.space, width: .flexible),
        Key(.longVowel, width: .units(1)),
        Key(.returnKey, width: .units(1.75)),
    ])
}
