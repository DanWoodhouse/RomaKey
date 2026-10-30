/// Romaji → kana mappings, following the conventions of the common desktop IMEs
/// (Hepburn and Kunrei spellings, `x`/`l` prefixes for small kana).
///
/// `n` on its own and double consonants (`kk` → っk) are handled by `RomajiComposer`
/// rather than by this table, because they depend on the character that follows.
enum RomajiTable {
    static let mappings: [String: String] = [
        // Vowels
        "a": "あ", "i": "い", "u": "う", "e": "え", "o": "お",

        // K / G
        "ka": "か", "ki": "き", "ku": "く", "ke": "け", "ko": "こ",
        "kya": "きゃ", "kyi": "きぃ", "kyu": "きゅ", "kye": "きぇ", "kyo": "きょ",
        "kwa": "くぁ",
        "ga": "が", "gi": "ぎ", "gu": "ぐ", "ge": "げ", "go": "ご",
        "gya": "ぎゃ", "gyi": "ぎぃ", "gyu": "ぎゅ", "gye": "ぎぇ", "gyo": "ぎょ",
        "gwa": "ぐぁ",

        // S / Z / J
        "sa": "さ", "si": "し", "su": "す", "se": "せ", "so": "そ",
        "shi": "し", "sha": "しゃ", "shu": "しゅ", "she": "しぇ", "sho": "しょ",
        "sya": "しゃ", "syi": "しぃ", "syu": "しゅ", "sye": "しぇ", "syo": "しょ",
        "za": "ざ", "zi": "じ", "zu": "ず", "ze": "ぜ", "zo": "ぞ",
        "zya": "じゃ", "zyi": "じぃ", "zyu": "じゅ", "zye": "じぇ", "zyo": "じょ",
        "ja": "じゃ", "ji": "じ", "ju": "じゅ", "je": "じぇ", "jo": "じょ",
        "jya": "じゃ", "jyi": "じぃ", "jyu": "じゅ", "jye": "じぇ", "jyo": "じょ",

        // T / D / C
        "ta": "た", "ti": "ち", "tu": "つ", "te": "て", "to": "と",
        "chi": "ち", "cha": "ちゃ", "chu": "ちゅ", "che": "ちぇ", "cho": "ちょ",
        "tya": "ちゃ", "tyi": "ちぃ", "tyu": "ちゅ", "tye": "ちぇ", "tyo": "ちょ",
        "cya": "ちゃ", "cyi": "ちぃ", "cyu": "ちゅ", "cye": "ちぇ", "cyo": "ちょ",
        "tsu": "つ", "tsa": "つぁ", "tsi": "つぃ", "tse": "つぇ", "tso": "つぉ",
        "tha": "てゃ", "thi": "てぃ", "thu": "てゅ", "the": "てぇ", "tho": "てょ",
        "twu": "とぅ",
        "da": "だ", "di": "ぢ", "du": "づ", "de": "で", "do": "ど",
        "dya": "ぢゃ", "dyi": "ぢぃ", "dyu": "ぢゅ", "dye": "ぢぇ", "dyo": "ぢょ",
        "dha": "でゃ", "dhi": "でぃ", "dhu": "でゅ", "dhe": "でぇ", "dho": "でょ",
        "dwu": "どぅ",
        "ca": "か", "ci": "し", "cu": "く", "ce": "せ", "co": "こ",

        // N
        "na": "な", "ni": "に", "nu": "ぬ", "ne": "ね", "no": "の",
        "nya": "にゃ", "nyi": "にぃ", "nyu": "にゅ", "nye": "にぇ", "nyo": "にょ",
        "n'": "ん", "xn": "ん",

        // H / F / B / P
        "ha": "は", "hi": "ひ", "hu": "ふ", "he": "へ", "ho": "ほ",
        "hya": "ひゃ", "hyi": "ひぃ", "hyu": "ひゅ", "hye": "ひぇ", "hyo": "ひょ",
        "fa": "ふぁ", "fi": "ふぃ", "fu": "ふ", "fe": "ふぇ", "fo": "ふぉ",
        "fya": "ふゃ", "fyu": "ふゅ", "fyo": "ふょ",
        "ba": "ば", "bi": "び", "bu": "ぶ", "be": "べ", "bo": "ぼ",
        "bya": "びゃ", "byi": "びぃ", "byu": "びゅ", "bye": "びぇ", "byo": "びょ",
        "pa": "ぱ", "pi": "ぴ", "pu": "ぷ", "pe": "ぺ", "po": "ぽ",
        "pya": "ぴゃ", "pyi": "ぴぃ", "pyu": "ぴゅ", "pye": "ぴぇ", "pyo": "ぴょ",

        // M / Y / R
        "ma": "ま", "mi": "み", "mu": "む", "me": "め", "mo": "も",
        "mya": "みゃ", "myi": "みぃ", "myu": "みゅ", "mye": "みぇ", "myo": "みょ",
        "ya": "や", "yi": "い", "yu": "ゆ", "ye": "いぇ", "yo": "よ",
        "ra": "ら", "ri": "り", "ru": "る", "re": "れ", "ro": "ろ",
        "rya": "りゃ", "ryi": "りぃ", "ryu": "りゅ", "rye": "りぇ", "ryo": "りょ",

        // W / V / Q
        "wa": "わ", "wi": "うぃ", "wu": "う", "we": "うぇ", "wo": "を",
        "wha": "うぁ", "whi": "うぃ", "whu": "う", "whe": "うぇ", "who": "うぉ",
        "wyi": "ゐ", "wye": "ゑ",
        "va": "ゔぁ", "vi": "ゔぃ", "vu": "ゔ", "ve": "ゔぇ", "vo": "ゔぉ",
        "vya": "ゔゃ", "vyu": "ゔゅ", "vyo": "ゔょ",
        "qa": "くぁ", "qi": "くぃ", "qu": "く", "qe": "くぇ", "qo": "くぉ",

        // Small kana (x- or l- prefix)
        "xa": "ぁ", "xi": "ぃ", "xu": "ぅ", "xe": "ぇ", "xo": "ぉ",
        "la": "ぁ", "li": "ぃ", "lu": "ぅ", "le": "ぇ", "lo": "ぉ",
        "xya": "ゃ", "xyu": "ゅ", "xyo": "ょ",
        "lya": "ゃ", "lyu": "ゅ", "lyo": "ょ",
        "xtu": "っ", "xtsu": "っ", "ltu": "っ", "ltsu": "っ",
        "xwa": "ゎ", "lwa": "ゎ",
        "xka": "ゕ", "xke": "ゖ", "lka": "ゕ", "lke": "ゖ",

        // Punctuation
        "-": "ー", ",": "、", ".": "。",
        "[": "「", "]": "」", "~": "〜", "/": "・",
        "?": "？", "!": "！",
    ]

    /// Every proper prefix of a key in `mappings`, e.g. "k", "ky", "ts".
    static let prefixes: Set<String> = {
        var result = Set<String>()
        for key in mappings.keys {
            var prefix = ""
            for character in key.dropLast() {
                prefix.append(character)
                result.insert(prefix)
            }
        }
        return result
    }()
}
