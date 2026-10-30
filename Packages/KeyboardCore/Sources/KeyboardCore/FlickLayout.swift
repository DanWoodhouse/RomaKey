/// The 12-key flick keyboard (フリック入力), laid out like the iPhone's built-in 日本語かな keyboard.
public enum FlickPage: Equatable {
    case kana
    case alphabet
    case numbers
}

public enum FlickDirection: Hashable, CaseIterable {
    case center
    case left
    case up
    case right
    case down

    /// Picks a direction from how far the finger has moved since touching down.
    public init(dx: Double, dy: Double, threshold: Double = 20) {
        guard dx * dx + dy * dy >= threshold * threshold else {
            self = .center
            return
        }
        if abs(dx) > abs(dy) {
            self = dx < 0 ? .left : .right
        } else {
            self = dy < 0 ? .up : .down
        }
    }
}

public struct FlickKey: Hashable {
    public let label: String
    public let outputs: [FlickDirection: String]
    /// What repeated taps step through (あ → い → う …). Starts with the centre output.
    public let cycle: [String]

    /// `flicks` lists the outputs for centre, left, up, right, down; it may stop early.
    init(_ label: String, _ flicks: String, cycle: String? = nil) {
        self.label = label
        var outputs: [FlickDirection: String] = [:]
        for (direction, character) in zip(FlickDirection.allCases, flicks) {
            outputs[direction] = String(character)
        }
        self.outputs = outputs
        self.cycle = (cycle ?? flicks).map(String.init)
    }
}

public enum FlickKeyKind: Hashable {
    case flick(FlickKey)
    /// → : ends a tap cycle so the same kana can be typed twice (ああ), or moves the cursor.
    case advance
    /// ↺ : steps a tap cycle backwards.
    case reverseCycle
    /// あいう → ABC → ☆123
    case pageCycle
    /// Where 🌐 sits on the system's かな keyboard. Tap to go back to the ローマ字 board, or press
    /// and drag for the same mode wheel as the ローマ字 board.
    case modeKey
    /// ゛゜小 : cycles the last kana through dakuten, handakuten and small forms.
    case modifier
    /// a/A : flips the case of the last letter.
    case caseToggle
    case delete
    case space
    case returnKey
}

public struct FlickCell: Hashable {
    public let kind: FlickKeyKind
    public let column: Int
    public let row: Int
    public let rowSpan: Int
}

public struct FlickLayout: Hashable {
    /// Relative widths of the five columns. The outer columns hold the function keys.
    public static let columnWeights: [Double] = [1, 1.2, 1.2, 1.2, 1]
    public static let rowCount = 4

    public let cells: [FlickCell]

    public static func layout(for page: FlickPage) -> FlickLayout {
        var cells = [
            FlickCell(kind: .advance, column: 0, row: 0, rowSpan: 1),
            FlickCell(kind: .reverseCycle, column: 0, row: 1, rowSpan: 1),
            FlickCell(kind: .pageCycle, column: 0, row: 2, rowSpan: 1),
            FlickCell(kind: .modeKey, column: 0, row: 3, rowSpan: 1),
            FlickCell(kind: .delete, column: 4, row: 0, rowSpan: 1),
            FlickCell(kind: .space, column: 4, row: 1, rowSpan: 1),
            FlickCell(kind: .returnKey, column: 4, row: 2, rowSpan: 2),
        ]
        for (row, kinds) in centerKeys(for: page).enumerated() {
            for (index, kind) in kinds.enumerated() {
                cells.append(FlickCell(kind: kind, column: index + 1, row: row, rowSpan: 1))
            }
        }
        return FlickLayout(cells: cells)
    }

    /// One frame per cell, in the same order as `cells`.
    public func frames(width: Double, rowHeight: Double) -> [KeyFrame] {
        let totalWeight = Self.columnWeights.reduce(0, +)
        var columnX = [0.0]
        for weight in Self.columnWeights {
            columnX.append(columnX.last! + weight / totalWeight * width)
        }
        return cells.map { cell in
            KeyFrame(
                x: columnX[cell.column],
                y: Double(cell.row) * rowHeight,
                width: columnX[cell.column + 1] - columnX[cell.column],
                height: Double(cell.rowSpan) * rowHeight
            )
        }
    }

    private static func centerKeys(for page: FlickPage) -> [[FlickKeyKind]] {
        switch page {
        case .kana:
            return [
                [.flick(FlickKey("あ", "あいうえお", cycle: "あいうえおぁぃぅぇぉ")),
                 .flick(FlickKey("か", "かきくけこ")),
                 .flick(FlickKey("さ", "さしすせそ"))],
                [.flick(FlickKey("た", "たちつてと", cycle: "たちつてとっ")),
                 .flick(FlickKey("な", "なにぬねの")),
                 .flick(FlickKey("は", "はひふへほ"))],
                [.flick(FlickKey("ま", "まみむめも")),
                 .flick(FlickKey("や", "や（ゆ）よ", cycle: "やゆよゃゅょ")),
                 .flick(FlickKey("ら", "らりるれろ"))],
                [.modifier,
                 .flick(FlickKey("わ", "わをんー", cycle: "わをんゎー")),
                 .flick(FlickKey("、。?!", "、。？！…"))],
            ]
        case .alphabet:
            return [
                [.flick(FlickKey("@#/&_", "@#/&_")),
                 .flick(FlickKey("ABC", "abc", cycle: "abcABC")),
                 .flick(FlickKey("DEF", "def", cycle: "defDEF"))],
                [.flick(FlickKey("GHI", "ghi", cycle: "ghiGHI")),
                 .flick(FlickKey("JKL", "jkl", cycle: "jklJKL")),
                 .flick(FlickKey("MNO", "mno", cycle: "mnoMNO"))],
                [.flick(FlickKey("PQRS", "pqrs", cycle: "pqrsPQRS")),
                 .flick(FlickKey("TUV", "tuv", cycle: "tuvTUV")),
                 .flick(FlickKey("WXYZ", "wxyz", cycle: "wxyzWXYZ"))],
                [.caseToggle,
                 .flick(FlickKey("'\"()", "'\"()")),
                 .flick(FlickKey(".,?!", ".,?!"))],
            ]
        case .numbers:
            return [
                [.flick(FlickKey("1", "1☆♪→")),
                 .flick(FlickKey("2", "2¥$€")),
                 .flick(FlickKey("3", "3%°#"))],
                [.flick(FlickKey("4", "4○*・")),
                 .flick(FlickKey("5", "5+×÷")),
                 .flick(FlickKey("6", "6<=>"))],
                [.flick(FlickKey("7", "7「」:")),
                 .flick(FlickKey("8", "8〒々〆")),
                 .flick(FlickKey("9", "9^|\\"))],
                [.flick(FlickKey("()[]", "()[]")),
                 .flick(FlickKey("0", "0〜…")),
                 .flick(FlickKey(".,-/", ".,-/"))],
            ]
        }
    }
}
