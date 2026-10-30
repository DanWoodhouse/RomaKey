import KeyboardCore
import UIKit

final class KanaKeyboardViewController: KeyboardHostController {
    private let engine = FlickKeyboardEngine()

    override func makeContentView() -> KeyboardContentView {
        engine.output = textOutput
        return FlickKeyboardView(engine: engine, globeTarget: self)
    }
}
