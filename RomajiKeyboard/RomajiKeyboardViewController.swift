import KeyboardCore
import UIKit

final class RomajiKeyboardViewController: KeyboardHostController {
    private let engine = KeyboardEngine(mode: .japanese)

    override func makeContentView() -> KeyboardContentView {
        engine.output = textOutput
        return RomajiKeyboardView(engine: engine, globeTarget: self)
    }
}
