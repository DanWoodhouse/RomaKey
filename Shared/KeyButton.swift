import KeyboardCore
import UIKit

/// A key: a rounded keycap drawn inside a (possibly larger) touch area.
class KeyButton: UIControl {
    var label: KeyLabel = .text("") {
        didSet { if label != oldValue { applyLabel() } }
    }

    /// Where the visible key sits inside the touch area.
    var keycapFrame: CGRect = .zero {
        didSet { setNeedsLayout() }
    }

    /// Function keys (shift, delete, …) are drawn darker than character keys.
    private let isSpecial: Bool
    private let keycap = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    init(isSpecial: Bool) {
        self.isSpecial = isSpecial
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
            let isSingleCharacter = text.count == 1 && !isSpecial
            titleLabel.font = .systemFont(ofSize: isSingleCharacter ? 23 : 16, weight: .regular)
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

/// Calls an action on touch down, then repeatedly while the key is held (for delete).
final class KeyRepeater {
    private var timer: Timer?

    func start(_ action: @escaping () -> Void) {
        stop()
        action()
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in action() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit {
        stop()
    }
}
