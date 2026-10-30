import ImageIO
import KeyboardCore
import UIKit

/// What both keyboards share: the candidate bar on top, the key area underneath, the
/// dictionary entry panel, the emoji and GIF panels (shown in place of the keys), emoji/GIF
/// search, settings and theme. Subclasses build and lay out the keys.
class KeyboardViewBase: UIView, UIInputViewAudioFeedback {
    let candidateBar = CandidateBar()
    let keyArea = UIView()
    let feedback: KeyFeedback
    private(set) var settings = KeyboardSettings()
    private(set) var theme = KeyboardTheme.named(.system)
    private var entryView: DictionaryEntryView?
    private let backgroundImageView = UIImageView()
    private let dimView = UIView()
    private let blurView = UIVisualEffectView(effect: UIBlurEffect(style: .regular))

    /// Set by the controller once loaded.
    var emojiCatalog: EmojiCatalog?
    var recentEmoji: RecentEmoji?
    var hasFullAccess = false
    /// Saves a newly picked skin tone.
    var onSkinTone: ((Int) -> Void)?
    /// A slot picked on the mode wheel. The controller switches mode or board.
    var onModeWheel: ((ModeWheelSlot) -> Void)?
    /// Settings changed in the quick settings panel. The controller saves and applies them.
    var onSettingsChange: ((KeyboardSettings) -> Void)?
    /// The text field being edited, for the AI panel to read and replace text.
    var document: TextOutput?

    enum SearchTarget {
        case emoji
        case gif
    }

    /// The emoji or GIF panel, shown in place of the keys.
    private var panel: UIView?
    private(set) var searchTarget: SearchTarget?
    /// Where typing goes while searching.
    let searchBuffer = SearchBuffer()
    private var statusTimer: Timer?

    var enableInputClicksWhenVisible: Bool { true }

    init(feedback: KeyFeedback) {
        self.feedback = feedback
        super.init(frame: .zero)
        backgroundColor = .clear
        backgroundImageView.contentMode = .scaleAspectFill
        backgroundImageView.clipsToBounds = true
        dimView.backgroundColor = .black
        for view in [backgroundImageView, blurView, dimView] {
            view.isHidden = true
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        addSubview(candidateBar)
        addSubview(keyArea)
        candidateBar.onSelect = { [weak self] candidate in
            self?.feedback.keyDown()
            self?.candidateTapped(candidate)
        }
        candidateBar.onShowEntry = { [weak self] candidate in
            self?.showEntry(for: candidate)
        }
        candidateBar.onToolbar = { [weak self] action in
            self?.feedback.keyDown()
            self?.toolbarTapped(action)
        }
        candidateBar.onCancelSearch = { [weak self] in self?.endSearch() }
        searchBuffer.onChange = { [weak self] in self?.refreshSearch() }
        searchBuffer.onSubmit = { [weak self] in self?.submitSearch() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - For subclasses

    /// Relabels keys and refreshes candidates from the engine.
    func reload() {}

    /// Positions the keys inside `keyArea`.
    func layoutKeys(rowHeight: CGFloat) {}

    func selectCandidate(_ candidate: Candidate) {}

    /// Inserts a word chosen from the dictionary entry panel.
    func insertWord(_ text: String) {}

    /// Passes new settings to the engine and keys.
    func settingsDidChange() {}

    func textDidChange() {}

    /// Inserts text straight into the document (emoji, kaomoji, paste).
    func insertDirectly(_ text: String) {}

    /// Delete pressed in the emoji panel.
    func deleteFromPanel() {}

    /// Sends typing to `output` (the search field) or, when nil, back to the document.
    func routeTyping(to output: TextOutput?) {}

    /// Confirms any composition, so the document holds everything typed.
    func commitTyping() {}

    /// "ja" or "en", for GIF search.
    var searchLanguage: String { "en" }

    /// Subclasses show their engine's candidates through this, so search results aren't replaced.
    func showCandidates(_ candidates: [Candidate], showsMeanings: Bool, placeholder: String) {
        guard searchTarget == nil else { return }
        candidateBar.showsMeanings = showsMeanings
        candidateBar.showsRomaji = settings.showRomaji
        candidateBar.placeholder = placeholder
        candidateBar.candidates = candidates
    }

    // MARK: - Shared behaviour

    /// Closes panels, search and the dictionary entry before the other board is shown.
    func boardWillHide() {
        closePanel()
        endSearch()
        hideEntry()
    }

    func apply(_ settings: KeyboardSettings) {
        self.settings = settings
        theme = KeyboardTheme(settings)
        backgroundColor = theme.background

        let image = BackgroundImageLoader.image(id: settings.backgroundImageID)
        backgroundImageView.image = image
        backgroundImageView.isHidden = image == nil
        blurView.isHidden = image == nil || !settings.backgroundBlur
        dimView.isHidden = image == nil
        dimView.alpha = settings.backgroundDim
        candidateBar.theme = theme
        settingsDidChange()
        reload()
        setNeedsLayout()
    }

    var rowHeight: CGFloat {
        KeyboardMetrics.rowHeight(compact: traitCollection.verticalSizeClass == .compact, height: settings.height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundImageView.frame = bounds
        blurView.frame = bounds
        dimView.frame = bounds
        let barHeight = KeyboardMetrics.candidateBarHeight
        candidateBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        keyArea.frame = CGRect(x: 0, y: barHeight, width: bounds.width, height: bounds.height - barHeight)
        entryView?.frame = keyArea.frame.insetBy(dx: 6, dy: 4)
        panel?.frame = keyArea.frame
        layoutKeys(rowHeight: rowHeight)
    }

    // MARK: - Toolbar, panels and search

    private func candidateTapped(_ candidate: Candidate) {
        guard searchTarget == .emoji else {
            selectCandidate(candidate)
            return
        }
        // An emoji search result: back to the document, then insert it.
        endSearch()
        recentEmoji?.use(candidate.text)
        insertDirectly(candidate.text)
    }

    private func toolbarTapped(_ action: CandidateBar.ToolbarAction) {
        switch action {
        case .emoji:
            showEmojiPanel(tab: (recentEmoji?.items.isEmpty ?? true) ? .group(.smileys) : .recent)
        case .kaomoji:
            showEmojiPanel(tab: .kaomoji)
        case .gif:
            showGIFPanel(query: nil)
        case .paste:
            // Keyboards can only read the clipboard with Full Access.
            if hasFullAccess, let text = UIPasteboard.general.string, !text.isEmpty {
                insertDirectly(text)
            } else {
                flash(hasFullAccess ? "Nothing to paste" : "Paste needs Allow Full Access")
            }
        case .ai:
            commitTyping()
            let input = AIPrompts.trimmedInput(document?.textBeforeCursor ?? "")
            let panel = AIPanel(input: input, theme: theme, showsRomaji: settings.showRomaji,
                                provider: settings.aiProvider, claudeAPIKey: settings.claudeAPIKey)
            panel.onClose = { [weak self] in self?.closePanel() }
            panel.onProviderChange = { [weak self] provider in
                guard let self else { return }
                var newSettings = self.settings
                newSettings.aiProvider = provider
                self.onSettingsChange?(newSettings)
            }
            panel.onReplace = { [weak self] text in
                self?.replaceTextBeforeCursor(input, with: text)
                self?.closePanel()
            }
            install(panel)
        case .settings:
            let quickSettings = QuickSettingsPanel(settings: settings, theme: theme, sharesWithApp: hasFullAccess)
            quickSettings.onChange = { [weak self] newSettings in self?.onSettingsChange?(newSettings) }
            quickSettings.onClose = { [weak self] in self?.closePanel() }
            install(quickSettings)
        }
    }

    func showEmojiPanel(tab: EmojiPanel.Tab) {
        endSearch()
        let emojiPanel = EmojiPanel(catalog: emojiCatalog, recents: recentEmoji, theme: theme,
                                    skinTone: settings.skinTone, tab: tab)
        emojiPanel.onInsert = { [weak self] text in
            self?.feedback.keyDown()
            self?.insertDirectly(text)
        }
        emojiPanel.onDelete = { [weak self] in
            self?.feedback.keyDown()
            self?.deleteFromPanel()
        }
        emojiPanel.onClose = { [weak self] in self?.closePanel() }
        emojiPanel.onSearch = { [weak self] in self?.beginSearch(.emoji) }
        emojiPanel.onSkinTone = { [weak self] tone in
            self?.settings.skinTone = tone
            self?.onSkinTone?(tone)
        }
        install(emojiPanel)
    }

    func showGIFPanel(query: String?) {
        endSearch()
        let unavailable: String?
        if settings.giphyAPIKey.isEmpty {
            unavailable = "GIFs need a GIPHY API key. Add one in the app: Settings → GIFs."
        } else if !hasFullAccess {
            unavailable = "GIFs need Allow Full Access, so the keyboard can reach GIPHY and copy the GIF."
        } else {
            unavailable = nil
        }
        let client = unavailable == nil
            ? GiphyClient(apiKey: settings.giphyAPIKey, rating: settings.gifRating, language: searchLanguage)
            : nil
        let gifPanel = GIFPanel(client: client, query: query, theme: theme, unavailableReason: unavailable)
        gifPanel.onClose = { [weak self] in self?.closePanel() }
        gifPanel.onSearch = { [weak self] in self?.beginSearch(.gif) }
        gifPanel.onMessage = { [weak self] message in self?.flash(message) }
        install(gifPanel)
    }

    private func install(_ newPanel: UIView) {
        panel?.removeFromSuperview()
        hideEntry()
        keyArea.isHidden = true
        addSubview(newPanel)
        panel = newPanel
        setNeedsLayout()
    }

    func closePanel() {
        panel?.removeFromSuperview()
        panel = nil
        keyArea.isHidden = false
    }

    /// Shows the keys and a search field; typing goes into the field until the search ends.
    func beginSearch(_ target: SearchTarget) {
        closePanel()
        searchTarget = target
        searchBuffer.reset()
        routeTyping(to: searchBuffer)
        refreshSearch()
    }

    func endSearch() {
        guard searchTarget != nil else { return }
        searchTarget = nil
        routeTyping(to: nil)
        candidateBar.search = nil
        reload()
    }

    private func refreshSearch() {
        guard let searchTarget else { return }
        let query = searchBuffer.query
        switch searchTarget {
        case .emoji:
            candidateBar.search = .init(query: query, prompt: "絵文字を検索 · Search emoji")
            candidateBar.candidates = (emojiCatalog?.search(query, limit: 40) ?? [])
                .map { Candidate($0.withSkinTone(settings.skinTone), kind: .emoji) }
        case .gif:
            candidateBar.search = .init(query: query, prompt: "GIFを検索 · Search GIFs, then return")
            candidateBar.candidates = []
        }
    }

    private func submitSearch() {
        guard let searchTarget else { return }
        let query = searchBuffer.query
        switch searchTarget {
        case .gif:
            showGIFPanel(query: query.isEmpty ? nil : query)
        case .emoji:
            showEmojiPanel(tab: .recent)
        }
    }

    /// Swaps `original`, the end of the text before the cursor (ignoring trailing spaces), for
    /// `replacement`, keeping the trailing spaces.
    func replaceTextBeforeCursor(_ original: String, with replacement: String) {
        guard let document, let before = document.textBeforeCursor else { return }
        let trailing = String(before.reversed().prefix { $0.isWhitespace }.reversed())
        guard !original.isEmpty, before.dropLast(trailing.count).hasSuffix(original) else {
            flash("The text changed, so nothing was replaced")
            return
        }
        for _ in 0..<(original.count + trailing.count) {
            document.deleteBackward()
        }
        document.insertText(replacement + trailing)
    }

    /// A short message in the candidate bar.
    func flash(_ message: String) {
        candidateBar.status = message
        statusTimer?.invalidate()
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            self?.candidateBar.status = nil
        }
    }

    func showEntry(for candidate: Candidate) {
        guard let entry = candidate.entry else { return }
        hideEntry()
        let view = DictionaryEntryView(entry: entry, theme: theme, showsRomaji: settings.showRomaji)
        view.onInsert = { [weak self] text in
            self?.feedback.keyDown()
            self?.hideEntry()
            self?.insertWord(text)
        }
        view.onClose = { [weak self] in self?.hideEntry() }
        addSubview(view)
        entryView = view
        setNeedsLayout()
    }

    func hideEntry() {
        entryView?.removeFromSuperview()
        entryView = nil
    }

    /// Keys go faint while the space bar is being used as a trackpad.
    func setTrackpadActive(_ active: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.keyArea.alpha = active ? 0.35 : 1
        }
    }
}

/// Loads the background image the app saved, scaled down to keyboard size so it stays well
/// within a keyboard extension's small memory allowance.
enum BackgroundImageLoader {
    private static var cached: (id: String, image: UIImage)?

    static func image(id: String?) -> UIImage? {
        guard let id, let url = KeyboardSettings.backgroundImageURL else { return nil }
        if let cached, cached.id == id {
            return cached.image
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1400,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = UIImage(cgImage: thumbnail)
        cached = (id, image)
        return image
    }
}
