import Foundation

/// The romaji (QWERTY) keyboard's state and key handling, independent of UIKit.
public final class KeyboardEngine {
    public enum ShiftState: Equatable {
        case off
        case once
        case locked
    }

    public private(set) var mode: InputMode
    public private(set) var page: KeyboardPage = .letters
    public private(set) var shift: ShiftState = .off
    public private(set) var composer = RomajiComposer()
    /// What's been typed in 辞書 mode, waiting for a word to be picked.
    public private(set) var englishQuery = ""

    /// Whether to show our own globe key. Decided by the system per device, not per language.
    public var showsGlobe: Bool {
        didSet { if showsGlobe != oldValue { onChange?() } }
    }

    public var settings = KeyboardSettings()
    /// Loaded in the background; until then there are no kanji or 辞書 results.
    public var dictionary: JapaneseDictionary? {
        didSet { onChange?() }
    }

    public weak var output: TextOutput?
    public var onChange: (() -> Void)?
    /// For remembering the last-used mode.
    public var onModeChange: ((InputMode) -> Void)?

    private let now: () -> Date
    private var lastShiftTap: Date?
    /// Shift was turned on by auto-capitalisation rather than by the user.
    private var shiftIsAutomatic = false
    private var lastKeyWasSpace = false
    private static let doubleTapInterval: TimeInterval = 0.35

    public init(mode: InputMode = .japanese, showsGlobe: Bool = true, now: @escaping () -> Date = Date.init) {
        self.mode = mode
        self.showsGlobe = showsGlobe
        self.now = now
    }

    public var layout: KeyboardLayout {
        .layout(for: page, showsGlobe: showsGlobe)
    }

    public var isComposing: Bool { !composer.isEmpty || !englishQuery.isEmpty }

    public var candidates: [Candidate] {
        if mode == .dictionary {
            return dictionary?.search(english: englishQuery).map { Candidate($0.word, entry: $0) } ?? []
        }
        return composer.candidates(using: dictionary)
    }

    public func press(_ kind: KeyKind) {
        let previousKeyWasSpace = lastKeyWasSpace
        lastKeyWasSpace = kind == .space

        switch kind {
        case .character(let character):
            typeCharacter(character)
        case .shift:
            toggleShift()
        case .delete:
            deleteBackward()
        case .pageToggle:
            page = page == .letters ? .numbers : .letters
            shift = .off
        case .symbolsToggle:
            page = page == .numbers ? .symbols : .numbers
        case .globe:
            break  // Handled by the system's input mode list.
        case .languageToggle:
            setMode(nextMode)
            return
        case .space:
            typeSpace(afterSpace: previousKeyWasSpace)
        case .longVowel:
            switch mode {
            case .japanese:
                composer.input("-")
                output?.show(composer)
            case .english:
                output?.insertText("-")
            case .dictionary:
                appendToQuery("-")
            }
        case .returnKey:
            if isComposing {
                commitComposition()
            } else {
                output?.insertText("\n")
            }
        }
        updateAutoCapitalization()
        onChange?()
    }

    /// Switches straight to a mode, e.g. from the language key's long-press menu.
    public func setMode(_ newMode: InputMode) {
        commitComposition()
        mode = newMode
        page = .letters
        shift = .off
        shiftIsAutomatic = false
        updateAutoCapitalization()
        onModeChange?(newMode)
        onChange?()
    }

    public func selectCandidate(_ candidate: Candidate) {
        commit(candidate.text)
        updateAutoCapitalization()
        onChange?()
    }

    /// Inserts a specific form of a dictionary word (kanji, hiragana or katakana).
    public func insertWord(_ text: String) {
        selectCandidate(Candidate(text))
    }

    public func commitComposition() {
        if !englishQuery.isEmpty {
            commit(englishQuery)
        } else if !composer.isEmpty {
            commit(composer.finalizedText)
        }
    }

    /// Space-bar trackpad: moves the cursor, confirming any composition first.
    public func moveCursor(by offset: Int) {
        commitComposition()
        output?.moveCursor(by: offset)
        onChange?()
    }

    /// Holding delete speeds up to whole words. Within a composition it still goes one character at a time.
    public func deleteWordBackward() {
        guard !isComposing else {
            press(.delete)
            return
        }
        // Trailing spaces, then the English word before them. Japanese has no spaces between
        // words, so there it's one character per step (the repeat is already fast by then).
        let reversed = Array((output?.textBeforeCursor ?? "").reversed())
        var count = 0
        while count < reversed.count && reversed[count] == " " {
            count += 1
        }
        while count < reversed.count && reversed[count].isASCII
                && (reversed[count].isLetter || reversed[count].isNumber || reversed[count] == "'") {
            count += 1
        }
        for _ in 0..<max(count, 1) {
            output?.deleteBackward()
        }
        updateAutoCapitalization()
        onChange?()
    }

    /// Call when the text or cursor changes outside the keyboard.
    public func textDidChange() {
        updateAutoCapitalization()
        onChange?()
    }

    public func label(for kind: KeyKind) -> KeyLabel {
        switch kind {
        case .character(let character):
            return .text(isShifted ? character.uppercased() : character)
        case .shift:
            switch shift {
            case .off: return .systemImage("shift")
            case .once: return .systemImage("shift.fill")
            case .locked: return .systemImage("capslock.fill")
            }
        case .delete:
            return .systemImage("delete.left")
        case .pageToggle:
            if page == .letters { return .text("123") }
            return .text(mode == .japanese ? "かな" : "ABC")
        case .symbolsToggle:
            return .text(page == .numbers ? "#+=" : "123")
        case .globe:
            return .systemImage("globe")
        case .languageToggle:
            return .text(Self.shortName(of: mode))
        case .space:
            return .text(mode == .japanese ? "空白" : "space")
        case .longVowel:
            return .text(mode == .japanese ? "ー" : "-")
        case .returnKey:
            if isComposing { return .text("確定") }
            return .text(mode == .japanese ? "改行" : "return")
        }
    }

    /// あ / EN / 辞, as shown on the language key.
    public static func shortName(of mode: InputMode) -> String {
        switch mode {
        case .japanese: return "あ"
        case .english: return "EN"
        case .dictionary: return "辞"
        }
    }

    // MARK: - Private

    private var isShifted: Bool { page == .letters && shift != .off }

    /// The next mode in the language key's cycle.
    private var nextMode: InputMode {
        let modes = settings.languageKeyModes.count >= 2 ? settings.languageKeyModes : InputMode.allCases
        guard let index = modes.firstIndex(of: mode) else { return modes[0] }
        return modes[(index + 1) % modes.count]
    }

    private func typeCharacter(_ character: String) {
        let text = isShifted ? character.uppercased() : character
        switch mode {
        case .english:
            output?.insertText(text)
        case .japanese:
            if isShifted {
                composer.inputLiteral(text)
            } else {
                for romaji in text {
                    composer.input(romaji)
                }
            }
            output?.show(composer)
        case .dictionary:
            appendToQuery(text)
        }
        if shift == .once {
            shift = .off
            shiftIsAutomatic = false
        }
    }

    private func typeSpace(afterSpace: Bool) {
        if mode == .dictionary && !englishQuery.isEmpty {
            // Multi-word lookups, e.g. "thank you".
            appendToQuery(" ")
            return
        }
        if isComposing {
            commitComposition()
            return
        }
        if page != .letters {
            page = .letters
        }
        if mode == .english && settings.doubleSpacePeriod && afterSpace,
           let before = output?.textBeforeCursor, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            output?.deleteBackward()
            output?.insertText(". ")
            lastKeyWasSpace = false
            return
        }
        output?.insertText(mode == .japanese && settings.fullWidthSpace ? "　" : " ")
    }

    private func appendToQuery(_ text: String) {
        englishQuery += text
        output?.setMarkedText(englishQuery)
    }

    private func toggleShift() {
        let time = now()
        if shift == .once, let lastShiftTap, time.timeIntervalSince(lastShiftTap) < Self.doubleTapInterval {
            shift = .locked
        } else {
            shift = shift == .off ? .once : .off
        }
        shiftIsAutomatic = false
        lastShiftTap = time
    }

    private func deleteBackward() {
        if !englishQuery.isEmpty {
            englishQuery.removeLast()
            if englishQuery.isEmpty {
                output?.setMarkedText("")
                output?.unmarkText()
            } else {
                output?.setMarkedText(englishQuery)
            }
        } else if !composer.isEmpty {
            composer.deleteBackward()
            output?.show(composer)
        } else {
            output?.deleteBackward()
        }
    }

    private func commit(_ text: String) {
        output?.commit(text)
        composer.reset()
        englishQuery = ""
    }

    /// Turns shift on at the start of a sentence in English, and back off once it's no longer needed.
    private func updateAutoCapitalization() {
        guard shift != .locked else { return }
        let wanted = settings.autoCapitalization && mode == .english && page == .letters
            && !isComposing && Self.isSentenceStart(output?.textBeforeCursor)
        if wanted {
            if shift == .off {
                shift = .once
                shiftIsAutomatic = true
            }
        } else if shift == .once && shiftIsAutomatic {
            shift = .off
            shiftIsAutomatic = false
        }
    }

    private static func isSentenceStart(_ before: String?) -> Bool {
        guard let before, !before.isEmpty else { return true }
        if before.hasSuffix("\n") { return true }
        guard before.hasSuffix(" ") else { return false }
        let lastVisible = before.last(where: { $0 != " " })
        return lastVisible.map { ".!?。！？".contains($0) } ?? true
    }
}
