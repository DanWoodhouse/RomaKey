import KeyboardCore
import UIKit

/// The 12-key flick keyboard, laid out like the iPhone's built-in 日本語かな keyboard.
/// Tap a key for its centre kana (あ), or press and slide left/up/right/down for the rest (いうえお).
final class FlickKeyboardView: UIView, UIInputViewAudioFeedback, KeyboardContentView {
    private let engine: FlickKeyboardEngine
    private weak var globeTarget: UIInputViewController?
    private let candidateBar = CandidateBar()
    private let keyArea = UIView()
    private let guide = FlickGuideView()
    private var buttons: [FlickKeyButton] = []
    private var builtLayout: FlickLayout?
    private let deleteRepeater = KeyRepeater()

    var enableInputClicksWhenVisible: Bool { true }

    init(engine: FlickKeyboardEngine, globeTarget: UIInputViewController) {
        self.engine = engine
        self.globeTarget = globeTarget
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(candidateBar)
        addSubview(keyArea)
        addSubview(guide)
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
        // The grid always keeps its globe key, so its shape is the same on every phone.
    }

    func reload() {
        if engine.layout != builtLayout {
            rebuildKeys()
        }
        for button in buttons {
            button.label = engine.label(for: button.kind)
        }
        candidateBar.candidates = engine.candidates
    }

    private func rebuildKeys() {
        buttons.forEach { $0.removeFromSuperview() }
        let layout = engine.layout
        buttons = layout.cells.map { cell in
            let button = FlickKeyButton(kind: cell.kind)
            configureActions(for: button)
            keyArea.addSubview(button)
            return button
        }
        builtLayout = layout
        setNeedsLayout()
    }

    private func configureActions(for button: FlickKeyButton) {
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
        case .flick:
            button.addTarget(self, action: #selector(flickBegan(_:forEvent:)), for: .touchDown)
            button.addTarget(self, action: #selector(flickMoved(_:forEvent:)), for: [.touchDragInside, .touchDragOutside])
            button.addTarget(self, action: #selector(flickEnded(_:forEvent:)), for: [.touchUpInside, .touchUpOutside])
            button.addTarget(self, action: #selector(flickCancelled(_:)), for: .touchCancel)
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
        guide.frame = bounds

        let frames = engine.layout.frames(width: Double(bounds.width), rowHeight: Double(rowHeight))
        for (button, frame) in zip(buttons, frames) {
            button.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            button.keycapFrame = button.bounds
        }
    }

    // MARK: - Flick keys

    @objc private func flickBegan(_ sender: FlickKeyButton, forEvent event: UIEvent) {
        UIDevice.current.playInputClick()
        sender.touchStart = event.touches(for: sender)?.first?.location(in: self)
        showGuide(for: sender, direction: .center)
    }

    @objc private func flickMoved(_ sender: FlickKeyButton, forEvent event: UIEvent) {
        showGuide(for: sender, direction: direction(of: sender, event: event))
    }

    @objc private func flickEnded(_ sender: FlickKeyButton, forEvent event: UIEvent) {
        let flickDirection = direction(of: sender, event: event)
        sender.touchStart = nil
        guide.hide()
        engine.press(sender.kind, direction: flickDirection)
    }

    @objc private func flickCancelled(_ sender: FlickKeyButton) {
        sender.touchStart = nil
        guide.hide()
    }

    private func direction(of sender: FlickKeyButton, event: UIEvent) -> FlickDirection {
        guard let start = sender.touchStart,
              let point = event.touches(for: sender)?.first?.location(in: self) else { return .center }
        return FlickDirection(dx: Double(point.x - start.x), dy: Double(point.y - start.y))
    }

    private func showGuide(for button: FlickKeyButton, direction: FlickDirection) {
        guard case .flick(let key) = button.kind else { return }
        guide.show(key, around: button.convert(button.bounds, to: self), selected: direction)
    }

    // MARK: - Other keys

    @objc private func keyDown() {
        UIDevice.current.playInputClick()
    }

    @objc private func keyUp(_ sender: FlickKeyButton) {
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

final class FlickKeyButton: KeyButton {
    let kind: FlickKeyKind
    /// Where the current touch began, in the keyboard view's coordinates.
    var touchStart: CGPoint?

    init(kind: FlickKeyKind) {
        self.kind = kind
        let isSpecial: Bool
        switch kind {
        case .flick, .modifier, .caseToggle: isSpecial = false
        default: isSpecial = true
        }
        super.init(isSpecial: isSpecial)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// The cross of kana shown while a key is held, highlighting where the flick will land.
final class FlickGuideView: UIView {
    private var tiles: [FlickDirection: UILabel] = [:]

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isHidden = true
        for direction in FlickDirection.allCases {
            let tile = UILabel()
            tile.textAlignment = .center
            tile.font = .systemFont(ofSize: 24)
            tile.layer.cornerRadius = 6
            tile.clipsToBounds = true
            addSubview(tile)
            tiles[direction] = tile
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ key: FlickKey, around keyFrame: CGRect, selected: FlickDirection) {
        isHidden = false
        for (direction, tile) in tiles {
            guard let text = key.outputs[direction] else {
                tile.isHidden = true
                continue
            }
            var frame = keyFrame
            switch direction {
            case .center: break
            case .left: frame.origin.x -= keyFrame.width
            case .right: frame.origin.x += keyFrame.width
            case .up: frame.origin.y -= keyFrame.height
            case .down: frame.origin.y += keyFrame.height
            }
            tile.isHidden = false
            tile.text = text
            tile.frame = frame.insetBy(dx: 2, dy: 2).intersection(bounds)
            let isSelected = direction == selected
            tile.backgroundColor = isSelected ? .systemBlue : .secondarySystemBackground
            tile.textColor = isSelected ? .white : .label
        }
    }

    func hide() {
        isHidden = true
    }
}
