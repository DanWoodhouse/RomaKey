import KeyboardCore
import UIKit

/// Candidate bar on top, keys underneath. The candidate bar is there in both languages
/// so the keyboard's height doesn't change when switching either.
final class KeyboardView: UIView, UIInputViewAudioFeedback {
    static let candidateBarHeight: CGFloat = 40

    private let engine: KeyboardEngine
    private weak var globeTarget: UIInputViewController?
    private let candidateBar = CandidateBar()
    private let keyArea = UIView()
    private var buttons: [[KeyButton]] = []
    private var builtLayout: KeyboardLayout?
    private var deleteRepeatTimer: Timer?

    var enableInputClicksWhenVisible: Bool { true }

    init(engine: KeyboardEngine, globeTarget: UIInputViewController) {
        self.engine = engine
        self.globeTarget = globeTarget
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(candidateBar)
        addSubview(keyArea)
        candidateBar.onSelect = { [weak self] candidate in
            UIDevice.current.playInputClick()
            self?.engine.selectCandidate(candidate)
        }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func preferredHeight(compact: Bool) -> CGFloat {
        Self.candidateBarHeight + CGFloat(engine.layout.rows.count) * rowHeight(compact: compact)
    }

    private func rowHeight(compact: Bool) -> CGFloat {
        compact ? 40 : 54
    }

    /// Rebuilds the keys if the layout changed (page or globe), otherwise just relabels them.
    func reload() {
        if engine.layout != builtLayout {
            rebuildKeys()
        }
        for row in buttons {
            for button in row {
                button.label = engine.label(for: button.kind)
            }
        }
        candidateBar.candidates = engine.candidates
    }

    private func rebuildKeys() {
        buttons.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        let layout = engine.layout
        buttons = layout.rows.map { row in
            row.keys.map { key in
                let button = KeyButton(kind: key.kind)
                configureActions(for: button)
                keyArea.addSubview(button)
                return button
            }
        }
        builtLayout = layout
        setNeedsLayout()
    }

    private func configureActions(for button: KeyButton) {
        switch button.kind {
        case .globe:
            if let globeTarget {
                button.addTarget(
                    globeTarget,
                    action: #selector(UIInputViewController.handleInputModeList(from:with:)),
                    for: .allTouchEvents
                )
            }
        case .delete:
            button.addTarget(self, action: #selector(deleteDown), for: .touchDown)
            button.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        default:
            button.addTarget(self, action: #selector(keyDown), for: .touchDown)
            button.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let compact = traitCollection.verticalSizeClass == .compact
        let keyRowHeight = rowHeight(compact: compact)
        candidateBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Self.candidateBarHeight)
        keyArea.frame = CGRect(x: 0, y: Self.candidateBarHeight, width: bounds.width,
                               height: bounds.height - Self.candidateBarHeight)

        let frames = engine.layout.frames(width: Double(bounds.width), rowHeight: Double(keyRowHeight))
        for (rowButtons, rowFrames) in zip(buttons, frames) {
            for (index, (button, frame)) in zip(rowButtons, rowFrames).enumerated() {
                let keyFrame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
                // Stretch the outermost keys' touch area into the row's inset, like the system
                // keyboard does (tapping left of A still types A). The drawn key doesn't move.
                var touchFrame = keyFrame
                if index == 0 {
                    touchFrame.size.width += touchFrame.minX
                    touchFrame.origin.x = 0
                }
                if index == rowButtons.count - 1 {
                    touchFrame.size.width = bounds.width - touchFrame.minX
                }
                button.frame = touchFrame
                button.keycapFrame = keyFrame.offsetBy(dx: -touchFrame.minX, dy: 0)
            }
        }
    }

    @objc private func keyDown() {
        UIDevice.current.playInputClick()
    }

    @objc private func keyUp(_ sender: KeyButton) {
        engine.press(sender.kind)
    }

    @objc private func deleteDown() {
        UIDevice.current.playInputClick()
        engine.press(.delete)
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                self?.engine.press(.delete)
            }
        }
    }

    @objc private func deleteUp() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }
}

final class KeyButton: UIControl {
    let kind: KeyKind

    var label: KeyLabel = .text("") {
        didSet { if label != oldValue { applyLabel() } }
    }

    /// Where the visible key sits inside the (possibly larger) touch area.
    var keycapFrame: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    private let keycap = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    private var isSpecial: Bool {
        if case .character = kind { return false }
        return kind != .space && kind != .longVowel
    }

    init(kind: KeyKind) {
        self.kind = kind
        super.init(frame: .zero)

        keycap.isUserInteractionEnabled = false
        keycap.layer.cornerRadius = 5
        keycap.layer.shadowColor = UIColor.black.cgColor
        keycap.layer.shadowOpacity = 0.3
        keycap.layer.shadowOffset = CGSize(width: 0, height: 1)
        keycap.layer.shadowRadius = 0
        addSubview(keycap)

        titleLabel.textAlignment = .center
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.6
        titleLabel.textColor = .label
        keycap.addSubview(titleLabel)

        iconView.contentMode = .center
        iconView.tintColor = .label
        keycap.addSubview(iconView)

        updateBackground()
        applyLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { updateBackground() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Gaps between keys are drawn, but still belong to a key's touch area.
        keycap.frame = keycapFrame.insetBy(dx: 3, dy: 5)
        titleLabel.frame = keycap.bounds.insetBy(dx: 2, dy: 0)
        iconView.frame = keycap.bounds
    }

    private func applyLabel() {
        switch label {
        case .text(let text):
            titleLabel.text = text
            titleLabel.isHidden = false
            iconView.isHidden = true
            let isLetter = text.count == 1 && !isSpecial
            titleLabel.font = .systemFont(ofSize: isLetter ? 23 : 16, weight: .regular)
        case .systemImage(let name):
            iconView.image = UIImage(
                systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            )
            iconView.isHidden = false
            titleLabel.isHidden = true
        }
    }

    private func updateBackground() {
        let special = isSpecial
        let pressed = isHighlighted
        keycap.backgroundColor = UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            switch (special, pressed, dark) {
            case (false, false, false): return .white
            case (false, false, true): return UIColor(white: 0.42, alpha: 1)
            case (true, true, false), (false, true, false): return UIColor(white: 0.82, alpha: 1)
            case (true, true, true), (false, true, true): return UIColor(white: 0.55, alpha: 1)
            case (true, false, false): return UIColor(red: 0.67, green: 0.69, blue: 0.73, alpha: 1)
            case (true, false, true): return UIColor(white: 0.27, alpha: 1)
            }
        }
    }
}

/// Horizontal strip of conversion choices (ひらがな / カタカナ for now).
final class CandidateBar: UIView {
    var onSelect: ((String) -> Void)?

    var candidates: [String] = [] {
        didSet { if candidates != oldValue { rebuild() } }
    }

    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        scrollView.showsHorizontalScrollIndicator = false
        addSubview(scrollView)
        stack.axis = .horizontal
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
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
        for candidate in candidates {
            var title = AttributedString(candidate)
            title.font = .systemFont(ofSize: 18)
            var configuration = UIButton.Configuration.plain()
            configuration.attributedTitle = title
            configuration.baseForegroundColor = .label
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)
            let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.onSelect?(candidate)
            })
            stack.addArrangedSubview(button)
        }
    }
}
