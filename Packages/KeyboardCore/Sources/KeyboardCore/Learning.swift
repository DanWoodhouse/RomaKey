import Foundation

/// Where learned data is kept. The keyboards use the App Group (with Full Access) or their own
/// storage, so nothing ever leaves the phone. Tests use an in-memory store.
public protocol KeyValueStore: AnyObject {
    func dictionary(forKey key: String) -> [String: Any]?
    func stringArray(forKey key: String) -> [String]?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: KeyValueStore {}

/// A store that forgets everything, for tests and previews.
public final class MemoryStore: KeyValueStore {
    private var values: [String: Any] = [:]

    public init() {}

    public func dictionary(forKey key: String) -> [String: Any]? { values[key] as? [String: Any] }
    public func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    public func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// English words the user types, so they're suggested and never "corrected" away.
public final class LearnedWords {
    private static let key = "learnedWords"
    private static let capacity = 3000

    private let store: KeyValueStore
    private var counts: [String: Int]

    public init(store: KeyValueStore) {
        self.store = store
        counts = store.dictionary(forKey: Self.key) as? [String: Int] ?? [:]
    }

    public func contains(_ word: String) -> Bool {
        counts[word.lowercased()] != nil
    }

    public func learn(_ word: String) {
        let word = word.lowercased()
        guard word.count >= 2, word.allSatisfy({ $0.isLetter || $0 == "'" }) else { return }
        counts[word, default: 0] += 1
        if counts.count > Self.capacity {
            // Forget the least-used words.
            for (old, _) in counts.sorted(by: { $0.value < $1.value }).prefix(counts.count - Self.capacity) {
                counts.removeValue(forKey: old)
            }
        }
        store.set(counts, forKey: Self.key)
    }

    public func forget(_ word: String) {
        counts.removeValue(forKey: word.lowercased())
        store.set(counts, forKey: Self.key)
    }

    /// Learned words starting with `prefix`, most used first.
    public func completions(for prefix: String, limit: Int = 3) -> [String] {
        let prefix = prefix.lowercased()
        return counts
            .filter { $0.key.hasPrefix(prefix) && $0.key != prefix }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit)
            .map(\.key)
    }

    public func reset() {
        counts = [:]
        store.set(nil, forKey: Self.key)
    }
}

/// Which word the user picks for each reading (きかい → 機会 rather than 機械), so their
/// usual choice comes first next time.
public final class ConversionHistory {
    private static let key = "conversionHistory"
    private static let capacity = 2000

    private let store: KeyValueStore
    /// reading → [word, most recent first]
    private var choices: [String: [String]]
    /// Readings, most recently used last, for trimming.
    private var order: [String]

    public init(store: KeyValueStore) {
        self.store = store
        let saved = store.dictionary(forKey: Self.key) as? [String: [String]] ?? [:]
        choices = saved
        order = store.stringArray(forKey: Self.key + ".order") ?? Array(saved.keys)
    }

    /// Changes whenever a choice is recorded or forgotten, so remembered conversions are redone.
    public private(set) var revision = 0

    public func record(reading: String, word: String) {
        // Kana is remembered too, so a word kept in kana isn't converted automatically.
        guard !reading.isEmpty else { return }
        revision += 1
        var words = choices[reading] ?? []
        words.removeAll { $0 == word }
        words.insert(word, at: 0)
        choices[reading] = Array(words.prefix(5))
        order.removeAll { $0 == reading }
        order.append(reading)
        if order.count > Self.capacity {
            for old in order.prefix(order.count - Self.capacity) {
                choices.removeValue(forKey: old)
            }
            order.removeFirst(order.count - Self.capacity)
        }
        store.set(choices, forKey: Self.key)
        store.set(order, forKey: Self.key + ".order")
    }

    /// Words previously picked for `reading`, most recent first.
    public func choices(for reading: String) -> [String] {
        choices[reading] ?? []
    }

    public func reset() {
        revision += 1
        choices = [:]
        order = []
        store.set(nil, forKey: Self.key)
        store.set(nil, forKey: Self.key + ".order")
    }
}

/// Recently used emoji and kaomoji, newest first.
public final class RecentEmoji {
    private static let key = "recentEmoji"
    private let store: KeyValueStore
    public private(set) var items: [String]

    public init(store: KeyValueStore) {
        self.store = store
        items = store.stringArray(forKey: Self.key) ?? []
    }

    public func use(_ item: String) {
        items.removeAll { $0 == item }
        items.insert(item, at: 0)
        items = Array(items.prefix(32))
        store.set(items, forKey: Self.key)
    }
}
