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

    /// Shown in the candidate bar while the dictionary is still loading.
    public var loadingMessage: String? {
        isComposing && dictionary == nil ? "辞書を読み込み中… · Loading dictionary…" : nil
    }

    /// Words picked for each reading before, so they come first.
    public var history: ConversionHistory?
    /// Predictive text. Loaded in the background; until then there are no predictions.
    public var predictor: NextWordPredictor? {
        didSet { onChange?() }
    }
    private var predictionContext = JapanesePredictionContext()
    public var emojiCatalog: EmojiCatalog? {
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

    /// Switches straight to a page, e.g. back to かな when the board is picked from the mode wheel.
    public func setPage(_ newPage: FlickPage) {
        commitComposition()
        toggle = nil
        lastDirect = nil
        page = newPage
        onChange?()
    }
    public var isComposing: Bool { !composer.isEmpty }

    /// Live conversion is off while typing goes into an emoji or GIF search.
    public var convertsAutomatically = true

    /// What the composition shows, and what 確定 or space confirms: with live conversion on,
    /// the words the keyboard is sure of are already in kanji (たべた → 食べた).
    private func liveText(_ text: String, converting kana: String) -> String {
        guard settings.liveConversion, convertsAutomatically, let dictionary, !kana.isEmpty else { return text }
        let converted = KanaKanjiConverter(dictionary: dictionary, history: history).liveConversion(kana)
        return converted + text.dropFirst(kana.count)
    }

    /// The text 確定 or space confirms.
    private var committedText: String {
        let finalized = composer.finalizedText
        return liveText(finalized, converting: finalized)
    }

    private func showComposition() {
        if composer.isEmpty {
            output?.show(composer)
        } else {
            output?.setMarkedText(liveText(composer.displayText, converting: composer.kana))
        }
    }
    public var candidates: [Candidate] {
        if composer.isEmpty {
            // Straight after a word is committed: the words likely to come next.
            guard settings.predictiveText, let predictor,
                  let previous = predictionContext.previous(textBefore: output?.textBeforeCursor) else { return [] }
            return predictor.japanese(after: previous).map { Candidate($0, kind: .prediction) }
        }
        return composer.candidates(using: dictionary, history: history, emoji: settings.emojiSuggestions ? emojiCatalog : nil)
    }

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
        case .modeKey:
            break  // Handled by the keyboard, which switches boards.
        case .modifier:
            if let last = composer.kana.last, let modified = Self.modifierCycle[last] {
                composer.deleteBackward()
                composer.inputLiteral(String(modified))
                showComposition()
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
                showComposition()
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
        if let part = candidate.part, isComposing {
            // The first word of a phrase: the rest stays, to convert next.
            history?.record(reading: part, word: candidate.text)
            output?.commit(candidate.text)
            composer.removeFirst(part)
            toggle = nil
            showComposition()
            onChange?()
            return
        }
        if candidate.kind == .conversion {
            history?.record(reading: composer.finalizedText, word: candidate.text)
        }
        if candidate.kind == .prediction {
            predictionContext.compositionStarted(textBefore: output?.textBeforeCursor)
        }
        predictionContext.committed(candidate.text, predictor: predictor)
        output?.commit(candidate.text)
        composer.reset()
        toggle = nil
        onChange?()
    }

    /// Inserts a specific form of a dictionary word (kanji, hiragana or katakana).
    public func insertWord(_ text: String) {
        selectCandidate(Candidate(text))
    }

    /// Inserts text straight into the document (emoji panel, kaomoji, paste), confirming any composition first.
    public func insertDirectly(_ text: String) {
        commitComposition()
        toggle = nil
        output?.insertText(text)
        onChange?()
    }

    /// Swipe left on delete: the composition goes, then everything before the cursor that the
    /// text field shares. Returns what was removed.
    @discardableResult
    public func deleteAllBackward() -> String {
        if isComposing {
            composer.reset()
            toggle = nil
            output?.setMarkedText("")
            output?.unmarkText()
        }
        let before = output?.textBeforeCursor ?? ""
        for _ in 0..<before.count {
            output?.deleteBackward()
        }
        onChange?()
        return before
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
        let text = committedText
        predictionContext.committed(text, predictor: predictor)
        output?.commit(text)
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
        case .modeKey: return .text("かな")
        case .modifier: return .text("゛゜小")
        case .caseToggle: return .text("a/A")
        case .delete: return .systemImage("delete.left")
        case .space: return .text("空白")
        case .returnKey: return .text(isComposing ? "確定" : "改行")
        }
    }

    private func insert(_ text: String) {
        if page == .kana {
            if composer.isEmpty {
                predictionContext.compositionStarted(textBefore: output?.textBeforeCursor)
            }
            composer.inputLiteral(text)
            showComposition()
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
            showComposition()
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
