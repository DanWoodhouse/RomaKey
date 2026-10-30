import KeyboardCore
import UIKit

/// Follows a press on a board's mode key. A quick tap calls `onTap`. Dragging past the
/// threshold, or holding, opens the half wheel; letting go over a slot picks it, and letting go
/// without one closes the wheel. A fast swipe picks a slot before the wheel has even shown.
final class ModeWheelTracker: NSObject {
    private weak var host: KeyboardViewBase?
    private let current: () -> ModeWheelSlot
    private let onTap: () -> Void
    private var start: CGPoint?
    private var wheel: ModeWheelView?
    private var holdTimer: Timer?
    private var selected: ModeWheelSlot?
    private static let holdDelay: TimeInterval = 0.3

    init(button: KeyButton, host: KeyboardViewBase, current: @escaping () -> ModeWheelSlot, onTap: @escaping () -> Void) {
        self.host = host
        self.current = current
        self.onTap = onTap
        super.init()
        button.addTarget(self, action: #selector(touchDown(_:forEvent:)), for: .touchDown)
        button.addTarget(self, action: #selector(touchMoved(_:forEvent:)), for: [.touchDragInside, .touchDragOutside])
        button.addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside])
        button.addTarget(self, action: #selector(touchCancelled), for: .touchCancel)
        button.accessibilityHint = "Tap to switch mode. Press and drag for あ, EN, 辞, かな or the next keyboard."
    }

    @objc private func touchDown(_ sender: KeyButton, forEvent event: UIEvent) {
        guard let host else { return }
        host.feedback.keyDown()
        host.hideEntry()
        start = event.touches(for: sender)?.first?.location(in: host)
        selected = nil
        holdTimer?.invalidate()
        holdTimer = Timer.scheduledTimer(withTimeInterval: Self.holdDelay, repeats: false) { [weak self] _ in
            self?.showWheel()
        }
    }

    @objc private func touchMoved(_ sender: KeyButton, forEvent event: UIEvent) {
        guard let host, let start, let point = event.touches(for: sender)?.first?.location(in: host) else { return }
        let slot = ModeWheel.slot(dx: Double(point.x - start.x), dy: Double(point.y - start.y))
        if slot != nil {
            showWheel()
        }
        if slot != selected {
            selected = slot
            wheel?.highlight(slot)
            if slot != nil {
                host.feedback.keyDown()
            }
        }
    }

    @objc private func touchUp() {
        let slot = selected
        let wasOpen = wheel != nil
        finish()
        if let slot {
            host?.onModeWheel?(slot)
        } else if !wasOpen {
            onTap()
        }
    }

    @objc private func touchCancelled() {
        finish()
    }

    private func showWheel() {
        holdTimer?.invalidate()
        guard wheel == nil, let host, let start else { return }
        let view = ModeWheelView(current: current(), theme: host.theme)
        view.frame = host.bounds
        host.addSubview(view)
        view.layout(around: start)
        view.highlight(selected)
        wheel = view
    }

    private func finish() {
        holdTimer?.invalidate()
        holdTimer = nil
        wheel?.removeFromSuperview()
        wheel = nil
        start = nil
        selected = nil
    }
}

/// The half wheel drawn above the mode key. The slots are always in the same places, whatever
/// the current mode: the current one is only outlined, never moved.
final class ModeWheelView: UIView {
    private let current: ModeWheelSlot
    private let theme: KeyboardTheme
    private let disc = CAShapeLayer()
    private var slotLabels: [ModeWheelSlot: UILabel] = [:]
    private let nameLabel = UILabel()
    private static let slotSize: CGFloat = 46

    init(current: ModeWheelSlot, theme: KeyboardTheme) {
        self.current = current
        self.theme = theme
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        disc.shadowColor = UIColor.black.cgColor
        disc.shadowOpacity = 0.3
        disc.shadowRadius = 6
        disc.shadowOffset = .zero
        layer.addSublayer(disc)

        for slot in ModeWheel.slots {
            let label = UILabel()
            label.text = slot.label
            label.textAlignment = .center
            label.font = .systemFont(ofSize: slot == .nextKeyboard ? 22 : 18, weight: .medium)
            label.adjustsFontSizeToFitWidth = true
            label.minimumScaleFactor = 0.7
            label.layer.cornerRadius = Self.slotSize / 2
            label.clipsToBounds = true
            label.layer.borderWidth = slot == current ? 2 : 0
            addSubview(label)
            slotLabels[slot] = label
        }

        nameLabel.textAlignment = .center
        nameLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nameLabel.textColor = theme.secondaryText
        addSubview(nameLabel)
        highlight(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Centres the wheel on where the finger touched down, moved sideways only as far as it
    /// takes to stay on screen. Call once added to the keyboard, so colours match light or dark mode.
    func layout(around point: CGPoint) {
        disc.fillColor = theme.panel.resolvedColor(with: traitCollection).cgColor
        let outline = theme.accent.resolvedColor(with: traitCollection).cgColor
        slotLabels.values.forEach { $0.layer.borderColor = outline }

        let margin: CGFloat = 4
        let radius = max(min(130, point.y - margin, (bounds.width - 2 * margin) / 2), Self.slotSize)
        let centre = CGPoint(
            x: min(max(point.x, radius + margin), bounds.width - radius - margin),
            y: point.y
        )
        let path = UIBezierPath(arcCenter: centre, radius: radius, startAngle: .pi, endAngle: 0, clockwise: true)
        path.close()
        disc.path = path.cgPath

        let slotRadius = radius - Self.slotSize / 2 - 6
        for (slot, label) in slotLabels {
            let angle = CGFloat(ModeWheel.angle(of: slot))
            label.frame = CGRect(
                x: centre.x + cos(angle) * slotRadius - Self.slotSize / 2,
                y: centre.y - sin(angle) * slotRadius - Self.slotSize / 2,
                width: Self.slotSize,
                height: Self.slotSize
            )
        }
        nameLabel.frame = CGRect(x: centre.x - 70, y: centre.y - 42, width: 140, height: 16)
    }

    func highlight(_ slot: ModeWheelSlot?) {
        for (candidate, label) in slotLabels {
            let isOn = candidate == slot
            label.backgroundColor = isOn ? theme.accent : theme.key
            label.textColor = isOn ? .white : theme.text
        }
        nameLabel.text = slot?.accessibilityName
    }
}
