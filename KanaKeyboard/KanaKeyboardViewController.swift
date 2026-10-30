import KeyboardCore
import UIKit

final class KanaKeyboardViewController: KeyboardHostController {
    private let engine = FlickKeyboardEngine()

    override func makeContentView() -> KeyboardViewBase {
        engine.output = textOutput
        engine.history = ConversionHistory(store: learningStore)
        return FlickKeyboardView(engine: engine, globeTarget: self, feedback: feedback)
    }

    override func dictionaryDidLoad(_ dictionary: JapaneseDictionary?) {
        engine.dictionary = dictionary
    }

    override func emojiDidLoad(_ catalog: EmojiCatalog?) {
        engine.emojiCatalog = catalog
    }

    override func resetLearning() {
        engine.history?.reset()
    }
}
