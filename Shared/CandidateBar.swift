import KeyboardCore
import UIKit

/// Horizontal strip of conversion choices: ひらがな, kanji from the dictionary, カタカナ, and in
/// 辞書 mode the Japanese words for what's been typed in English.
///
/// Tap a candidate to insert it. Long-press a dictionary word to see its full entry.
final class CandidateBar: UIView {
    var onSelect: ((Candidate) -> Void)?
    var onShowEntry: ((Candidate) -> Void)?

    var theme = KeyboardTheme.named(.system) {
        didSet { rebuild() }
    }

    /// Show the reading and English meaning under each dictionary word.
    var showsMeanings = true {
        didSet { if showsMeanings != oldValue { rebuild() } }
    }

    var candidates: [Candidate] = [] {
        didSet { if candidates != oldValue { rebuild() } }
    }

    /// Shown when there are no candidates (e.g. "辞書: type in English").
    var placeholder = "" {
        didSet { if placeholder != oldValue { rebuild() } }
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
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
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

        if candidates.isEmpty && !placeholder.isEmpty {
            let label = UILabel()
            label.text = placeholder
            label.font = .systemFont(ofSize: 13)
            label.textColor = theme.secondaryText
            stack.addArrangedSubview(label)
            return
        }

        for candidate in candidates {
            let cell = CandidateCell(candidate: candidate, showsMeaning: showsMeanings, theme: theme)
            cell.addAction(UIAction { [weak self] _ in self?.onSelect?(candidate) }, for: .touchUpInside)
            if candidate.entry != nil {
                let press = UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:)))
                cell.addGestureRecognizer(press)
            }
            stack.addArrangedSubview(cell)
        }
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

    init(candidate: Candidate, showsMeaning: Bool, theme: KeyboardTheme) {
        self.candidate = candidate
        self.theme = theme
        super.init(frame: .zero)
        layer.cornerRadius = 6

        let title = UILabel()
        let word = NSMutableAttributedString(
            string: candidate.text,
            attributes: [.font: UIFont.systemFont(ofSize: 18), .foregroundColor: theme.text]
        )
        if showsMeaning, let reading = candidate.entry?.reading, reading != candidate.text {
            word.append(NSAttributedString(
                string: " " + reading,
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
            stack.addArrangedSubview(subtitle)
        }

        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = -1
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(lessThanOrEqualToConstant: 220),
            heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { backgroundColor = isHighlighted ? theme.pressedKey : .clear }
    }
}
