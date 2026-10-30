import KeyboardCore
import UIKit

/// The 12-key flick keyboard, laid out like the iPhone's built-in 日本語かな keyboard.
/// Tap a key for its centre kana (あ), or press and slide left/up/right/down for the rest (いうえお).
/// The mode key sits where 🌐 is on the system keyboard.
final class FlickKeyboardView: KeyboardViewBase {
    /// The mode key was tapped: back to the ローマ字 board.
    var onModeKeyTap: (() -> Void)?

    private let engine: FlickKeyboardEngine
    private let guide = FlickGuideView()
    private var buttons: [FlickKeyButton] = []
    private var builtLayout: FlickLayout?
    private let deleteRepeater = KeyRepeater()
    private var spaceBarCursor: SpaceBarCursor?
    private var modeWheel: ModeWheelTracker?
    /// The host app's text field; typing goes back here when a search ends.
    private let documentOutput: TextOutput?

    init(engine: FlickKeyboardEngine, feedback: KeyFeedback) {
        self.engine = engine
        documentOutput = engine.output
        super.init(feedback: feedback)
        addSubview(guide)
        engine.onChange = { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func settingsDidChange() {
        engine.settings = settings
        for button in buttons {
            button.theme = theme
        }
        spaceBarCursor?.isEnabled = settings.spaceBarCursor
    }

    override func selectCandidate(_ candidate: Candidate) {
        engine.selectCandidate(candidate)
    }

    override func insertWord(_ text: String) {
        engine.insertWord(text)
    }

    override func insertDirectly(_ text: String) {
        engine.insertDirectly(text)
    }

    override func deleteFromPanel() {
        engine.press(.delete)
    }

    override func routeTyping(to output: TextOutput?) {
        engine.commitComposition()
        engine.output = output ?? documentOutput
    }

    override var searchLanguage: String { "ja" }

    override func reload() {
        if engine.layout != builtLayout {
            rebuildKeys()
        }
        for button in buttons {
            button.label = engine.label(for: button.kind)
        }
        showCandidates(engine.candidates, showsMeanings: settings.showMeanings, placeholder: "")
    }

    private func rebuildKeys() {
        buttons.forEach { $0.removeFromSuperview() }
        let layout = engine.layout
        buttons = layout.cells.map { cell in
            let button = FlickKeyButton(kind: cell.kind)
            button.theme = theme
            configureActions(for: button)
            keyArea.addSubview(button)
            return button
        }
        builtLayout = layout
        setNeedsLayout()
    }

    private func configureActions(for button: FlickKeyButton) {
        switch button.kind {
        case .modeKey:
            modeWheel = ModeWheelTracker(
                button: button,
                host: self,
                current: { .kana },
                onTap: { [weak self] in self?.onModeKeyTap?() }
            )
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

        if button.kind == .space {
            let cursor = SpaceBarCursor(
                button: button,
                onActiveChange: { [weak self] active in self?.setTrackpadActive(active) },
                onMove: { [weak self] offset in self?.engine.moveCursor(by: offset) }
            )
            cursor.isEnabled = settings.spaceBarCursor
            spaceBarCursor = cursor
        }
    }

    override func layoutKeys(rowHeight: CGFloat) {
        guide.frame = bounds
        let frames = engine.layout.frames(width: Double(bounds.width), rowHeight: Double(rowHeight))
        for (button, frame) in zip(buttons, frames) {
            button.frame = CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
            button.keycapFrame = button.bounds
        }
    }

    // MARK: - Flick keys

    @objc private func flickBegan(_ sender: FlickKeyButton, forEvent event: UIEvent) {
        feedback.keyDown()
        hideEntry()
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
        return FlickDirection(
            dx: Double(point.x - start.x),
            dy: Double(point.y - start.y),
            threshold: settings.flickSensitivity.threshold
        )
    }

    private func showGuide(for button: FlickKeyButton, direction: FlickDirection) {
        guard case .flick(let key) = button.kind else { return }
        guide.show(key, around: button.convert(button.bounds, to: self), selected: direction, theme: theme)
    }

    // MARK: - Other keys

    @objc private func keyDown() {
        feedback.keyDown()
    }

    @objc private func keyUp(_ sender: FlickKeyButton) {
        hideEntry()
        engine.press(sender.kind)
    }

    @objc private func deleteDown() {
        feedback.keyDown()
        hideEntry()
        deleteRepeater.start { [weak self] _ in self?.engine.press(.delete) }
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

    func show(_ key: FlickKey, around keyFrame: CGRect, selected: FlickDirection, theme: KeyboardTheme) {
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
            tile.backgroundColor = isSelected ? theme.accent : theme.panel
            tile.textColor = isSelected ? .white : theme.text
        }
    }

    func hide() {
        isHidden = true
    }
}
