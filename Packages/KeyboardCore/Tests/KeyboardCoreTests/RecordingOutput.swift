@testable import KeyboardCore

/// Stands in for the host app's text field. Ignores cursor position except for `cursorMoves`.
final class RecordingOutput: TextOutput {
    var committed = ""
    var marked = ""
    var cursorMoves = 0

    func insertText(_ text: String) { committed += text }
    func deleteBackward() { if !committed.isEmpty { committed.removeLast() } }
    func setMarkedText(_ text: String) { marked = text }
    func unmarkText() {
        committed += marked
        marked = ""
    }
    func moveCursor(by offset: Int) { cursorMoves += offset }
}
