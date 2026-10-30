import KeyboardCore
import UIKit

/// What both keyboards share: the candidate bar on top, the key area underneath, the
/// dictionary entry panel, settings and theme. Subclasses build and lay out the keys.
class KeyboardViewBase: UIView, UIInputViewAudioFeedback {
    let candidateBar = CandidateBar()
    let keyArea = UIView()
    let feedback: KeyFeedback
    private(set) var settings = KeyboardSettings()
    private(set) var theme = KeyboardTheme.named(.system)
    private var entryView: DictionaryEntryView?

    var enableInputClicksWhenVisible: Bool { true }

    init(feedback: KeyFeedback) {
        self.feedback = feedback
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(candidateBar)
        addSubview(keyArea)
        candidateBar.onSelect = { [weak self] candidate in
            self?.feedback.keyDown()
            self?.selectCandidate(candidate)
        }
        candidateBar.onShowEntry = { [weak self] candidate in
            self?.showEntry(for: candidate)
        }
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

    func update(showsGlobe: Bool) {}

    func textDidChange() {}

    // MARK: - Shared behaviour

    func apply(_ settings: KeyboardSettings) {
        self.settings = settings
        theme = .named(settings.theme)
        backgroundColor = theme.background
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
        let barHeight = KeyboardMetrics.candidateBarHeight
        candidateBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        keyArea.frame = CGRect(x: 0, y: barHeight, width: bounds.width, height: bounds.height - barHeight)
        entryView?.frame = keyArea.frame.insetBy(dx: 6, dy: 4)
        layoutKeys(rowHeight: rowHeight)
    }

    func showEntry(for candidate: Candidate) {
        guard let entry = candidate.entry else { return }
        hideEntry()
        let view = DictionaryEntryView(entry: entry, theme: theme)
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
