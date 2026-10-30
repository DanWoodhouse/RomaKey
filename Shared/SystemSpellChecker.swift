import KeyboardCore
import UIKit

/// Apple's built-in spell checker (`UITextChecker`), on device, in the user's English variant.
final class SystemSpellChecker: SpellChecking {
    private let checker = UITextChecker()
    private let language: String

    init() {
        // Prefer the user's own English (en_GB spells "colour"), else US English.
        let available = UITextChecker.availableLanguages
        let preferred = Locale.preferredLanguages
            .map { $0.replacingOccurrences(of: "-", with: "_") }
            .first { $0.hasPrefix("en") && available.contains($0) }
        language = preferred ?? (available.contains("en_GB") && Locale.current.region?.identifier == "GB" ? "en_GB" : "en_US")
    }

    func isKnown(_ word: String) -> Bool {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.rangeOfMisspelledWord(in: word, range: range, startingAt: 0, wrap: false, language: language).location == NSNotFound
    }

    func corrections(for word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.guesses(forWordRange: range, in: word, language: language) ?? []
    }

    func completions(for prefix: String) -> [String] {
        let range = NSRange(location: 0, length: (prefix as NSString).length)
        return checker.completions(forPartialWordRange: range, in: prefix, language: language) ?? []
    }
}

/// Text in the search field while searching emoji or GIFs: the keyboard's engine types into
/// this instead of the document.
final class SearchBuffer: TextOutput {
    private(set) var text = ""
    private(set) var marked = ""
    var onChange: (() -> Void)?
    /// Return was pressed.
    var onSubmit: (() -> Void)?

    var query: String { (text + marked).trimmingCharacters(in: .whitespaces) }

    func reset() {
        text = ""
        marked = ""
    }

    func insertText(_ newText: String) {
        if newText.contains("\n") {
            onSubmit?()
            return
        }
        text += newText
        onChange?()
    }

    func deleteBackward() {
        if !text.isEmpty {
            text.removeLast()
        }
        onChange?()
    }

    func setMarkedText(_ newText: String) {
        marked = newText
        onChange?()
    }

    func unmarkText() {
        text += marked
        marked = ""
        onChange?()
    }

    func moveCursor(by offset: Int) {}

    var textBeforeCursor: String? { text + marked }
}
