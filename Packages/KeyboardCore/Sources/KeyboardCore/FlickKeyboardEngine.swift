/// The flick keyboard's state and key handling, independent of UIKit.
///
/// Kana go into a composition (underlined until confirmed), like the romaji keyboard.
/// Letters, numbers and symbols are inserted straight into the document.
public final class FlickKeyboardEngine {
    public private(set) var page: FlickPage = .kana
    public private(set) var composer = RomajiComposer()

    public var settings = KeyboardSettings()
    /// Loaded in the background; until then there's no kanji conversion.
    public var dictionary: JapaneseDictionary? {
        didSet { onChange?() }
    }

    public weak var output: TextOutput?
    public var onChange: (() -> Void)?

    /// The key being tapped repeatedly, and where in its cycle we are.
    private var toggle: (key: FlickKey, index: Int)?
    /// The last character inserted straight into the document, for a/A.
    private var lastDirect: String?

    public init() {}

    public var layout: FlickLayout { .layout(for: page) }
    public var isComposing: Bool { !composer.isEmpty }
    public var candidates: [Candidate] { composer.candidates(using: dictionary) }

    public func press(_ kind: FlickKeyKind, direction: FlickDirection = .center) {
        // Anything other than another tap on the same key ends the tap cycle.
        let previousToggle = toggle
        let previousDirect = lastDirect
        toggle = nil
        lastDirect = nil

        switch kind {
        case .flick(let key):
            if direction != .center {
                if let text = key.outputs[direction] {
                    insert(text)
                }
            } else if !settings.flickOnly, let previousToggle, previousToggle.key == key {
                let index = (previousToggle.index + 1) % key.cycle.count
                replaceLast(with: key.cycle[index])
                toggle = (key, index)
            } else {
                insert(key.cycle[0])
                toggle = (key, 0)
            }
        case .advance:
            if previousToggle == nil && !isComposing {
                output?.moveCursor(by: 1)
            }
        case .reverseCycle:
            if let previousToggle {
                let count = previousToggle.key.cycle.count
                let index = (previousToggle.index + count - 1) % count
                replaceLast(with: previousToggle.key.cycle[index])
                toggle = (previousToggle.key, index)
            }
        case .pageCycle:
            commitComposition()
            switch page {
            case .kana: page = .alphabet
            case .alphabet: page = .numbers
            case .numbers: page = .kana
            }
        case .globe:
            break  // Handled by the system's input mode list.
        case .modifier:
            if let last = composer.kana.last, let modified = Self.modifierCycle[last] {
                composer.deleteBackward()
                composer.inputLiteral(String(modified))
                output?.show(composer)
            }
        case .caseToggle:
            if let previousDirect {
                let flipped = previousDirect == previousDirect.uppercased()
                    ? previousDirect.lowercased()
                    : previousDirect.uppercased()
                if flipped != previousDirect {
                    output?.deleteBackward()
                    output?.insertText(flipped)
                }
                lastDirect = flipped
            }
        case .delete:
            if isComposing {
                composer.deleteBackward()
                output?.show(composer)
            } else {
                output?.deleteBackward()
            }
        case .space:
            if isComposing {
                commitComposition()
            } else {
                output?.insertText(page == .kana && settings.fullWidthSpace ? "　" : " ")
            }
        case .returnKey:
            if isComposing {
                commitComposition()
            } else {
                output?.insertText("\n")
            }
        }
        onChange?()
    }

    public func selectCandidate(_ candidate: Candidate) {
        output?.commit(candidate.text)
        composer.reset()
        toggle = nil
        onChange?()
    }

    /// Inserts a specific form of a dictionary word (kanji, hiragana or katakana).
    public func insertWord(_ text: String) {
        selectCandidate(Candidate(text))
    }

    /// Space-bar trackpad: moves the cursor, confirming any composition first.
    public func moveCursor(by offset: Int) {
        commitComposition()
        toggle = nil
        output?.moveCursor(by: offset)
        onChange?()
    }

    public func commitComposition() {
        guard isComposing else { return }
        output?.commit(composer.finalizedText)
        composer.reset()
    }

    public func label(for kind: FlickKeyKind) -> KeyLabel {
        switch kind {
        case .flick(let key): return .text(key.label)
        case .advance: return .systemImage("arrow.right")
        case .reverseCycle: return .systemImage("arrow.uturn.backward")
        case .pageCycle:
            switch page {
            case .kana: return .text("ABC")
            case .alphabet: return .text("☆123")
            case .numbers: return .text("あいう")
            }
        case .globe: return .systemImage("globe")
        case .modifier: return .text("゛゜小")
        case .caseToggle: return .text("a/A")
        case .delete: return .systemImage("delete.left")
        case .space: return .text("空白")
        case .returnKey: return .text(isComposing ? "確定" : "改行")
        }
    }

    private func insert(_ text: String) {
        if page == .kana {
            composer.inputLiteral(text)
            output?.show(composer)
        } else {
            commitComposition()
            output?.insertText(text)
            lastDirect = text
        }
    }

    private func replaceLast(with text: String) {
        if page == .kana {
            composer.deleteBackward()
            composer.inputLiteral(text)
            output?.show(composer)
        } else {
            output?.deleteBackward()
            output?.insertText(text)
            lastDirect = text
        }
    }

    /// か → が → か, は → ば → ぱ → は, つ → っ → づ → つ, …
    private static let modifierCycle: [Character: Character] = {
        let groups = [
            "かが", "きぎ", "くぐ", "けげ", "こご",
            "さざ", "しじ", "すず", "せぜ", "そぞ",
            "ただ", "ちぢ", "つっづ", "てで", "とど",
            "はばぱ", "ひびぴ", "ふぶぷ", "へべぺ", "ほぼぽ",
            "あぁ", "いぃ", "うぅゔ", "えぇ", "おぉ",
            "やゃ", "ゆゅ", "よょ", "わゎ",
        ]
        var cycle: [Character: Character] = [:]
        for group in groups {
            let characters = Array(group)
            for (index, character) in characters.enumerated() {
                cycle[character] = characters[(index + 1) % characters.count]
            }
        }
        return cycle
    }()
}
