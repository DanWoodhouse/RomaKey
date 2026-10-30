import KeyboardCore
import UIKit

/// The toolbar's clipboard: the last five things copied, newest first, in place of the keys.
/// Tap one to paste it; ✕ forgets it, and Clear forgets them all. They stay on this phone.
/// Reading the clipboard needs Allow Full Access.
final class ClipboardPanel: UIView {
    var onPaste: ((String) -> Void)?
    var onDelete: ((String) -> Void)?
    var onClear: (() -> Void)?
    var onClose: (() -> Void)?

    private var items: [String]
    private let theme: KeyboardTheme
    private let hasFullAccess: Bool
    private let scrollView = UIScrollView()
    private let list = UIStackView()
    private let emptyLabel = UILabel()
    private var clearButton: UIButton?
    private var bar: UIView?
    private var hasAppeared = false
    private static let barHeight: CGFloat = 38

    init(items: [String], theme: KeyboardTheme, hasFullAccess: Bool) {
        self.items = items
        self.theme = theme
        self.hasFullAccess = hasFullAccess
        super.init(frame: .zero)

        list.axis = .vertical
        list.spacing = 8
        list.translatesAutoresizingMaskIntoConstraints = false
        scrollView.removeEdgeEffects()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(list)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            list.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            list.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            list.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            list.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -10),
            list.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -20),
        ])
        for item in items {
            list.addArrangedSubview(row(for: item))
        }

        emptyLabel.numberOfLines = 0
        emptyLabel.textAlignment = .center
        emptyLabel.font = .systemFont(ofSize: 14)
        emptyLabel.textColor = theme.secondaryText
        emptyLabel.text = hasFullAccess
            ? "Copy something, then open this to paste it here. Your last \(ClipboardHistory.capacity) copies stay on this iPhone."
            : "The clipboard needs Allow Full Access: Settings → General → Keyboard → Keyboards → ローマ字."
        addSubview(emptyLabel)
        emptyLabel.isHidden = !items.isEmpty

        let bar = bottomBar()
        addSubview(bar)
        self.bar = bar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.barHeight)
        emptyLabel.frame = scrollView.frame.insetBy(dx: 28, dy: 12)
        bar?.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 8, height: Self.barHeight)
    }

    /// The rows settle up one after another the first time the panel shows.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasAppeared else { return }
        hasAppeared = true
        guard theme.animates else { return }
        for (index, row) in list.arrangedSubviews.enumerated() {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: 0, y: 10)
            UIView.animate(withDuration: 0.4, delay: Double(index) * 0.04, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                row.alpha = 1
                row.transform = .identity
            }
        }
    }

    // MARK: - Rows

    private func row(for item: String) -> UIView {
        let row = ClipRow(text: item, theme: theme)
        row.addAction(UIAction { [weak self] _ in self?.onPaste?(item) }, for: .touchUpInside)
        row.onDelete = { [weak self, weak row] in
            guard let self, let row else { return }
            self.onDelete?(item)
            self.items.removeAll { $0 == item }
            self.remove(row)
        }
        return row
    }

    private func remove(_ row: UIView) {
        let finish = {
            row.removeFromSuperview()
            self.emptyLabel.isHidden = !self.items.isEmpty
            self.clearButton?.isHidden = self.items.isEmpty
        }
        guard theme.animates else {
            finish()
            return
        }
        UIView.animate(withDuration: 0.25, animations: {
            row.alpha = 0
            row.transform = CGAffineTransform(translationX: -24, y: 0)
            row.isHidden = true
            self.list.layoutIfNeeded()
        }, completion: { _ in finish() })
    }

    private func bottomBar() -> UIView {
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.alignment = .center
        var done = UIButton.Configuration.plain()
        done.baseForegroundColor = theme.text
        var title = AttributedString("ABC")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        done.attributedTitle = title
        bar.addArrangedSubview(UIButton(configuration: done, primaryAction: UIAction { [weak self] _ in self?.onClose?() }))
        let heading = UILabel()
        heading.text = "クリップボード · Clipboard"
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = theme.secondaryText
        heading.textAlignment = .center
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(heading)
        var clear = UIButton.Configuration.plain()
        clear.baseForegroundColor = .systemRed
        var clearTitle = AttributedString("Clear")
        clearTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        clear.attributedTitle = clearTitle
        let clearButton = UIButton(configuration: clear, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.onClear?()
            self.items = []
            self.list.arrangedSubviews.forEach { self.remove($0) }
        })
        clearButton.isHidden = items.isEmpty
        clearButton.accessibilityLabel = "Clear the clipboard history"
        bar.addArrangedSubview(clearButton)
        self.clearButton = clearButton
        return bar
    }
}

/// One copied text on glass: tap to paste, ✕ to forget it.
private final class ClipRow: UIControl {
    var onDelete: (() -> Void)?
    private let glass = Glass.view(cornerRadius: 16)
    private let label = UILabel()
    private let delete = UIButton(type: .system)
    private let theme: KeyboardTheme

    init(text: String, theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        if !Glass.tintsItself {
            glass.contentView.backgroundColor = theme.panel.withAlphaComponent(0.28)
        }
        addSubview(glass)
        label.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        label.numberOfLines = 2
        label.font = theme.font(15)
        label.textColor = theme.text
        label.isUserInteractionEnabled = false
        addSubview(label)
        delete.setImage(UIImage(systemName: "xmark.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18)), for: .normal)
        delete.tintColor = theme.secondaryText
        delete.accessibilityLabel = "Forget this"
        delete.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        addSubview(delete)
        isAccessibilityElement = false
        label.isAccessibilityElement = true
        label.accessibilityTraits = .button
        label.accessibilityHint = "Pastes it"
        accessibilityElements = [label, delete]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: label.numberOfLines > 1 && (label.text?.count ?? 0) > 30 ? 62 : 46)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        delete.frame = CGRect(x: bounds.width - 40, y: 0, width: 40, height: bounds.height)
        label.frame = CGRect(x: 14, y: 6, width: bounds.width - 14 - 40, height: bounds.height - 12)
    }

    /// The glass gives a little under the finger.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue, theme.animates else { return }
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }
}
