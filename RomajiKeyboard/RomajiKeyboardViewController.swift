import KeyboardCore
import UIKit

final class RomajiKeyboardViewController: KeyboardHostController {
    private let engine = KeyboardEngine(mode: .japanese)

    override func makeContentView() -> KeyboardViewBase {
        engine.output = textOutput
        engine.onModeChange = { [weak self] mode in
            guard let defaults = self?.sharedDefaults else { return }
            KeyboardSettings.saveLastUsedMode(mode, to: defaults)
        }
        engine.history = ConversionHistory(store: learningStore)
        engine.suggester = WordSuggester(checker: SystemSpellChecker(), learned: LearnedWords(store: learningStore))
        return RomajiKeyboardView(engine: engine, globeTarget: self, feedback: feedback)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The user's iOS text replacements (omw → On my way!) and contact names, so names are never "corrected".
        requestSupplementaryLexicon { [weak self] lexicon in
            var replacements: [String: String] = [:]
            var known: Set<String> = []
            for entry in lexicon.entries {
                if entry.userInput.caseInsensitiveCompare(entry.documentText) == .orderedSame {
                    known.insert(entry.documentText.lowercased())
                } else {
                    replacements[entry.userInput.lowercased()] = entry.documentText
                }
            }
            self?.engine.suggester?.textReplacements = replacements
            self?.engine.suggester?.knownWords = known
        }
    }

    override func dictionaryDidLoad(_ dictionary: JapaneseDictionary?) {
        engine.dictionary = dictionary
    }

    override func emojiDidLoad(_ catalog: EmojiCatalog?) {
        engine.emojiCatalog = catalog
    }

    override func resetLearning() {
        engine.suggester?.learned.reset()
        engine.history?.reset()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.setMode(settings.initialMode)
    }
}
