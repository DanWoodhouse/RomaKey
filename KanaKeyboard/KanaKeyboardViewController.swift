/// かな in Settings: the same keyboard, opening on the flick board, for handing the phone to
/// someone who types that way.
final class KanaKeyboardViewController: KeyboardHostController {
    override var openingBoard: Board { .kana }
}
