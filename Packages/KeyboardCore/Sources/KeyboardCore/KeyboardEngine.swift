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

    public var settings = KeyboardSettings()
    /// Loaded in the background; until then there are no kanji or 辞書 results.
    public var dictionary: JapaneseDictionary? {
        didSet { onChange?() }
    }

    /// Words picked for each reading before, so they come first.
    public var history: ConversionHistory?
    public var emojiCatalog: EmojiCatalog? {
        didSet { onChange?() }
    }
    /// English suggestions and autocorrect.
    public var suggester: WordSuggester?
    /// Predictive text. Loaded in the background; until then there are no predictions.
    public var predictor: NextWordPredictor? {
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
    /// The last autocorrection, so pressing delete straight after it can undo it.
    private var lastAutocorrection: (original: String, corrected: String)?
    private var japaneseContext = JapanesePredictionContext()
    private static let doubleTapInterval: TimeInterval = 0.35

    public init(mode: InputMode = .japanese, now: @escaping () -> Date = Date.init) {
        self.mode = mode
        self.now = now
    }

    public var layout: KeyboardLayout {
        .layout(for: page)
    }

    public var isComposing: Bool { !composer.isEmpty || !englishQuery.isEmpty }

    /// Live conversion is off while typing goes into an emoji or GIF search.
    public var convertsAutomatically = true

    /// What the composition shows, and what 確定 or space confirms: with live conversion on,
    /// the words the keyboard is sure of are already in kanji (たべた → 食べた).
    private func liveText(_ text: String, converting kana: String) -> String {
        guard settings.liveConversion, convertsAutomatically, let dictionary, !kana.isEmpty else { return text }
        let converted = KanaKanjiConverter(dictionary: dictionary, history: history).liveConversion(kana)
        return converted + text.dropFirst(kana.count)
    }

    /// The text 確定 or space confirms.
    private var committedText: String {
        let finalized = composer.finalizedText
        return liveText(finalized, converting: finalized)
    }

    private func showComposition() {
        if composer.isEmpty {
            output?.show(composer)
        } else {
            output?.setMarkedText(liveText(composer.displayText, converting: composer.kana))
        }
    }

    /// 辞 has two styles, switched with the key next to return: look words up (the English is a
    /// search, confirmed with 確定), or type English straight into the text, seeing the Japanese.
    public var typesDirectly: Bool { mode == .dictionary && settings.dictionaryTypesDirectly }

    /// English typed as text: EN, or 辞 typing directly. Gets auto-capitals and double-space.
    private var typesEnglish: Bool { mode == .english || typesDirectly }

    /// The 辞 style changed from the keyboard; the controller saves it.
    public var onSettingsChange: ((KeyboardSettings) -> Void)?

    public var candidates: [Candidate] {
        switch mode {
        case .dictionary:
            if typesDirectly {
                guard let word = dictionaryWord else { return [] }
                return dictionary?.search(english: word.word).map { Candidate($0.word, entry: $0) } ?? []
            }
            return dictionary?.search(english: englishQuery).map { Candidate($0.word, entry: $0) } ?? []
        case .japanese:
            if composer.isEmpty {
                return japanesePredictions
            }
            return composer.candidates(using: dictionary, history: history, emoji: settings.emojiSuggestions ? emojiCatalog : nil)
        case .english:
            return englishCandidates
        }
    }

    /// For the word being typed: keep-as-typed and the autocorrection (when autocorrect would
    /// change it), completions, then emoji.
    private var englishCandidates: [Candidate] {
        guard page == .letters || page == .numbers, let before = output?.textBeforeCursor else { return [] }
        let word = WordSuggester.currentWord(in: before)
        guard !word.isEmpty else { return englishPredictions(before: before) }
        var result: [Candidate] = []
        if settings.wordSuggestions, let suggestions = suggester?.suggestions(for: word) {
            if let correction = suggestions.autocorrection {
                if settings.autocorrect {
                    result.append(Candidate(word, kind: .typed))
                    result.append(Candidate(correction, kind: .autocorrection))
                } else {
                    result.append(Candidate(correction, kind: .word))
                }
            }
            result += suggestions.alternatives.map { Candidate($0, kind: .word) }
        }
        if settings.emojiSuggestions {
            result += (emojiCatalog?.suggestions(for: word, limit: 2) ?? [])
                .map { Candidate($0.withSkinTone(settings.skinTone), kind: .emoji) }
        }
        return result
    }

    /// After an English word and a space: the words likely to come next.
    private func englishPredictions(before: String) -> [Candidate] {
        guard settings.predictiveText, page == .letters, let predictor,
              let previous = NextWordPredictor.wordBeforeSpace(in: before) else { return [] }
        return predictor.english(after: previous).map { Candidate($0, kind: .prediction) }
    }

    /// Straight after a Japanese word is committed: the words likely to come next.
    private var japanesePredictions: [Candidate] {
        guard settings.predictiveText, let predictor,
              let previous = japaneseContext.previous(textBefore: output?.textBeforeCursor) else { return [] }
        return predictor.japanese(after: previous).map { Candidate($0, kind: .prediction) }
    }

    public func press(_ kind: KeyKind) {
        let previousKeyWasSpace = lastKeyWasSpace
        lastKeyWasSpace = kind == .space
        let autocorrectionToUndo = lastAutocorrection
        lastAutocorrection = nil

        switch kind {
        case .character(let character):
            typeCharacter(character)
        case .shift:
            toggleShift()
        case .delete:
            if let autocorrectionToUndo, undoAutocorrection(autocorrectionToUndo) {
                break
            }
            deleteBackward()
        case .pageToggle:
            page = page == .letters ? .numbers : .letters
            shift = .off
        case .symbolsToggle:
            page = page == .numbers ? .symbols : .numbers
        case .languageToggle:
            setMode(nextMode)
            return
        case .space:
            typeSpace(afterSpace: previousKeyWasSpace)
        case .longVowel:
            switch mode {
            case .japanese:
                composer.input("-")
                showComposition()
            case .english:
                output?.insertText("-")
            case .dictionary:
                // In 辞, a toggle between looking words up and typing English.
                commitComposition()
                settings.dictionaryTypesDirectly.toggle()
                onSettingsChange?(settings)
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

    /// Switches straight to a mode, e.g. from the mode wheel.
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
        lastAutocorrection = nil
        if typesDirectly && !isComposing, let word = dictionaryWord {
            // Swap the English word for the Japanese one.
            for _ in 0..<(word.word.count + word.after.count) {
                output?.deleteBackward()
            }
            output?.insertText(candidate.text + word.after)
            updateAutoCapitalization()
            onChange?()
            return
        }
        if let part = candidate.part, isComposing {
            // The first word of a phrase: the rest stays, to convert next.
            history?.record(reading: part, word: candidate.text)
            output?.commit(candidate.text)
            composer.removeFirst(part)
            showComposition()
            onChange?()
            return
        }
        if mode == .english && !isComposing {
            let word = WordSuggester.currentWord(in: output?.textBeforeCursor ?? "")
            switch candidate.kind {
            case .typed:
                suggester?.learned.learn(word)
                learnPair(endingWith: word)
                output?.insertText(" ")
            case .word, .autocorrection:
                learnPair(endingWith: word, as: candidate.text)
                replaceCurrentWord(word, with: candidate.text)
                output?.insertText(" ")
            case .prediction:
                if let previous = NextWordPredictor.wordBeforeSpace(in: output?.textBeforeCursor ?? "") {
                    predictor?.learn(previous: previous, next: candidate.text)
                }
                output?.insertText(candidate.text + " ")
            case .emoji:
                // After the word, like other keyboards: "pizza 🍕".
                output?.insertText(word.isEmpty ? candidate.text : " " + candidate.text)
            case .conversion:
                output?.insertText(candidate.text)
            }
        } else {
            if mode == .japanese && candidate.kind == .conversion {
                history?.record(reading: composer.finalizedText, word: candidate.text)
            }
            if candidate.kind == .prediction {
                japaneseContext.compositionStarted(textBefore: output?.textBeforeCursor)
            }
            commit(candidate.text)
        }
        updateAutoCapitalization()
        onChange?()
    }

    /// Inserts text straight into the document (emoji panel, kaomoji, paste), confirming any composition first.
    public func insertDirectly(_ text: String) {
        lastAutocorrection = nil
        commitComposition()
        output?.insertText(text)
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
            commit(committedText)
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
        case .languageToggle:
            return .text(Self.shortName(of: mode))
        case .space:
            return .text(mode == .japanese ? "空白" : "space")
        case .longVowel:
            if mode == .dictionary {
                return .systemImage(settings.dictionaryTypesDirectly ? "character.cursor.ibeam" : "magnifyingglass")
            }
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
            if ".,!?;:".contains(text) {
                finishEnglishWord()
            }
            output?.insertText(text)
        case .dictionary where settings.dictionaryTypesDirectly:
            output?.insertText(text)
        case .japanese:
            if composer.isEmpty {
                japaneseContext.compositionStarted(textBefore: output?.textBeforeCursor)
            }
            if isShifted {
                composer.inputLiteral(text)
            } else {
                for romaji in text {
                    composer.input(romaji)
                }
            }
            showComposition()
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
        if mode == .english {
            finishEnglishWord()
        }
        if typesEnglish && settings.doubleSpacePeriod && afterSpace,
           let before = output?.textBeforeCursor, before.hasSuffix(" "),
           let previous = before.dropLast().last, previous.isLetter || previous.isNumber {
            output?.deleteBackward()
            output?.insertText(". ")
            lastKeyWasSpace = false
            return
        }
        output?.insertText(mode == .japanese && settings.fullWidthSpace ? "　" : " ")
    }

    /// At the end of an English word: autocorrect it, or remember it as a word the user uses.
    private func finishEnglishWord() {
        let word = WordSuggester.currentWord(in: output?.textBeforeCursor ?? "")
        guard !word.isEmpty else { return }
        if settings.autocorrect, let correction = suggester?.correction(for: word), correction != word {
            learnPair(endingWith: word, as: correction)
            replaceCurrentWord(word, with: correction)
            lastAutocorrection = (word, correction)
        } else {
            suggester?.learned.learn(word)
            learnPair(endingWith: word)
        }
    }

    /// Remembers the word before the one being finished, for predictive text ("see you").
    private func learnPair(endingWith word: String, as finalWord: String? = nil) {
        let before = output?.textBeforeCursor ?? ""
        guard before.hasSuffix(word),
              let previous = NextWordPredictor.wordBeforeSpace(in: String(before.dropLast(word.count))) else { return }
        predictor?.learn(previous: previous, next: finalWord ?? word)
    }

    /// Delete straight after an autocorrection puts back what was typed, and remembers it.
    private func undoAutocorrection(_ change: (original: String, corrected: String)) -> Bool {
        guard let before = output?.textBeforeCursor, before.hasSuffix(change.corrected + " ") else { return false }
        for _ in 0...change.corrected.count {
            output?.deleteBackward()
        }
        output?.insertText(change.original)
        suggester?.learned.learn(change.original)
        return true
    }

    private func replaceCurrentWord(_ word: String, with replacement: String) {
        for _ in 0..<word.count {
            output?.deleteBackward()
        }
        output?.insertText(replacement)
    }

    /// In 辞 while typing English: the word being typed, or the one just finished and its space.
    private var dictionaryWord: (word: String, after: String)? {
        let before = output?.textBeforeCursor ?? ""
        let word = WordSuggester.currentWord(in: before)
        if !word.isEmpty {
            return (word, "")
        }
        guard before.hasSuffix(" ") else { return nil }
        let previous = WordSuggester.currentWord(in: String(before.dropLast()))
        return previous.isEmpty ? nil : (previous, " ")
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
            showComposition()
        } else {
            output?.deleteBackward()
        }
    }

    private func commit(_ text: String) {
        if mode == .japanese {
            japaneseContext.committed(text, predictor: predictor)
        }
        output?.commit(text)
        composer.reset()
        englishQuery = ""
    }

    /// Turns shift on at the start of a sentence in English, and back off once it's no longer needed.
    private func updateAutoCapitalization() {
        guard shift != .locked else { return }
        let wanted = settings.autoCapitalization && typesEnglish && page == .letters
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
