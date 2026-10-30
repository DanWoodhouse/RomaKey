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
        return RomajiKeyboardView(engine: engine, globeTarget: self, feedback: feedback)
    }

    override func dictionaryDidLoad(_ dictionary: JapaneseDictionary?) {
        engine.dictionary = dictionary
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        engine.setMode(settings.initialMode)
    }
}
