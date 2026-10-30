import KeyboardCore
import UIKit

final class KanaKeyboardViewController: KeyboardHostController {
    private let engine = FlickKeyboardEngine()

    override func makeContentView() -> KeyboardViewBase {
        engine.output = textOutput
        return FlickKeyboardView(engine: engine, globeTarget: self, feedback: feedback)
    }

    override func dictionaryDidLoad(_ dictionary: JapaneseDictionary?) {
        engine.dictionary = dictionary
    }
}
