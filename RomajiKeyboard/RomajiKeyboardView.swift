import KeyboardCore
import UIKit

/// The romaji QWERTY keyboard: candidate bar on top, keys underneath. The candidate bar is
/// there in both languages so the keyboard's height doesn't change when switching either.
final class RomajiKeyboardView: UIView, UIInputViewAudioFeedback, KeyboardContentView {
    private let engine: KeyboardEngine
    private weak var globeTarget: UIInputViewController?
    private let candidateBar = CandidateBar()
    private let keyArea = UIView()
    private var buttons: [[RomajiKeyButton]] = []
    private var builtLayout: KeyboardLayout?
    private let deleteRepeater = KeyRepeater()

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
        engine.onChange = { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(showsGlobe: Bool) {
        engine.showsGlobe = showsGlobe
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
                let button = RomajiKeyButton(kind: key.kind)
                configureActions(for: button)
                keyArea.addSubview(button)
                return button
            }
        }
        builtLayout = layout
        setNeedsLayout()
    }

    private func configureActions(for button: RomajiKeyButton) {
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
        let rowHeight = KeyboardMetrics.rowHeight(compact: traitCollection.verticalSizeClass == .compact)
        let barHeight = KeyboardMetrics.candidateBarHeight
        candidateBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: barHeight)
        keyArea.frame = CGRect(x: 0, y: barHeight, width: bounds.width, height: bounds.height - barHeight)

        let frames = engine.layout.frames(width: Double(bounds.width), rowHeight: Double(rowHeight))
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

    @objc private func keyUp(_ sender: RomajiKeyButton) {
        engine.press(sender.kind)
    }

    @objc private func deleteDown() {
        UIDevice.current.playInputClick()
        deleteRepeater.start { [weak self] in self?.engine.press(.delete) }
    }

    @objc private func deleteUp() {
        deleteRepeater.stop()
    }
}

final class RomajiKeyButton: KeyButton {
    let kind: KeyKind

    init(kind: KeyKind) {
        self.kind = kind
        let isSpecial: Bool
        switch kind {
        case .character, .space, .longVowel: isSpecial = false
        default: isSpecial = true
        }
        super.init(isSpecial: isSpecial)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
