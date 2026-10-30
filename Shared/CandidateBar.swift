import KeyboardCore
import UIKit

/// The strip above the keys. It shows one of three things:
/// - **suggestions** while typing: ひらがな/kanji/カタカナ, English completions and autocorrect,
///   辞書 results and emoji. Tap to insert; long-press a dictionary word for its full entry;
/// - **predictions** after a word is finished, with an emoji button in front so emoji stay one tap away;
/// - a **toolbar** when nothing is being typed: emoji, 顔文字, GIFs, paste and settings;
/// - a **search field** while searching emoji or GIFs (typing goes into it instead of the document).
final class CandidateBar: UIView {
    enum ToolbarAction: CaseIterable {
        case emoji
        case kaomoji
        case gif
        case paste
        /// Apple Intelligence on the text before the cursor.
        case ai
        /// Quick settings, in place of the keys.
        case settings
    }

    struct Search: Equatable {
        var query: String
        var prompt: String
    }

    var onSelect: ((Candidate) -> Void)?
    var onShowEntry: ((Candidate) -> Void)?
    var onToolbar: ((ToolbarAction) -> Void)?
    var onCancelSearch: (() -> Void)?

    var theme = KeyboardTheme.named(.system) {
        didSet { rebuild() }
    }

    /// Show the reading and English meaning under each dictionary word.
    var showsMeanings = true {
        didSet { if showsMeanings != oldValue { rebuild() } }
    }

    /// Add romaji after the reading (ねこ neko).
    var showsRomaji = false {
        didSet { if showsRomaji != oldValue { rebuild() } }
    }

    var candidates: [Candidate] = [] {
        didSet { if candidates != oldValue { rebuild() } }
    }

    /// Shown when there are no candidates (e.g. "辞書: type in English").
    var placeholder = "" {
        didSet { if placeholder != oldValue { rebuild() } }
    }

    /// A temporary message that takes the placeholder's place, e.g. "GIF copied".
    var status: String? {
        didSet { if status != oldValue { rebuild() } }
    }

    var toolbarItems: [ToolbarAction] = ToolbarAction.allCases {
        didSet { if toolbarItems != oldValue { rebuild() } }
    }

    /// Non-nil while searching; `candidates` are then the results.
    var search: Search? {
        didSet { if search != oldValue { rebuild() } }
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        stack.axis = .horizontal
        stack.spacing = 2
        stack.alignment = .center
        // Items share out the bar's width when they fit, and scroll when they don't.
        stack.distribution = .fillProportionally
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -8),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = bounds
    }

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        scrollView.contentOffset = .zero
        // The search field has no natural width to share out by.
        stack.distribution = search == nil ? .fillProportionally : .fill

        if let search {
            addSearchField(search)
        } else if candidates.isEmpty {
            let message = status ?? placeholder
            if message.isEmpty {
                addToolbar()
            } else {
                stack.addArrangedSubview(label(message))
            }
            return
        }

        if candidates.first?.kind == .prediction {
            addToolbarButton(.emoji)
        }
        for (index, candidate) in candidates.enumerated() {
            let cell = CandidateCell(candidate: candidate, showsMeaning: showsMeanings, showsRomaji: showsRomaji,
                                     showsDivider: index > 0, theme: theme)
            cell.addAction(UIAction { [weak self] _ in self?.onSelect?(candidate) }, for: .touchUpInside)
            if candidate.entry != nil {
                let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
                cell.addGestureRecognizer(press)
            }
            stack.addArrangedSubview(cell)
        }
    }

    private func label(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13)
        label.textColor = theme.secondaryText
        return label
    }

    private func addToolbar() {
        for action in toolbarItems {
            addToolbarButton(action)
        }
    }

    private func addToolbarButton(_ action: ToolbarAction) {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = theme.text
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10)
        switch action {
        case .emoji:
            configuration.image = UIImage(systemName: "face.smiling")
        case .kaomoji:
            var title = AttributedString("(^_^)")
            title.font = .systemFont(ofSize: 14, weight: .medium)
            configuration.attributedTitle = title
        case .gif:
            var title = AttributedString("GIF")
            title.font = .systemFont(ofSize: 13, weight: .bold)
            configuration.attributedTitle = title
        case .paste:
            configuration.image = UIImage(systemName: "doc.on.clipboard")
        case .ai:
            configuration.image = UIImage(systemName: "sparkles")
        case .settings:
            configuration.image = UIImage(systemName: "gearshape")
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.onToolbar?(action)
        })
        button.accessibilityLabel = switch action {
        case .emoji: "Emoji"
        case .kaomoji: "Kaomoji"
        case .gif: "GIFs"
        case .paste: "Paste"
        case .ai: "AI"
        case .settings: "Keyboard settings"
        }
        stack.addArrangedSubview(button)
    }

    private func addSearchField(_ search: Search) {
        var close = UIButton.Configuration.plain()
        close.image = UIImage(systemName: "xmark.circle.fill")
        close.baseForegroundColor = theme.secondaryText
        stack.addArrangedSubview(UIButton(configuration: close, primaryAction: UIAction { [weak self] _ in
            self?.onCancelSearch?()
        }))

        let field = UILabel()
        field.font = .systemFont(ofSize: 16)
        field.textColor = search.query.isEmpty ? theme.secondaryText : theme.text
        field.text = (search.query.isEmpty ? search.prompt : search.query) + " ▏"
        field.backgroundColor = theme.panel
        field.layer.cornerRadius = 8
        field.clipsToBounds = true
        field.setContentHuggingPriority(.required, for: .horizontal)
        let container = UIView()
        container.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            field.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            field.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            field.heightAnchor.constraint(equalToConstant: 30),
            field.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
            container.heightAnchor.constraint(equalToConstant: 38),
        ])
        stack.addArrangedSubview(container)
    }

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let cell = gesture.view as? CandidateCell else { return }
        onShowEntry?(cell.candidate)
    }
}

/// One candidate: the word, and optionally its reading and meaning underneath.
private final class CandidateCell: UIControl {
    let candidate: Candidate
    private let theme: KeyboardTheme
    private let stack = UIStackView()

    init(candidate: Candidate, showsMeaning: Bool, showsRomaji: Bool, showsDivider: Bool, theme: KeyboardTheme) {
        self.candidate = candidate
        self.theme = theme
        super.init(frame: .zero)
        layer.cornerRadius = 6

        // A thin line before every suggestion but the first, like the system bar.
        if showsDivider && candidate.kind != .autocorrection {
            let divider = UIView()
            divider.backgroundColor = theme.secondaryText.withAlphaComponent(0.35)
            divider.isUserInteractionEnabled = false
            divider.translatesAutoresizingMaskIntoConstraints = false
            addSubview(divider)
            NSLayoutConstraint.activate([
                divider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -1),
                divider.centerYAnchor.constraint(equalTo: centerYAnchor),
                divider.widthAnchor.constraint(equalToConstant: 1),
                divider.heightAnchor.constraint(equalToConstant: 18),
            ])
        }

        let title = UILabel()
        let text: String
        let font: UIFont
        switch candidate.kind {
        case .typed:
            // Keep what was typed, the way iOS shows it.
            text = "“\(candidate.text)”"
            font = theme.font(17)
        case .autocorrection:
            text = candidate.text
            font = theme.font(17, weight: .semibold)
            backgroundColor = theme.panel
        case .emoji:
            text = candidate.text
            font = .systemFont(ofSize: 24)
        case .conversion, .word, .prediction:
            text = candidate.text
            font = theme.font(18)
        }
        let word = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: theme.text])
        if showsMeaning, let reading = candidate.entry?.reading {
            var parts: [String] = []
            if reading != candidate.text {
                parts.append(reading)
            }
            if showsRomaji {
                parts.append(KanaConverter.romaji(from: reading))
            }
            word.append(NSAttributedString(
                string: parts.isEmpty ? "" : " " + parts.joined(separator: " "),
                attributes: [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: theme.secondaryText]
            ))
        }
        title.attributedText = word
        stack.addArrangedSubview(title)

        if showsMeaning, let meaning = candidate.entry?.shortMeaning, !meaning.isEmpty {
            let subtitle = UILabel()
            subtitle.text = meaning
            subtitle.font = .systemFont(ofSize: 11)
            subtitle.textColor = theme.secondaryText
            subtitle.lineBreakMode = .byTruncatingTail
            stack.addArrangedSubview(subtitle)
        }

        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = -1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // Centred in whatever width the bar gives it; long meanings are cut off at 200 points.
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 200),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The word's natural width plus padding, which the bar uses to share out its width.
    override var intrinsicContentSize: CGSize {
        let size = stack.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize)
        return CGSize(width: min(size.width, 200) + 20, height: 38)
    }

    override var isHighlighted: Bool {
        didSet {
            let resting = candidate.kind == .autocorrection ? theme.panel : UIColor.clear
            backgroundColor = isHighlighted ? theme.pressedKey : resting
        }
    }
}
