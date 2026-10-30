import KeyboardCore
import UIKit

/// The romaji QWERTY keyboard. Switching between あ, EN and 辞 only relabels keys; the candidate
/// bar is there in every mode, so the keyboard's height doesn't change either. The mode key
/// opens the mode wheel, which replaces 🌐.
final class RomajiKeyboardView: KeyboardViewBase {
    private let engine: KeyboardEngine
    private var buttons: [[RomajiKeyButton]] = []
    private var builtLayout: KeyboardLayout?
    private let popup = KeyPopupView()
    private let deleteRepeater = KeyRepeater()
    private var spaceBarCursor: SpaceBarCursor?
    private var modeWheel: ModeWheelTracker?
    private var accentPicker: AccentPickerView?
    /// What the open picker's labels type, where they differ (、 types "," for the composer).
    private var pickerTyped: [String: String] = [:]
    /// Where the current touch on a letter or ー/- began, and whether it has swiped up far
    /// enough to type the key's secondary character.
    private var swipeStart: CGPoint?
    private var swipeArmed = false
    private static let swipeThreshold: CGFloat = 22
    /// The mode the keys were last labelled for, to animate a change.
    private var shownMode: InputMode?
    /// The host app's text field; typing goes back here when a search ends.
    private let documentOutput: TextOutput?

    init(engine: KeyboardEngine, feedback: KeyFeedback) {
        self.engine = engine
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
        // Searches stay in kana (ねこ finds 🐈).
        engine.convertsAutomatically = output == nil
    }

    override func commitTyping() {
        engine.commitComposition()
    }

    override var searchLanguage: String {
        engine.mode == .english ? "en" : "ja"
    }

    /// Rebuilds the keys if the page changed, otherwise just relabels them.
    override func reload() {
        if engine.layout != builtLayout {
            rebuildKeys()
        }
        let modeChanged = shownMode != nil && shownMode != engine.mode
        shownMode = engine.mode
        for button in buttons.joined() {
            button.setLabel(engine.label(for: button.kind), animated: modeChanged && animates)
            button.hint = secondary(for: button)?.label
        }
        if modeChanged {
            pulseKeys()
        }
        showCandidates(
            engine.candidates,
            showsMeanings: settings.showMeanings || engine.mode == .dictionary,
            placeholder: placeholder,
            notice: engine.loadingMessage
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
                button.isPrimaryAction = key.kind == .returnKey
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
        case .languageToggle:
            modeWheel = ModeWheelTracker(
                button: button,
                host: self,
                current: { [weak self] in ModeWheelSlot(self?.engine.mode ?? .japanese) },
                onTap: { [weak self] in self?.engine.press(.languageToggle) }
            )
        case .delete:
            button.addTarget(self, action: #selector(deleteDown), for: .touchDown)
            button.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        case .character, .longVowel:
            // Tap types the key; swipe up types its secondary (1, @, 、…).
            button.addTarget(self, action: #selector(letterDown(_:forEvent:)), for: .touchDown)
            button.addTarget(self, action: #selector(letterMoved(_:forEvent:)), for: [.touchDragInside, .touchDragOutside])
            button.addTarget(self, action: #selector(letterUpInside(_:)), for: .touchUpInside)
            button.addTarget(self, action: #selector(letterUpOutside(_:)), for: .touchUpOutside)
            button.addTarget(self, action: #selector(keyReleased), for: .touchCancel)
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
        switch button.kind {
        case .character, .longVowel:
            let press = UILongPressGestureRecognizer(target: self, action: #selector(characterKeyLongPressed(_:)))
            press.minimumPressDuration = 0.35
            button.addGestureRecognizer(press)
        default:
            break
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
                // The keycap is placed inside the button, so in the button's own coordinates.
                button.keycapFrame = keyFrame.offsetBy(dx: -touchFrame.minX, dy: -touchFrame.minY)
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
        swipeStart = nil
        swipeArmed = false
    }

    // MARK: - Swipe up for secondaries

    /// A key's secondary character, if it has one turned on: the label (shown as a hint and in
    /// the popup) and what it types.
    private func secondary(for button: RomajiKeyButton) -> (label: String, typed: String)? {
        guard settings.keySecondaries else { return nil }
        switch button.kind {
        case .character(let letter):
            guard engine.page == .letters, settings.secondaryIsOn(for: letter),
                  let secondary = KeyboardLayout.secondary(for: letter) else { return nil }
            return (secondary, secondary)
        case .longVowel:
            guard settings.secondaryIsOn(for: KeyboardLayout.longVowelKeyName) else { return nil }
            return KeyboardLayout.punctuation(japanese: engine.mode == .japanese).first
        default:
            return nil
        }
    }

    @objc private func letterDown(_ sender: RomajiKeyButton, forEvent event: UIEvent) {
        swipeStart = event.touches(for: sender)?.first?.location(in: self)
        swipeArmed = false
        keyDown(sender)
    }

    @objc private func letterMoved(_ sender: RomajiKeyButton, forEvent event: UIEvent) {
        guard settings.swipeUpSecondaries, let start = swipeStart, let secondary = secondary(for: sender),
              let point = event.touches(for: sender)?.first?.location(in: self) else { return }
        let armed = start.y - point.y > Self.swipeThreshold
        guard armed != swipeArmed else { return }
        swipeArmed = armed
        if armed {
            feedback.keyDown()
            popup.show(secondary.label, above: sender.keycapFrame(in: self), in: bounds, theme: theme)
        } else {
            popup.hide()
        }
    }

    @objc private func letterUpInside(_ sender: RomajiKeyButton) {
        if swipeArmed, let secondary = secondary(for: sender) {
            typeSecondary(secondary.typed)
        } else {
            keyUp(sender)
        }
        keyReleased()
    }

    @objc private func letterUpOutside(_ sender: RomajiKeyButton) {
        // A swipe up usually ends above the key.
        if swipeArmed, let secondary = secondary(for: sender) {
            typeSecondary(secondary.typed)
        }
        keyReleased()
    }

    private func typeSecondary(_ text: String) {
        popup.hide()
        hideEntry()
        engine.press(.character(text))
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

    // MARK: - Held letters

    /// Hold a letter for its secondary (q → 1, a → @) and, in English and 辞書, accents (é, ü,
    /// ñ…); hold ー/- for punctuation (、。！？〜). Slide to one and let go. Japanese romaji has no
    /// accents.
    @objc private func characterKeyLongPressed(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            popup.hide()
            guard let key = gesture.view as? RomajiKeyButton else { return }
            var options: [String] = []
            pickerTyped = [:]
            if key.kind == .longVowel {
                if secondary(for: key) != nil {
                    for option in KeyboardLayout.punctuation(japanese: engine.mode == .japanese) {
                        options.append(option.label)
                        pickerTyped[option.label] = option.typed
                    }
                }
            } else if engine.page == .letters, case .text(let letter) = key.label {
                if let secondary = secondary(for: key) {
                    options.append(secondary.label)
                }
                if engine.mode != .japanese {
                    options += Accents.alternatives(for: letter)
                }
            }
            guard !options.isEmpty else {
                // Nothing to pick: behave like a normal (slow) tap.
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
                engine.press(.character(pickerTyped[choice] ?? choice.lowercased()))
            }
            fallthrough
        default:
            accentPicker?.removeFromSuperview()
            accentPicker = nil
        }
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
            label.font = theme.font(24)
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
