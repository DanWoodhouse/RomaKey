/// Where the engines send text. The keyboard extensions forward these to `UITextDocumentProxy`.
public protocol TextOutput: AnyObject {
    func insertText(_ text: String)
    func deleteBackward()
    func setMarkedText(_ text: String)
    func unmarkText()
    func moveCursor(by offset: Int)
}

public enum KeyLabel: Equatable {
    case text(String)
    /// SF Symbol name.
    case systemImage(String)
}

extension TextOutput {
    /// Shows the in-progress composition as underlined (marked) text.
    func show(_ composer: RomajiComposer) {
        if composer.isEmpty {
            setMarkedText("")
            unmarkText()
        } else {
            setMarkedText(composer.displayText)
        }
    }

    /// Replaces the marked text with `text` and confirms it.
    func commit(_ text: String) {
        setMarkedText(text)
        unmarkText()
    }
}

extension RomajiComposer {
    /// Conversion choices for the current composition (kanji conversion will go here later).
    public var candidates: [String] {
        guard !isEmpty else { return [] }
        let hiragana = finalizedText
        let katakana = KanaConverter.katakana(from: hiragana)
        return katakana == hiragana ? [hiragana] : [hiragana, katakana]
    }
}
