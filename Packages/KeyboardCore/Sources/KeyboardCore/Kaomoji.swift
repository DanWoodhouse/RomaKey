/// 顔文字: Japanese text faces, a staple of Japanese keyboards.
public enum Kaomoji {
    public struct Category {
        public let name: String
        public let faces: [String]
    }

    public static let categories: [Category] = [
        Category(name: "嬉しい · Happy", faces: [
            "(^_^)", "(^▽^)", "(*^▽^*)", "(≧▽≦)", "ヽ(・∀・)ﾉ", "(๑˃ᴗ˂)ﻭ", "(◕‿◕)", "٩(◕‿◕)۶", "(´∀`)", "(＾ｖ＾)",
        ]),
        Category(name: "好き · Love", faces: [
            "(♡˙︶˙♡)", "(´♡‿♡`)", "(*˘︶˘*).｡.:*♡", "(ღ˘⌣˘ღ)", "♡(｡- ω -)", "(っ´▽`)っ♡",
        ]),
        Category(name: "ありがとう · Thanks", faces: [
            "m(_ _)m", "(_ _)", "(._.)ゞ", "(*_ _)人", "<(_ _)>",
        ]),
        Category(name: "悲しい · Sad", faces: [
            "(;_;)", "(T_T)", "(ToT)", "(´；ω；`)", "(ｏ´_｀ｏ)", "(｡•́︿•̀｡)",
        ]),
        Category(name: "驚き · Surprised", faces: [
            "(ﾟoﾟ;)", "Σ(ﾟДﾟ)", "(⊙_⊙)", "(°ロ°)", "w(ﾟДﾟ)w", "(・□・;)",
        ]),
        Category(name: "困った · Awkward", faces: [
            "(^_^;)", "(-_-;)", "(・_・;)", "(¬_¬)", "┐(￣ヘ￣)┌", "(´-ω-`)",
        ]),
        Category(name: "怒り · Angry", faces: [
            "(｀ε´)", "(╬ Ò﹏Ó)", "(ﾉಥ益ಥ)ﾉ", "(＃｀Д´)", "(-_-メ)",
        ]),
        Category(name: "動物 · Animals", faces: [
            "(=^・^=)", "ฅ^•ﻌ•^ฅ", "U・ᴥ・U", "(・⊝・)", "ʕ•ᴥ•ʔ", "><(((('>",
        ]),
        Category(name: "その他 · Other", faces: [
            "(￣ー￣)ｂ", "(^_−)☆", "( ˘ω˘ )ｽﾔｧ", "(ง •̀_•́)ง", "¯\\_(ツ)_/¯", "(╯°□°)╯︵ ┻━┻",
        ]),
    ]
}

/// Letters with accents, shown when a letter key is held (é, ü, ñ…).
public enum Accents {
    private static let table: [String: [String]] = [
        "a": ["à", "á", "â", "ä", "æ", "ã", "å", "ā"],
        "c": ["ç", "ć", "č"],
        "e": ["è", "é", "ê", "ë", "ē", "ė", "ę"],
        "i": ["î", "ï", "í", "ī", "į", "ì"],
        "l": ["ł"],
        "n": ["ñ", "ń"],
        "o": ["ô", "ö", "ò", "ó", "œ", "ø", "ō", "õ"],
        "s": ["ß", "ś", "š"],
        "u": ["û", "ü", "ù", "ú", "ū"],
        "y": ["ÿ"],
        "z": ["ž", "ź", "ż"],
    ]

    /// Alternatives for a letter, matching its case. Empty if it has none.
    public static func alternatives(for letter: String) -> [String] {
        let lower = letter.lowercased()
        let options = table[lower] ?? []
        return lower == letter ? options : options.map { $0.uppercased() }
    }
}
