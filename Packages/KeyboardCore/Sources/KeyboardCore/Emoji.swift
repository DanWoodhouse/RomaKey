import Foundation

public enum EmojiGroup: Int, CaseIterable {
    case smileys = 0
    case people = 1
    case animals = 3
    case food = 4
    case travel = 5
    case activities = 6
    case objects = 7
    case symbols = 8
    case flags = 9

    /// The section heading in the emoji panel.
    public var name: String {
        switch self {
        case .smileys: return "スマイリー · Smileys"
        case .people: return "人 · People"
        case .animals: return "動物と自然 · Animals & nature"
        case .food: return "食べ物 · Food & drink"
        case .travel: return "旅行と場所 · Travel & places"
        case .activities: return "アクティビティ · Activities"
        case .objects: return "物 · Objects"
        case .symbols: return "記号 · Symbols"
        case .flags: return "旗 · Flags"
        }
    }

    /// The tab icon.
    public var icon: String {
        switch self {
        case .smileys: return "😀"
        case .people: return "👋"
        case .animals: return "🐱"
        case .food: return "🍙"
        case .travel: return "🚃"
        case .activities: return "⚽️"
        case .objects: return "💡"
        case .symbols: return "💕"
        case .flags: return "🏳️"
        }
    }
}

public struct Emoji: Hashable {
    public let character: String
    public let group: EmojiGroup
    /// Unicode emoji version, to hide emoji the phone can't draw yet.
    public let version: Double
    /// Light to dark, when the emoji has skin tones.
    public let skinTones: [String]
    let englishName: String
    let japaneseName: String
    let englishKeywords: [String]
    let japaneseKeywords: [String]

    /// Lower is a better match for `keyword`: emoji whose name contains it (🐕 "dog") beat ones
    /// only tagged with it (🦴 "bone"), and shorter names beat longer ones (🐈 "cat" before 🐱 "cat face").
    func relevance(for keyword: String) -> Int {
        let isJapanese = AIText.containsJapanese(keyword)
        let name = isJapanese ? KanaConverter.hiragana(from: japaneseName) : englishName
        let inName = isJapanese
            ? name.contains(keyword)
            : name.split { $0 == " " || $0 == ":" || $0 == "," }.contains { $0 == keyword }
        return (inName ? 0 : 1000) + name.count
    }

    /// This emoji in skin tone 1–5, or the default yellow for 0.
    public func withSkinTone(_ tone: Int) -> String {
        guard (1...5).contains(tone), skinTones.count == 5 else { return character }
        return skinTones[tone - 1]
    }
}

/// Every emoji, grouped and searchable in English and Japanese (including hiragana readings,
/// so ねこ finds 🐱). Built from emojibase-data by tools/build_emoji.py.
public final class EmojiCatalog {
    public let emoji: [Emoji]
    /// Keyword → indexes into `emoji`, best match first.
    private let index: [String: [Int]]
    private let sortedKeywords: [String]

    /// `maxVersion` hides emoji newer than the phone's emoji font.
    public init(tsv: String, maxVersion: Double = .infinity) {
        var emoji: [Emoji] = []
        var index: [String: [Int]] = [:]
        for line in tsv.split(separator: "\n") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 8,
                  let groupNumber = Int(fields[1]), let group = EmojiGroup(rawValue: groupNumber),
                  let version = Double(fields[2]), version <= maxVersion else { continue }
            let item = Emoji(
                character: fields[0],
                group: group,
                version: version,
                skinTones: fields[3].split(separator: " ").map(String.init),
                englishName: fields[4],
                japaneseName: fields[6],
                englishKeywords: fields[5].split(separator: " ").map(String.init),
                japaneseKeywords: fields[7].split(separator: " ").map { KanaConverter.hiragana(from: String($0)) }
            )
            let position = emoji.count
            emoji.append(item)
            for keyword in item.englishKeywords + item.japaneseKeywords where index[keyword]?.last != position {
                index[keyword, default: []].append(position)
            }
        }
        // Best match first for every keyword; Unicode's order breaks ties.
        for (keyword, positions) in index {
            index[keyword] = positions.sorted {
                let left = emoji[$0].relevance(for: keyword), right = emoji[$1].relevance(for: keyword)
                return left != right ? left < right : $0 < $1
            }
        }
        // Hand-picked favourites for everyday words, where names alone pick oddly (love → 🏩).
        for (keyword, favourites) in Self.favourites {
            let positions = favourites.compactMap { favourite in emoji.firstIndex { $0.character == favourite } }
            index[keyword] = positions + (index[keyword] ?? []).filter { !positions.contains($0) }
        }
        self.emoji = emoji
        self.index = index
        sortedKeywords = index.keys.sorted()
    }

    private static let favourites: [String: [String]] = [
        "love": ["❤️", "🥰", "😍"], "あい": ["❤️", "🥰"], "すき": ["❤️", "😍", "🥰"], "だいすき": ["❤️", "😍"],
        "happy": ["😊", "😀", "🥳"], "うれしい": ["😊", "😆"],
        "sad": ["😢", "😭", "😞"], "かなしい": ["😢", "😭"],
        "laugh": ["😂", "🤣"], "lol": ["😂", "🤣"], "わらう": ["😂", "🤣"], "わら": ["😂", "🤣"],
        "thanks": ["🙏", "😊"], "thank": ["🙏"], "ありがとう": ["🙏", "😊"],
        "sorry": ["🙇", "😢"], "ごめん": ["🙇", "🙏"], "ごめんなさい": ["🙇", "🙏"],
        "ok": ["👌", "👍", "🆗"], "おっけー": ["👌", "👍"], "いいね": ["👍", "❤️"],
        "japan": ["🇯🇵", "🗾"], "にほん": ["🇯🇵", "🗾"], "にっぽん": ["🇯🇵", "🗾"],
        "good": ["👍", "😊"], "yes": ["👍", "🙆"], "no": ["🙅", "👎"], "party": ["🎉", "🥳"],
        "おめでとう": ["🎉", "🎊"], "congratulations": ["🎉", "🥳"], "birthday": ["🎂", "🎉"],
        "tired": ["😴", "😩"], "つかれた": ["😩", "😴"], "おやすみ": ["😴", "🌙"], "night": ["🌙", "😴"],
        "hot": ["🥵", "🔥"], "あつい": ["🥵", "🔥"], "cold": ["🥶", "❄️"], "さむい": ["🥶", "❄️"],
        "angry": ["😠", "😡"], "おこ": ["😠", "💢"], "beer": ["🍺", "🍻"], "coffee": ["☕"],
    ]

    public static func bundled(maxVersion: Double = .infinity) -> EmojiCatalog? {
        guard let url = CoreResources.url("emoji", "tsv"),
              let tsv = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return EmojiCatalog(tsv: tsv, maxVersion: maxVersion)
    }

    public func emoji(in group: EmojiGroup) -> [Emoji] {
        emoji.filter { $0.group == group }
    }

    /// Emoji for a word just typed: exact keyword matches only (cat → 🐱, ねこ → 🐱), for the candidate bar.
    public func suggestions(for word: String, limit: Int = 3) -> [Emoji] {
        let key = Self.key(word)
        guard key.count >= 2 || AIText.containsJapanese(key) else { return [] }
        return (index[key] ?? []).prefix(limit).map { emoji[$0] }
    }

    /// Search as you type: exact keyword matches first, then keywords that start with the query.
    public func search(_ query: String, limit: Int = 60) -> [Emoji] {
        let words = query.split(separator: " ").map { Self.key(String($0)) }.filter { !$0.isEmpty }
        guard !words.isEmpty else { return [] }
        // Every word must match a keyword exactly (2 points) or as a prefix (1 point). Ties are
        // broken by how well the first word matched (its keyword's best-first order).
        var scores: [Int: (points: Int, rank: Int)]?
        for word in words {
            var matches: [Int: (points: Int, rank: Int)] = [:]
            for (rank, item) in (index[word] ?? []).enumerated() {
                matches[item] = (2, rank)
            }
            for keyword in Self.keywords(in: sortedKeywords, withPrefix: word) where keyword != word {
                for (rank, item) in (index[keyword] ?? []).enumerated() where matches[item] == nil {
                    matches[item] = (1, 10_000 + rank)
                }
            }
            if let previous = scores {
                var combined: [Int: (points: Int, rank: Int)] = [:]
                for (item, score) in previous {
                    if let match = matches[item] {
                        combined[item] = (score.points + match.points, score.rank)
                    }
                }
                scores = combined
            } else {
                scores = matches
            }
        }
        return (scores ?? [:])
            .sorted { ($0.value.points, -$0.value.rank, -$0.key) > ($1.value.points, -$1.value.rank, -$1.key) }
            .prefix(limit)
            .map { emoji[$0.key] }
    }

    /// The newest emoji version the phone can draw, from its iOS version.
    public static func maxSupportedVersion(iOSMajor major: Int, minor: Int) -> Double {
        switch (major, minor) {
        case (27..., _), (26, 4...): return 17.0
        case (18, 4...), (19...26, _): return 16.0
        case (17, 4...), (18, _): return 15.1
        case (16, 4...), (17, _): return 15.0
        default: return 14.0
        }
    }

    private static func key(_ word: String) -> String {
        KanaConverter.hiragana(from: word.lowercased().trimmingCharacters(in: .punctuationCharacters))
    }

    private static func keywords(in sorted: [String], withPrefix prefix: String, limit: Int = 200) -> ArraySlice<String> {
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < prefix { low = middle + 1 } else { high = middle }
        }
        var end = low
        while end < sorted.count && end - low < limit && sorted[end].hasPrefix(prefix) {
            end += 1
        }
        return sorted[low..<end]
    }
}
