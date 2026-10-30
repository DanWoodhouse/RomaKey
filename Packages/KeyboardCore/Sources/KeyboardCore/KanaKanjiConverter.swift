import Foundation

/// How verbs and adjectives change their endings, for converting 食べた, 行きます, 高かった and
/// 勉強しています rather than only dictionary forms.
///
/// Each conjugating word is indexed by its stem (食べ, 行, 高, 勉強), and the endings its class
/// can take are matched against what follows the stem in the reading. The kanji stem keeps the
/// kana ending: たべ + ました → 食べ + ました.
enum Conjugation {
    /// Godan rows: the a, i, u, e and o kana, what comes before て/た, and whether て/た become で/だ.
    private struct Row {
        let a: String, i: String, u: String, e: String, o: String
        let te: String
        let voiced: Bool
    }

    private static let godan: [String: Row] = [
        "v5u": Row(a: "わ", i: "い", u: "う", e: "え", o: "お", te: "っ", voiced: false),
        "v5k": Row(a: "か", i: "き", u: "く", e: "け", o: "こ", te: "い", voiced: false),
        "v5k-s": Row(a: "か", i: "き", u: "く", e: "け", o: "こ", te: "っ", voiced: false),
        "v5g": Row(a: "が", i: "ぎ", u: "ぐ", e: "げ", o: "ご", te: "い", voiced: true),
        "v5s": Row(a: "さ", i: "し", u: "す", e: "せ", o: "そ", te: "し", voiced: false),
        "v5t": Row(a: "た", i: "ち", u: "つ", e: "て", o: "と", te: "っ", voiced: false),
        "v5n": Row(a: "な", i: "に", u: "ぬ", e: "ね", o: "の", te: "ん", voiced: true),
        "v5b": Row(a: "ば", i: "び", u: "ぶ", e: "べ", o: "ぼ", te: "ん", voiced: true),
        "v5m": Row(a: "ま", i: "み", u: "む", e: "め", o: "も", te: "ん", voiced: true),
        "v5r": Row(a: "ら", i: "り", u: "る", e: "れ", o: "ろ", te: "っ", voiced: false),
        "v5r-i": Row(a: "ら", i: "り", u: "る", e: "れ", o: "ろ", te: "っ", voiced: false),
        "v5aru": Row(a: "ら", i: "い", u: "る", e: "れ", o: "ろ", te: "っ", voiced: false),
    ]

    private static let polite = ["ます", "ました", "ません", "ませんでした", "ましょう", "たい", "たかった", "たくない",
                                 "たくなかった", "たくて", "ながら", "そう", "すぎる", "すぎた", "なさい"]
    private static let negative = ["ない", "なかった", "なくて", "なければ", "なきゃ", "ないで", "ず", "ずに"]
    /// Passive, causative and potential forms conjugate like ichidan verbs.
    private static let derived = ["る", "た", "ます", "ました", "ません", "ない", "なかった", "て"]
    private static let te = ["て", "ても", "てください", "ている", "ています", "ていました", "ていた", "ていない", "ていません",
                             "ていなかった", "てる", "てた", "てない", "てます", "てました", "てしまう", "てしまった",
                             "てしまいました", "ておく", "ておいた", "てみる", "てみた", "てみます", "てあげる", "てくれる",
                             "てもらう", "ちゃう", "ちゃった", "た", "たら", "たり", "たです"]
    private static let suru = ["する", "します", "しました", "しません", "しませんでした", "しましょう", "した", "して", "しない",
                               "しなかった", "しなくて", "しよう", "すれば", "させる", "させた", "される", "された", "されます",
                               "している", "しています", "していました", "していた", "していない", "してる", "してた",
                               "してください", "したい", "したかった", "しながら", "しちゃった", "しておく", "しても", "したら",
                               "しそう"]
    private static let kuru = ["くる", "きます", "きました", "きません", "きませんでした", "きましょう", "きた", "きて", "こない",
                               "こなかった", "こよう", "くれば", "こられる", "こさせる", "きたい", "きている", "きています",
                               "きていました", "きてる", "きてた", "きてください", "きちゃった", "きたら", "きても"]
    private static let adjective = ["い", "いです", "かった", "かったです", "くない", "くないです", "くなかった", "くありません",
                                    "くて", "ければ", "く", "さ", "そう", "すぎる", "すぎた", "かったら"]

    /// て → で, た → だ, ちゃ → じゃ, after ぐ, ぬ, ぶ and む verbs (泳いだ, 読んで).
    private static func voiced(_ ending: String) -> String {
        guard let first = ending.first else { return ending }
        let replacement: Character = first == "て" ? "で" : first == "た" ? "だ" : first == "ち" ? "じ" : first
        return String(replacement) + ending.dropFirst()
    }

    /// Every ending a class takes after the stem.
    static func endings(for code: String) -> [String] {
        table[code] ?? []
    }

    private static let table: [String: [String]] = Dictionary(uniqueKeysWithValues:
        (Array(godan.keys) + ["v1", "adj-i", "adj-ix", "vs", "vs-i", "vk"]).map { ($0, build($0)) })

    private static func build(_ code: String) -> [String] {
        var forms: [String] = []
        if let row = godan[code] {
            forms += [row.u, row.e + "ば", row.o + "う"]
            forms += polite.map { row.i + $0 }
            if code != "v5r-i" {  // ある's negative is ない, a word of its own
                forms += negative.map { row.a + $0 }
            }
            for ending in derived {
                forms += [row.a + "れ" + ending, row.a + "せ" + ending, row.e + ending]
            }
            forms += te.map { row.te + (row.voiced ? voiced($0) : $0) }
        } else {
            switch code {
            case "v1":
                forms = ["る", "れば", "よう", "ろ"] + polite + negative + te
                for ending in derived {
                    forms += ["られ" + ending, "させ" + ending, "れ" + ending]
                }
            case "adj-i": forms = adjective
            case "adj-ix": forms = ["い", "いです"]  // いい: its other forms come from 良い (よかった)
            case "vs", "vs-i": forms = suru
            case "vk": forms = kuru
            default: forms = []
            }
        }
        var seen: Set<String> = []
        return forms.filter { seen.insert($0).inserted }
    }

    /// How much of the dictionary form to drop for the stem: 食べる → 食べ, 勉強 → 勉強, 来る → (来).
    private static func stemDrop(_ code: String) -> Int {
        switch code {
        case "vs": return 0
        case "vs-i", "vk": return 2
        default: return 1
        }
    }

    /// The stem in hiragana, or nil if the word doesn't conjugate.
    static func stemReading(of entry: DictionaryEntry) -> String? {
        guard !entry.conjugation.isEmpty, endings(for: entry.conjugation).isEmpty == false else { return nil }
        if entry.conjugation == "vs-i" && !entry.reading.hasSuffix("する") {
            return nil
        }
        let reading = Array(KanaConverter.hiragana(from: entry.reading))
        let drop = stemDrop(entry.conjugation)
        guard reading.count >= drop else { return nil }
        return String(reading.dropLast(drop))
    }

    /// The written form: the kanji stem with the kana ending, or kana throughout if the word is
    /// usually written in kana or its kanji has no clean stem.
    static func written(_ entry: DictionaryEntry, ending: String, reading: String) -> String {
        guard !entry.usuallyKana, !entry.kanji.isEmpty else { return reading }
        let kanji = Array(entry.kanji)
        if entry.conjugation == "vk" {
            guard entry.kanji.hasSuffix("来る") else { return reading }
            return String(kanji.dropLast(2)) + "来" + ending.dropFirst()
        }
        let drop = stemDrop(entry.conjugation)
        // The dropped kana must be the same in both spellings (食べる/たべる).
        guard drop == 0 || entry.kanji.hasSuffix(String(Array(entry.reading).suffix(drop))) else { return reading }
        return String(kanji.dropLast(drop)) + ending
    }
}

/// Converts a whole reading (きょうはいいてんきですね) into the likeliest kanji and kana
/// (今日はいい天気ですね), word by word.
///
/// Every way of splitting the reading into dictionary words, conjugated forms and particles is
/// a path; each word has a cost (lower for common words) and the cheapest paths win (Viterbi,
/// keeping the best few at each position). Anything not in the dictionary stays as kana.
public struct KanaKanjiConverter {
    public struct Segment: Hashable {
        public let reading: String
        public let text: String
        public let entry: DictionaryEntry?
    }

    public struct Conversion: Hashable {
        public let text: String
        public let segments: [Segment]
        let cost: Int
    }

    private let dictionary: JapaneseDictionary
    /// Words picked before for a reading, which win next time.
    private let history: ConversionHistory?

    public init(dictionary: JapaneseDictionary, history: ConversionHistory? = nil) {
        self.dictionary = dictionary
        self.history = history
    }

    /// Lower is likelier. Kept in step with the web preview.
    private enum Cost {
        static let unknown = 6000
        static let function = 1200
        static let inflected = 300
        static let singleKana = 2000
        static let startParticle = 3000
        static let particlePair = 500
        static let learned = 2000
        static let everyday = 600
        /// Alternatives costing more than this over the best are odd splits (ね子 for ねこ).
        static let margin = 2500
    }

    /// Particles and other little words that stay in kana between the converted words.
    private static let functionWords: Set<String> = [
        "は", "が", "を", "に", "で", "と", "も", "の", "へ", "や", "か", "ね", "よ", "な", "わ", "ぞ", "さ", "だ", "です", "でした",
        "でしょう", "だった", "だろう", "じゃない", "ではない", "じゃありません", "ではありません", "から", "まで", "より", "けど",
        "けれど", "けれども", "ので", "のに", "って", "など", "しか", "だけ", "ばかり", "くらい", "ぐらい", "ほど", "こそ", "でも",
        "には", "では", "とは", "にも", "との", "への", "ください", "ましょう",
    ]

    /// Everyday words that written text (where the frequencies come from) undersells: 昨日 over 機能.
    private static let everyday: Set<String> = ["昨日", "何時", "今朝", "今晩", "今夜", "明後日", "一昨日"]

    private struct Edge {
        let end: Int
        let text: String
        let reading: String
        let cost: Int
        let entry: DictionaryEntry?
        var isFunction = false
    }

    private final class Node {
        let cost: Int
        let text: String
        let edge: Edge?
        let previous: Node?

        init(cost: Int, text: String, edge: Edge?, previous: Node?) {
            self.cost = cost
            self.text = text
            self.edge = edge
            self.previous = previous
        }
    }

    /// The best few conversions of the whole reading, best first.
    public func convert(_ reading: String, limit: Int = 3) -> [Conversion] {
        let kana = Array(KanaConverter.hiragana(from: reading))
        let count = kana.count
        guard count > 0, count <= 40 else { return [] }
        let keep = 6
        var nodes: [[Node]] = Array(repeating: [], count: count + 1)
        nodes[0] = [Node(cost: 0, text: "", edge: nil, previous: nil)]

        for start in 0..<count where !nodes[start].isEmpty {
            var edges = self.edges(in: kana, at: start)
            edges.append(Edge(end: start + 1, text: String(kana[start]), reading: String(kana[start]), cost: Cost.unknown, entry: nil))
            for edge in edges {
                for from in nodes[start] {
                    var cost = from.cost + edge.cost
                    if edge.isFunction && start == 0 && edge.end < count {
                        cost += Cost.startParticle
                    }
                    if edge.isFunction && from.edge?.isFunction == true {
                        cost += Cost.particlePair
                    }
                    let text = from.text + edge.text
                    var list = nodes[edge.end]
                    if let same = list.firstIndex(where: { $0.text == text }) {
                        if list[same].cost <= cost { continue }
                        list.remove(at: same)
                    }
                    list.append(Node(cost: cost, text: text, edge: edge, previous: from))
                    list.sort { $0.cost < $1.cost }
                    if list.count > keep {
                        list.removeLast()
                    }
                    nodes[edge.end] = list
                }
            }
        }

        guard let best = nodes[count].first else { return [] }
        return nodes[count]
            .filter { $0 === best || $0.cost <= best.cost + Cost.margin }
            .prefix(limit)
            .map { node in
                var segments: [Segment] = []
                var current: Node? = node
                while let step = current, let edge = step.edge {
                    segments.insert(Segment(reading: edge.reading, text: edge.text, entry: edge.entry), at: 0)
                    current = step.previous
                }
                return Conversion(text: node.text, segments: segments, cost: node.cost)
            }
    }

    /// Words for the start of a phrase, to convert it one part at a time (箸 | をたべる): the
    /// best conversion's first word and its homophones first, then other lengths. Empty when
    /// the best conversion is a single word.
    public func firstWords(of reading: String, best: Conversion?, limit: Int = 5) -> [Segment] {
        guard let best, best.segments.count >= 2, let first = best.segments.first else { return [] }
        let kana = Array(KanaConverter.hiragana(from: reading))
        let firstEnd = first.reading.count
        let edges = edges(in: kana, at: 0)
            .filter { $0.end < kana.count && $0.text != $0.reading && ($0.end == firstEnd || $0.end >= 2) }
            .sorted { lhs, rhs in
                let lhsFirst = lhs.end == firstEnd, rhsFirst = rhs.end == firstEnd
                if lhsFirst != rhsFirst { return lhsFirst }
                if lhs.end != rhs.end { return lhs.end > rhs.end }
                return lhs.cost < rhs.cost
            }
        var seen: Set<String> = []
        var result: [Segment] = []
        for edge in edges where result.count < limit && seen.insert(edge.text).inserted {
            result.append(Segment(reading: edge.reading, text: edge.text, entry: edge.entry))
        }
        return result
    }

    // MARK: - Words at a position

    private func wordCost(_ index: Int) -> Int {
        let entry = dictionary.entries[index]
        return 2500 + Int((500 * log10(Double(index + 10))).rounded()) - (Self.everyday.contains(entry.kanji) ? Cost.everyday : 0)
    }

    private func learned(_ reading: String, _ text: String) -> Bool {
        history?.choices(for: reading).contains(text) ?? false
    }

    private func edges(in kana: [Character], at start: Int) -> [Edge] {
        var result: [Edge] = []
        func add(_ end: Int, _ text: String, _ reading: String, _ cost: Int, _ entry: DictionaryEntry?, isFunction: Bool = false) {
            var edge = Edge(end: end, text: text, reading: reading, cost: cost - (learned(reading, text) ? Cost.learned : 0), entry: entry)
            edge.isFunction = isFunction
            result.append(edge)
        }
        func addForms(of index: Int, stemEnd: Int) {
            let entry = dictionary.entries[index]
            let rest = String(kana[stemEnd..<min(stemEnd + 12, kana.count)])
            let stem = String(kana[start..<stemEnd])
            for ending in Conjugation.endings(for: entry.conjugation) where rest.hasPrefix(ending) {
                let reading = stem + ending
                add(stemEnd + ending.count, Conjugation.written(entry, ending: ending, reading: reading), reading,
                    wordCost(index) + Cost.inflected, entry)
            }
        }

        let longest = min(16, kana.count - start)
        guard longest > 0 else { return [] }
        for length in 1...longest {
            let piece = String(kana[start..<start + length])
            for index in dictionary.entryIndexes(reading: piece).sorted() {
                let entry = dictionary.entries[index]
                add(start + length, entry.word, piece, wordCost(index) + (length == 1 ? Cost.singleKana : 0), entry)
            }
            if Self.functionWords.contains(piece) {
                add(start + length, piece, piece, Cost.function, nil, isFunction: true)
            }
            for index in dictionary.entryIndexes(stem: piece) {
                addForms(of: index, stemEnd: start + length)
            }
        }
        for index in dictionary.emptyStemEntries {
            addForms(of: index, stemEnd: start)
        }
        return result
    }
}
