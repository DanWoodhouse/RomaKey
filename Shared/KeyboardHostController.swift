import KeyboardCore
import UIKit

/// Sizes shared by both keyboards, so switching between them doesn't change the height.
enum KeyboardMetrics {
    static let candidateBarHeight: CGFloat = 46
    static let rowCount = 4

    static func rowHeight(compact: Bool, height: KeyboardSettings.Height) -> CGFloat {
        if compact { return 40 }
        switch height {
        case .compact: return 51
        case .standard: return 57
        case .tall: return 63
        }
    }

    static func height(compact: Bool, height: KeyboardSettings.Height) -> CGFloat {
        candidateBarHeight + CGFloat(rowCount) * rowHeight(compact: compact, height: height)
    }
}

/// Loads the bundled dictionary once per keyboard process, off the main thread.
enum DictionaryLoader {
    private static var dictionary: JapaneseDictionary?
    private static var isLoading = false
    private static var waiting: [(JapaneseDictionary?) -> Void] = []

    /// Calls back on the main thread.
    static func load(_ completion: @escaping (JapaneseDictionary?) -> Void) {
        if let dictionary {
            completion(dictionary)
            return
        }
        waiting.append(completion)
        guard !isLoading else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let loaded = JapaneseDictionary.bundled()
            DispatchQueue.main.async {
                dictionary = loaded
                isLoading = false
                let callbacks = waiting
                waiting = []
                callbacks.forEach { $0(loaded) }
            }
        }
    }
}

/// Loads the emoji list once per keyboard process, hiding emoji this iOS can't draw.
enum EmojiLoader {
    private static var catalog: EmojiCatalog?

    static func load(_ completion: @escaping (EmojiCatalog?) -> Void) {
        if let catalog {
            completion(catalog)
            return
        }
        let parts = UIDevice.current.systemVersion.split(separator: ".").compactMap { Int($0) }
        let maxVersion = EmojiCatalog.maxSupportedVersion(iOSMajor: parts.first ?? 16, minor: parts.dropFirst().first ?? 0)
        // After the dictionary, which matters more while typing.
        DispatchQueue.global(qos: .utility).async {
            let loaded = EmojiCatalog.bundled(maxVersion: maxVersion)
            DispatchQueue.main.async {
                catalog = loaded
                completion(loaded)
            }
        }
    }
}

/// Both boards, the ローマ字 QWERTY and the 12-key かな grid, connected to the text field being
/// edited. The mode wheel on either board's mode key switches modes and boards. The two
/// keyboards in Settings are this same keyboard; they only open on different boards.
class KeyboardHostController: UIInputViewController {
    enum Board {
        case romaji
        case kana
    }

    /// The board shown each time the keyboard appears. The かな keyboard overrides this.
    var openingBoard: Board { .romaji }

    private(set) lazy var textOutput: TextOutput = ProxyTextOutput(controller: self)
    let feedback = KeyFeedback()
    private(set) var settings = KeyboardSettings()
    private let romajiEngine = KeyboardEngine(mode: .japanese)
    private let flickEngine = FlickKeyboardEngine()
    private var romajiView: RomajiKeyboardView!
    private var flickView: FlickKeyboardView!
    private var board: Board = .romaji
    private var heightConstraint: NSLayoutConstraint?

    private var contentView: KeyboardViewBase {
        board == .romaji ? romajiView : flickView
    }

    private var boardViews: [KeyboardViewBase] { [romajiView, flickView] }

    /// Settings are shared with the app through an App Group, which needs Full Access.
    let sharedDefaults = UserDefaults(suiteName: KeyboardSettings.appGroup)

    /// Where settings are read and saved: shared with the app with Full Access, otherwise this
    /// keyboard's own storage, so the quick settings panel still works.
    private var settingsStore: UserDefaults? {
        hasFullAccess ? sharedDefaults : learningStore
    }

    /// Learned words, kanji choices and recent emoji stay in this keyboard's own storage, on the phone.
    let learningStore = UserDefaults.standard
    private(set) lazy var recentEmoji = RecentEmoji(store: learningStore)
    private(set) lazy var clipboardHistory = ClipboardHistory(store: learningStore)

    override func viewDidLoad() {
        super.viewDidLoad()
        let history = ConversionHistory(store: learningStore)
        romajiEngine.output = textOutput
        romajiEngine.history = history
        romajiEngine.suggester = WordSuggester(checker: SystemSpellChecker(), learned: LearnedWords(store: learningStore))
        romajiEngine.onSettingsChange = { [weak self] newSettings in self?.update(newSettings) }
        romajiEngine.onModeChange = { [weak self] mode in
            guard let defaults = self?.settingsStore else { return }
            KeyboardSettings.saveLastUsedMode(mode, to: defaults)
        }
        flickEngine.output = textOutput
        flickEngine.history = history

        romajiView = RomajiKeyboardView(engine: romajiEngine, feedback: feedback)
        flickView = FlickKeyboardView(engine: flickEngine, feedback: feedback)
        flickView.onModeKeyTap = { [weak self] in self?.show(.romaji) }
        for boardView in boardViews {
            boardView.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(boardView)
            NSLayoutConstraint.activate([
                boardView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                boardView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                boardView.topAnchor.constraint(equalTo: view.topAnchor),
                boardView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
            boardView.recentEmoji = recentEmoji
            boardView.clipboard = clipboardHistory
            boardView.onSkinTone = { [weak self] tone in
                guard let defaults = self?.settingsStore else { return }
                KeyboardSettings.saveSkinTone(tone, to: defaults)
            }
            boardView.onModeWheel = { [weak self] slot in self?.select(slot) }
            boardView.onSettingsChange = { [weak self] newSettings in self?.update(newSettings) }
            boardView.onOpenApp = { [weak self] in self?.openApp() }
            boardView.document = textOutput
        }
        show(openingBoard)

        DictionaryLoader.load { [weak self] dictionary in
            self?.romajiEngine.dictionary = dictionary
            self?.flickEngine.dictionary = dictionary
        }
        let store = learningStore
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let predictor = NextWordPredictor.bundled(store: store)
            DispatchQueue.main.async {
                self?.romajiEngine.predictor = predictor
                self?.flickEngine.predictor = predictor
            }
        }
        EmojiLoader.load { [weak self] catalog in
            guard let self else { return }
            boardViews.forEach { $0.emojiCatalog = catalog }
            romajiEngine.emojiCatalog = catalog
            flickEngine.emojiCatalog = catalog
        }
        // The user's iOS text replacements (omw → On my way!) and contact names, so names are never "corrected".
        requestSupplementaryLexicon { [weak self] lexicon in
            var replacements: [String: String] = [:]
            var known: Set<String> = []
            for entry in lexicon.entries {
                if entry.userInput.caseInsensitiveCompare(entry.documentText) == .orderedSame {
                    known.insert(entry.documentText.lowercased())
                } else {
                    replacements[entry.userInput.lowercased()] = entry.documentText
                }
            }
            self?.romajiEngine.suggester?.textReplacements = replacements
            self?.romajiEngine.suggester?.knownWords = known
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Re-read every time the keyboard appears, so changes made in the app apply straight away.
        settings = settingsStore.map(KeyboardSettings.init(defaults:)) ?? KeyboardSettings()
        feedback.playsSounds = settings.keySounds
        feedback.playsHaptics = settings.haptics && hasFullAccess
        if let resetID = settings.learningResetID, resetID != learningStore.string(forKey: "appliedLearningResetID") {
            romajiEngine.suggester?.learned.reset()
            romajiEngine.history?.reset()
            romajiEngine.predictor?.reset()
            learningStore.set(nil, forKey: "recentEmoji")
            recentEmoji = RecentEmoji(store: learningStore)
            clipboardHistory.removeAll()
            learningStore.set(resetID, forKey: "appliedLearningResetID")
        }
        for boardView in boardViews {
            boardView.hasFullAccess = hasFullAccess
            boardView.recentEmoji = recentEmoji
            boardView.apply(settings)
        }
        romajiEngine.setMode(settings.initialMode)
        flickEngine.setPage(.kana)
        show(openingBoard)
        updateHeight()
        runAIProbeIfRequested()
    }

    /// A change from the quick settings panel: saved, then applied to both boards straight away.
    private func update(_ newSettings: KeyboardSettings) {
        settings = newSettings
        if let settingsStore {
            newSettings.save(to: settingsStore)
        }
        feedback.playsSounds = settings.keySounds
        feedback.playsHaptics = settings.haptics && hasFullAccess
        boardViews.forEach { $0.apply(settings) }
        updateHeight()
    }

    /// Opens the RomaKey app at its settings. Keyboards can't call `openURL` themselves, so this
    /// asks the application object further up the responder chain. Fine for your own builds;
    /// App Review may not accept it.
    private func openApp() {
        guard let url = NSURL(string: "romakey://settings") else { return }
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, let method = class_getInstanceMethod(type(of: current), selector) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?) -> Void
                let open = unsafeBitCast(method_getImplementation(method), to: Open.self)
                open(current, selector, url, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        contentView.flash("Open the RomaKey app from the Home Screen")
    }

    /// A slot picked on either board's mode wheel.
    private func select(_ slot: ModeWheelSlot) {
        if let mode = slot.inputMode {
            romajiEngine.setMode(mode)
            show(.romaji)
            return
        }
        switch slot {
        case .kana:
            flickEngine.setPage(.kana)
            show(.kana)
        case .japanese, .english, .dictionary:
            break
        }
    }

    /// Both boards are the same height, so switching never moves the text field.
    private func show(_ newBoard: Board) {
        if newBoard != board {
            romajiEngine.commitComposition()
            flickEngine.commitComposition()
            contentView.boardWillHide()
        }
        let changed = newBoard != board
        board = newBoard
        romajiView.isHidden = newBoard != .romaji
        flickView.isHidden = newBoard != .kana
        contentView.reload()
        if changed {
            contentView.appear()
        }
    }

    /// The app's Apple Intelligence screen can ask the next keyboard to appear to test the
    /// on-device model from inside the keyboard. The result goes back to the app (with Full
    /// Access) and is also shown in the candidate bar.
    private func runAIProbeIfRequested() {
        guard let defaults = sharedDefaults, defaults.bool(forKey: AIProbe.requestKey) else { return }
        defaults.set(false, forKey: AIProbe.requestKey)
        contentView.candidateBar.status = "Testing Apple Intelligence…"
        Task { @MainActor [weak self] in
            let result = await AIProbe.run(process: "Keyboard")
            AIProbe.save(result, to: defaults)
            self?.contentView.candidateBar.status = AIProbe.summary(of: result)
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            self?.contentView.candidateBar.status = nil
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        updateHeight()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        contentView.textDidChange()
    }

    private func updateHeight() {
        let height = KeyboardMetrics.height(
            compact: traitCollection.verticalSizeClass == .compact,
            height: settings.height
        )
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }
}

/// Sends an engine's output to the host app's text field.
private final class ProxyTextOutput: TextOutput {
    private weak var controller: UIInputViewController?

    init(controller: UIInputViewController) {
        self.controller = controller
    }

    private var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }

    func insertText(_ text: String) {
        proxy?.insertText(text)
    }

    func deleteBackward() {
        proxy?.deleteBackward()
    }

    /// What's marked (underlined) in the text field, as far as the keyboard knows.
    private var marked = ""

    func setMarkedText(_ text: String) {
        marked = text
        proxy?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
    }

    func unmarkText() {
        marked = ""
        proxy?.unmarkText()
    }

    /// 確定. Setting the marked text and unmarking it in the same instant can leave the
    /// underline behind in some apps, so the marked text is only replaced when it differs, and
    /// the unmark is sent again once the app has caught up.
    func commit(_ text: String) {
        if marked != text {
            proxy?.setMarkedText(text, selectedRange: NSRange(location: (text as NSString).length, length: 0))
        }
        marked = ""
        proxy?.unmarkText()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.marked.isEmpty else { return }
            self.proxy?.unmarkText()
        }
    }

    func moveCursor(by offset: Int) {
        proxy?.adjustTextPosition(byCharacterOffset: offset)
    }

    var textBeforeCursor: String? {
        proxy?.documentContextBeforeInput
    }
}
