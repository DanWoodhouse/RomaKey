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

    var theme = KeyboardTheme.named(.system) {
        didSet {
            applyColors()
            applyLabel()
        }
    }

    /// A small label in the top corner: the extra a swipe up or hold types (q → 1, a → @).
    var hint: String? {
        didSet {
            hintLabel.text = hint
            hintLabel.isHidden = hint == nil
            if (hint == nil) != (oldValue == nil) {
                setNeedsLayout()
            }
        }
    }

    /// Function keys (shift, delete, …) are drawn darker than character keys.
    let isSpecial: Bool
    /// Return: drawn in the accent colour when the theme asks for it.
    var isPrimaryAction = false {
        didSet { applyColors() }
    }
    private let keycap = UIView()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()
    private let hintLabel = UILabel()

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
        keycap.addSubview(titleLabel)

        iconView.contentMode = .center
        keycap.addSubview(iconView)

        hintLabel.font = .systemFont(ofSize: 9, weight: .medium)
        hintLabel.textAlignment = .right
        hintLabel.isHidden = true
        keycap.addSubview(hintLabel)

        applyColors()
        applyLabel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet {
            applyColors()
            if isHighlighted != oldValue {
                animatePress()
            }
        }
    }

    /// The key sinks a little under the finger and springs back when let go.
    private func animatePress() {
        guard theme.animates else { return }
        let scale = CASpringAnimation(keyPath: "transform.scale")
        scale.fromValue = keycap.layer.presentation()?.value(forKeyPath: "transform.scale") ?? (isHighlighted ? 1 : 0.95)
        scale.toValue = isHighlighted ? 0.95 : 1
        scale.damping = isHighlighted ? 30 : 14
        scale.stiffness = 400
        scale.duration = isHighlighted ? 0.08 : scale.settlingDuration
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = !isHighlighted
        keycap.layer.add(scale, forKey: "press")
    }

    /// Changes the label; animated, it fades across with a small pop, as when the mode changes.
    func setLabel(_ newLabel: KeyLabel, animated: Bool) {
        guard newLabel != label else { return }
        label = newLabel
        guard animated else { return }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.18
        keycap.layer.add(fade, forKey: "label")
        let pop = CAKeyframeAnimation(keyPath: "transform.scale")
        pop.values = [1.14, 1]
        pop.duration = 0.3
        pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        titleLabel.layer.add(pop, forKey: "pop")
        iconView.layer.add(pop, forKey: "pop")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Gaps between keys are drawn, but still belong to a key's touch area.
        // Bounds and centre rather than frame, so the press animation's scale never distorts it.
        let capFrame = keycapFrame.insetBy(dx: theme.keyInset.width, dy: theme.keyInset.height)
        keycap.bounds = CGRect(origin: .zero, size: capFrame.size)
        keycap.center = CGPoint(x: capFrame.midX, y: capFrame.midY)
        // With a hint in the corner, the letter sits a little lower to leave it room.
        titleLabel.frame = keycap.bounds.insetBy(dx: 2, dy: 0).offsetBy(dx: 0, dy: hint == nil ? 0 : 3)
        iconView.frame = keycap.bounds
        hintLabel.frame = CGRect(x: 0, y: 1, width: keycap.bounds.width - 4, height: 12)
    }

    /// The visible key, in `view`'s coordinates (for popups and guides).
    func keycapFrame(in view: UIView) -> CGRect {
        keycap.convert(keycap.bounds, to: view)
    }

    private func applyLabel() {
        switch label {
        case .text(let text):
            titleLabel.text = text
            titleLabel.isHidden = false
            iconView.isHidden = true
            let isSingleCharacter = text.count == 1 && !isSpecial
            titleLabel.font = theme.font(isSingleCharacter ? 23 : 16)
        case .systemImage(let name):
            iconView.image = UIImage(
                systemName: name,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            )
            iconView.isHidden = false
            titleLabel.isHidden = true
        }
    }

    private func applyColors() {
        let accented = isPrimaryAction && theme.accentReturnKey
        if isHighlighted {
            keycap.backgroundColor = theme.pressedKey
        } else if accented {
            keycap.backgroundColor = theme.accent
        } else {
            keycap.backgroundColor = isSpecial ? theme.specialKey : theme.key
        }
        titleLabel.textColor = accented && !isHighlighted ? .white : theme.text
        iconView.tintColor = titleLabel.textColor
        keycap.layer.cornerRadius = theme.keyCornerRadius
        keycap.layer.shadowOpacity = theme.keyShadows ? 0.3 : 0
        keycap.layer.borderWidth = theme.keyOutlines ? 1 : 0
        keycap.layer.borderColor = theme.secondaryText.withAlphaComponent(0.35).resolvedColor(with: traitCollection).cgColor
        setNeedsLayout()
        hintLabel.textColor = theme.secondaryText
    }
}

/// The enlarged letter shown above a key while it's held.
final class KeyPopupView: UIView {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 2
        layer.shadowOffset = CGSize(width: 0, height: 1)
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 32)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Shows `text` in a cap one key-height above `keycap`, kept inside `bounds`.
    func show(_ text: String, above keycap: CGRect, in bounds: CGRect, theme: KeyboardTheme) {
        let width = keycap.width + 16
        let height = keycap.height * 1.1
        var frame = CGRect(x: keycap.midX - width / 2, y: keycap.minY - height - 2, width: width, height: height)
        frame.origin.x = min(max(frame.minX, bounds.minX + 2), bounds.maxX - width - 2)
        frame.origin.y = max(frame.minY, bounds.minY)
        self.frame = frame
        label.frame = CGRect(origin: .zero, size: frame.size)
        label.text = text
        label.font = theme.font(32)
        label.textColor = theme.text
        backgroundColor = theme.panel
        isHidden = false
    }

    func hide() {
        isHidden = true
    }
}

/// Plays the key click and haptic tap, as the settings allow.
final class KeyFeedback {
    var playsSounds = true
    /// Haptics only work when the keyboard has Full Access.
    var playsHaptics = false
    private lazy var generator = UIImpactFeedbackGenerator(style: .light)

    func keyDown() {
        if playsSounds {
            UIDevice.current.playInputClick()
        }
        if playsHaptics {
            generator.impactOccurred()
        }
    }
}

/// Calls an action on touch down, then repeatedly while the key is held (for delete).
/// The action is told how many times it has repeated, so it can speed up.
final class KeyRepeater {
    private var timer: Timer?

    func start(_ action: @escaping (_ repeatCount: Int) -> Void) {
        stop()
        action(0)
        timer = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            var count = 0
            self?.timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                count += 1
                action(count)
            }
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

/// Long-press the space bar, then slide sideways to move the cursor, like the system keyboard.
final class SpaceBarCursor: NSObject {
    private static let pointsPerCharacter: CGFloat = 9

    var isEnabled: Bool {
        get { gesture.isEnabled }
        set { gesture.isEnabled = newValue }
    }

    private let gesture = UILongPressGestureRecognizer()
    private let onActiveChange: (Bool) -> Void
    private let onMove: (Int) -> Void
    private var anchorX: CGFloat = 0

    init(button: UIControl, onActiveChange: @escaping (Bool) -> Void, onMove: @escaping (Int) -> Void) {
        self.onActiveChange = onActiveChange
        self.onMove = onMove
        super.init()
        gesture.minimumPressDuration = 0.35
        gesture.allowableMovement = .greatestFiniteMagnitude
        gesture.addTarget(self, action: #selector(handle(_:)))
        button.addGestureRecognizer(gesture)
    }

    @objc private func handle(_ gesture: UILongPressGestureRecognizer) {
        let x = gesture.location(in: gesture.view).x
        switch gesture.state {
        case .began:
            anchorX = x
            onActiveChange(true)
        case .changed:
            let steps = Int((x - anchorX) / Self.pointsPerCharacter)
            if steps != 0 {
                onMove(steps)
                anchorX += CGFloat(steps) * Self.pointsPerCharacter
            }
        default:
            onActiveChange(false)
        }
    }
}
