import Foundation

/// The rest of JMdict, for kanji conversion: about 130,000 rarer words (背徳, 背徳感) that the
/// main dictionary leaves out, each with its part of speech and a short meaning.
///
/// The file is memory-mapped rather than loaded: iOS reads its pages as lookups touch them and
/// can drop them again, so it doesn't count against the keyboard's small memory limit. Readings
/// are found by binary search. The layout is described in `tools/build_dictionary.py`.
public final class ExtendedLexicon {
    public struct Word: Hashable {
        public let text: String
        /// How common the word is in everyday text: 0 (most) to 8.
        public let band: Int
        public let entry: DictionaryEntry
    }

    private let data: Data
    private let count: Int
    private let textStart: Int
    /// The longest reading, in characters.
    public let longestReading: Int

    private static let headerSize = 16

    public init?(data: Data) {
        guard data.count >= Self.headerSize, data.prefix(4) == Data("RKLX".utf8) else { return nil }
        func number(at offset: Int) -> Int {
            data.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt32.self))) }
        }
        guard number(at: 4) == 1 else { return nil }
        count = number(at: 8)
        longestReading = number(at: 12)
        textStart = Self.headerSize + 4 * count
        guard count > 0, data.count > textStart else { return nil }
        self.data = data
    }

    /// The bundled lexicon, memory-mapped.
    public static func bundled() -> ExtendedLexicon? {
        guard let url = CoreResources.url("lexicon", "bin"),
              let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        return ExtendedLexicon(data: data)
    }

    /// The words read exactly `reading` (hiragana), most common first, and whether any longer
    /// reading starts with it: when none does, there's no point looking further along.
    public func lookup(_ reading: String) -> (words: [Word], continues: Bool) {
        let key = Array(reading.utf8)
        guard !key.isEmpty else { return ([], true) }
        return data.withUnsafeBytes { raw -> ([Word], Bool) in
            let bytes = raw.bindMemory(to: UInt8.self)
            func start(of line: Int) -> Int {
                textStart + Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: Self.headerSize + 4 * line, as: UInt32.self)))
            }
            /// The line's reading against the key: -1, 0 or 1, and whether the key is a prefix of it.
            func compare(_ line: Int) -> (order: Int, hasPrefix: Bool) {
                let base = start(of: line)
                var index = 0
                while true {
                    let byte = base + index < bytes.count ? bytes[base + index] : 0x09
                    let lineEnded = byte == 0x09
                    if index == key.count {
                        return (lineEnded ? 0 : 1, true)
                    }
                    if lineEnded || byte < key[index] { return (-1, false) }
                    if byte > key[index] { return (1, false) }
                    index += 1
                }
            }
            var low = 0
            var high = count - 1
            while low <= high {
                let middle = (low + high) / 2
                let (order, _) = compare(middle)
                if order == 0 {
                    let continues = middle + 1 < count && compare(middle + 1).hasPrefix
                    return (words(at: start(of: middle), in: bytes), continues)
                }
                if order < 0 {
                    low = middle + 1
                } else {
                    high = middle - 1
                }
            }
            // Not found: `low` is where it would go, so the next line shows whether a longer
            // reading starts with it.
            return ([], low < count && compare(low).hasPrefix)
        }
    }

    public func words(reading: String) -> [Word] {
        lookup(reading).words
    }

    private func words(at base: Int, in bytes: UnsafeBufferPointer<UInt8>) -> [Word] {
        var end = base
        while end < bytes.count && bytes[end] != 0x0A {
            end += 1
        }
        let line = String(decoding: UnsafeBufferPointer(rebasing: bytes[base..<end]), as: UTF8.self)
        let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard let reading = parts.first.map(String.init) else { return [] }
        return parts.dropFirst().compactMap { part in
            let fields = part.split(separator: "\u{1F}", omittingEmptySubsequences: false)
            guard fields.count == 4 else { return nil }
            let text = String(fields[0])
            let entry = DictionaryEntry(kanji: text, reading: reading, usuallyKana: false, partOfSpeech: String(fields[2]),
                                        sensesText: String(fields[3]), conjugation: "")
            return Word(text: text, band: Int(fields[1]) ?? 8, entry: entry)
        }
    }
}
