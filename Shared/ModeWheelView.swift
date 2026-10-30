import KeyboardCore
import UIKit

/// Follows a press on a board's mode key. A quick tap calls `onTap`. Dragging past the
/// threshold, or holding, opens the wheel; letting go over a slot picks it, and letting go
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
        let slot = ModeWheel.slot(dx: Double(point.x - start.x), dy: Double(point.y - start.y),
                                  leftHanded: host.settings.leftHandedWheel)
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
        let view = ModeWheelView(current: current(), theme: host.theme, leftHanded: host.settings.leftHandedWheel)
        view.frame = host.bounds
        host.addSubview(view)
        view.layout(around: start)
        view.highlight(selected)
        if host.animates {
            view.popIn()
        }
        wheel = view
        // The keys fade so the chips stand out.
        host.keyArea.alpha = 0.35
    }

    private func finish() {
        holdTimer?.invalidate()
        holdTimer = nil
        wheel?.removeFromSuperview()
        wheel = nil
        host?.keyArea.alpha = 1
        start = nil
        selected = nil
    }
}

/// The mode wheel: small chips around the finger, each sitting in the direction you'd swipe to
/// pick it. They're always in the same places, whatever the current mode, which only gets a dot.
final class ModeWheelView: UIView {
    private let current: ModeWheelSlot
    private let theme: KeyboardTheme
    private let leftHanded: Bool
    private var chips: [ModeWheelSlot: UILabel] = [:]
    private var dots: [ModeWheelSlot: UIView] = [:]
    private static let chipSize = CGSize(width: 36, height: 28)
    private static let radius: CGFloat = 64

    init(current: ModeWheelSlot, theme: KeyboardTheme, leftHanded: Bool) {
        self.current = current
        self.theme = theme
        self.leftHanded = leftHanded
        super.init(frame: .zero)
        isUserInteractionEnabled = false

        for slot in ModeWheel.slots {
            let chip = UILabel()
            chip.text = slot.label
            chip.textAlignment = .center
            chip.font = .systemFont(ofSize: slot == .nextKeyboard ? 15 : 13, weight: .semibold)
            chip.adjustsFontSizeToFitWidth = true
            chip.minimumScaleFactor = 0.7
            chip.layer.cornerRadius = 8
            chip.layer.masksToBounds = false
            chip.layer.shadowColor = UIColor.black.cgColor
            chip.layer.shadowOpacity = 0.25
            chip.layer.shadowRadius = 2
            chip.layer.shadowOffset = CGSize(width: 0, height: 1)
            chip.accessibilityLabel = slot.accessibilityName
            addSubview(chip)
            chips[slot] = chip
            if slot == current {
                let dot = UIView()
                dot.layer.cornerRadius = 2
                chip.addSubview(dot)
                dots[slot] = dot
            }
        }
        highlight(nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Places the chips around where the finger touched down. Near an edge, the whole wheel
    /// slides over just enough to fit, keeping its shape.
    func layout(around point: CGPoint) {
        let size = Self.chipSize
        let origins = ModeWheel.slots.map { slot -> (ModeWheelSlot, CGPoint) in
            let angle = CGFloat(ModeWheel.angle(of: slot, leftHanded: leftHanded))
            return (slot, CGPoint(
                x: point.x + cos(angle) * Self.radius - size.width / 2,
                y: max(point.y - sin(angle) * Self.radius - size.height / 2, 2)
            ))
        }
        let minX = origins.map(\.1.x).min() ?? 0
        let maxX = origins.map(\.1.x).max() ?? 0
        let shift = minX < 2 ? 2 - minX : (maxX > bounds.width - size.width - 2 ? bounds.width - size.width - 2 - maxX : 0)
        for (slot, origin) in origins {
            let chip = chips[slot]!
            chip.bounds = CGRect(origin: .zero, size: size)
            chip.center = CGPoint(x: origin.x + shift + size.width / 2, y: origin.y + size.height / 2)
            dots[slot]?.frame = CGRect(x: size.width / 2 - 2, y: size.height - 7, width: 4, height: 4)
        }
    }

    /// The chips pop out from the finger one after another, left to right.
    func popIn() {
        for (index, slot) in ModeWheel.order(leftHanded: leftHanded).enumerated() {
            guard let chip = chips[slot] else { continue }
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.5
            pop.toValue = 1
            pop.damping = 16
            pop.stiffness = 320
            pop.duration = pop.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.12
            for animation in [pop, fade] as [CAAnimation] {
                animation.beginTime = CACurrentMediaTime() + Double(index) * 0.018
                animation.fillMode = .backwards
            }
            chip.layer.add(pop, forKey: "pop")
            chip.layer.add(fade, forKey: "fade")
        }
    }

    func highlight(_ slot: ModeWheelSlot?) {
        for (candidate, chip) in chips {
            let isOn = candidate == slot
            chip.backgroundColor = isOn ? theme.accent : theme.key
            chip.textColor = isOn ? .white : theme.text
            chip.transform = isOn ? CGAffineTransform(scaleX: 1.15, y: 1.15) : .identity
            dots[candidate]?.backgroundColor = isOn ? .white : theme.accent
        }
    }
}
