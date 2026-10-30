import KeyboardCore
import UIKit

/// The romaji QWERTY keyboard. Switching between あ, EN and 辞 only relabels keys; the candidate
/// bar is there in every mode, so the keyboard's height doesn't change either.
final class RomajiKeyboardView: KeyboardViewBase {
    private let engine: KeyboardEngine
    private weak var globeTarget: UIInputViewController?
    private var buttons: [[RomajiKeyButton]] = []
    private var builtLayout: KeyboardLayout?
    private let popup = KeyPopupView()
    private let deleteRepeater = KeyRepeater()
    private var spaceBarCursor: SpaceBarCursor?
    private var modeMenu: ModeMenuView?
    private var accentPicker: AccentPickerView?
    /// The host app's text field; typing goes back here when a search ends.
    private let documentOutput: TextOutput?

    init(engine: KeyboardEngine, globeTarget: UIInputViewController, feedback: KeyFeedback) {
        self.engine = engine
        self.globeTarget = globeTarget
        documentOutput = engine.output
        super.init(feedback: feedback)
        addSubview(popup)
        engine.onChange = { [weak self] in self?.reload() }
        reload()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update(showsGlobe: Bool) {
        engine.showsGlobe = showsGlobe
    }

    override func settingsDidChange() {
        engine.settings = settings
        for button in buttons.joined() {
            button.theme = theme
        }
        spaceBarCursor?.isEnabled = settings.spaceBarCursor
    }

    override func textDidChange() {
        engine.textDidChange()
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

    override var searchLanguage: String {
        engine.mode == .english ? "en" : "ja"
    }

    /// Rebuilds the keys if the layout changed (page or globe), otherwise just relabels them.
    override func reload() {
        if engine.layout != builtLayout {
            rebuildKeys()
        }
        for button in buttons.joined() {
            button.label = engine.label(for: button.kind)
        }
        showCandidates(
            engine.candidates,
            showsMeanings: settings.showMeanings || engine.mode == .dictionary,
            placeholder: placeholder
        )
    }

    private var placeholder: String {
        guard engine.mode == .dictionary else { return "" }
        if engine.dictionary == nil { return "辞書を読み込み中… · Loading dictionary…" }
        return engine.englishQuery.isEmpty ? "辞書 · Type an English word" : "No matches"
    }

    private func rebuildKeys() {
        buttons.joined().forEach { $0.removeFromSuperview() }
        let layout = engine.layout
        buttons = layout.rows.map { row in
            row.keys.map { key in
                let button = RomajiKeyButton(kind: key.kind)
                button.theme = theme
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
            button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
            button.addTarget(self, action: #selector(keyUp(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(keyReleased), for: [.touchUpOutside, .touchCancel, .touchDragExit])
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
        if case .character = button.kind {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(characterKeyLongPressed(_:)))
            press.minimumPressDuration = 0.35
            button.addGestureRecognizer(press)
        }
        if button.kind == .languageToggle {
            let press = UILongPressGestureRecognizer(target: self, action: #selector(languageKeyLongPressed(_:)))
            press.minimumPressDuration = 0.4
            button.addGestureRecognizer(press)
        }
    }

    override func layoutKeys(rowHeight: CGFloat) {
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

    // MARK: - Keys

    @objc private func keyDown(_ sender: RomajiKeyButton) {
        feedback.keyDown()
        let showsPopup = settings.keyPopups && traitCollection.verticalSizeClass != .compact
        if showsPopup, case .character = sender.kind, case .text(let text) = sender.label {
            popup.show(text, above: sender.keycapFrame(in: self), in: bounds, theme: theme)
        }
    }

    @objc private func keyUp(_ sender: RomajiKeyButton) {
        popup.hide()
        hideEntry()
        engine.press(sender.kind)
    }

    @objc private func keyReleased() {
        popup.hide()
    }

    @objc private func deleteDown() {
        feedback.keyDown()
        hideEntry()
        // After about a second of holding, delete whole words.
        deleteRepeater.start { [weak self] repeatCount in
            if repeatCount < 12 {
                self?.engine.press(.delete)
            } else {
                self?.engine.deleteWordBackward()
            }
        }
    }

    @objc private func deleteUp() {
        deleteRepeater.stop()
    }

    // MARK: - Accents

    /// Hold a letter for é, ü, ñ… then slide to one and let go. English and 辞書 only: Japanese
    /// romaji has no accents.
    @objc private func characterKeyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            popup.hide()
            guard engine.mode != .japanese, engine.page == .letters,
                  let key = gesture.view as? RomajiKeyButton, case .text(let letter) = key.label else { return }
            let options = Accents.alternatives(for: letter)
            guard !options.isEmpty else {
                // No accents: behave like a normal (slow) tap.
                engine.press(key.kind)
                return
            }
            let picker = AccentPickerView(options: options, theme: theme)
            picker.place(above: key.keycapFrame(in: self), in: bounds)
            addSubview(picker)
            accentPicker = picker
        case .changed:
            accentPicker?.highlight(atX: gesture.location(in: accentPicker).x)
        case .ended:
            if let choice = accentPicker?.selected {
                // The engine applies shift, so pass the lowercase letter.
                engine.press(.character(choice.lowercased()))
            }
            fallthrough
        default:
            accentPicker?.removeFromSuperview()
            accentPicker = nil
        }
    }

    // MARK: - Mode menu

    @objc private func languageKeyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let key = gesture.view as? RomajiKeyButton else { return }
            feedback.keyDown()
            let menu = ModeMenuView(current: engine.mode, theme: theme)
            menu.onSelect = { [weak self] mode in
                self?.engine.setMode(mode)
                self?.dismissModeMenu()
            }
            menu.onDismiss = { [weak self] in self?.dismissModeMenu() }
            menu.frame = bounds
            addSubview(menu)
            menu.layoutPanel(above: key.keycapFrame(in: self))
            modeMenu = menu
        case .changed:
            modeMenu?.highlight(at: gesture.location(in: modeMenu))
        case .ended:
            // Slide-and-release picks the highlighted mode; otherwise the menu stays open for a tap.
            modeMenu?.selectHighlighted()
        default:
            break
        }
    }

    private func dismissModeMenu() {
        modeMenu?.removeFromSuperview()
        modeMenu = nil
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

/// Long-press the language key to jump straight to あ, EN or 辞.
private final class ModeMenuView: UIView {
    var onSelect: ((InputMode) -> Void)?
    var onDismiss: (() -> Void)?

    private let panel = UIStackView()
    private var options: [(mode: InputMode, view: UILabel)] = []
    private var highlighted: InputMode?
    private let theme: KeyboardTheme

    init(current: InputMode, theme: KeyboardTheme) {
        self.theme = theme
        super.init(frame: .zero)
        panel.axis = .horizontal
        panel.distribution = .fillEqually
        panel.spacing = 4
        panel.layoutMargins = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        panel.isLayoutMarginsRelativeArrangement = true
        panel.backgroundColor = theme.panel
        panel.layer.cornerRadius = 10
        panel.layer.shadowColor = UIColor.black.cgColor
        panel.layer.shadowOpacity = 0.3
        panel.layer.shadowRadius = 4
        addSubview(panel)

        let names: [InputMode: String] = [.japanese: "あ 日本語", .english: "EN English", .dictionary: "辞 辞書"]
        for mode in InputMode.allCases {
            let label = UILabel()
            label.text = names[mode]
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 15, weight: mode == current ? .semibold : .regular)
            label.layer.cornerRadius = 7
            label.clipsToBounds = true
            label.isUserInteractionEnabled = true
            label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(optionTapped(_:))))
            panel.addArrangedSubview(label)
            options.append((mode, label))
        }
        updateColors()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(backgroundTapped(_:))))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func layoutPanel(above key: CGRect) {
        let width = min(bounds.width - 16, 300)
        let height: CGFloat = 46
        let x = min(max(key.midX - width / 2, 8), bounds.width - width - 8)
        panel.frame = CGRect(x: x, y: max(key.minY - height - 6, 0), width: width, height: height)
    }

    func highlight(at point: CGPoint) {
        highlighted = options.first { panel.convert($0.view.frame, to: self).contains(point) }?.mode
        updateColors()
    }

    func selectHighlighted() {
        if let highlighted {
            onSelect?(highlighted)
        }
    }

    private func updateColors() {
        for option in options {
            let isOn = option.mode == highlighted
            option.view.backgroundColor = isOn ? theme.accent : .clear
            option.view.textColor = isOn ? .white : theme.text
        }
    }

    @objc private func optionTapped(_ gesture: UITapGestureRecognizer) {
        if let mode = options.first(where: { $0.view === gesture.view })?.mode {
            onSelect?(mode)
        }
    }

    @objc private func backgroundTapped(_ gesture: UITapGestureRecognizer) {
        if !panel.frame.contains(gesture.location(in: self)) {
            onDismiss?()
        }
    }
}

/// The row of accented letters shown while a letter key is held.
private final class AccentPickerView: UIView {
    private let options: [String]
    private var labels: [UILabel] = []
    private let theme: KeyboardTheme
    private(set) var selected: String?

    init(options: [String], theme: KeyboardTheme) {
        self.options = options
        self.theme = theme
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = theme.panel
        layer.cornerRadius = 8
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.35
        layer.shadowRadius = 3
        for option in options {
            let label = UILabel()
            label.text = option
            label.textAlignment = .center
            label.font = .systemFont(ofSize: 24)
            label.layer.cornerRadius = 6
            label.clipsToBounds = true
            addSubview(label)
            labels.append(label)
        }
        highlight(index: 0)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func place(above key: CGRect, in bounds: CGRect) {
        let cell = max(key.width, 34)
        let width = cell * CGFloat(options.count) + 8
        let x = min(max(key.minX - 4, bounds.minX + 2), bounds.maxX - width - 2)
        frame = CGRect(x: x, y: max(key.minY - 52, bounds.minY), width: width, height: 48)
        for (index, label) in labels.enumerated() {
            label.frame = CGRect(x: 4 + CGFloat(index) * cell, y: 4, width: cell, height: 40)
        }
    }

    func highlight(atX x: CGFloat) {
        guard let first = labels.first else { return }
        highlight(index: Int((x - first.frame.minX) / first.frame.width))
    }

    private func highlight(index: Int) {
        let index = min(max(index, 0), options.count - 1)
        selected = options[index]
        for (position, label) in labels.enumerated() {
            label.backgroundColor = position == index ? theme.accent : .clear
            label.textColor = position == index ? .white : theme.text
        }
    }
}
