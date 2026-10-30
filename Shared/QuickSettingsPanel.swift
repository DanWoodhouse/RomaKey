import KeyboardCore
import UIKit

/// The keyboard's own settings, shown in place of the keys from the toolbar's ⚙︎, laid out like
/// iOS 26's Control Centre: modules of Liquid Glass holding round toggles, sliders for text size
/// and height, and a Focus-style tile for the ✨ AI provider. Everything else is in the RomaKey
/// app, one tap away on the RomaKey button in the bottom bar.
final class QuickSettingsPanel: UIView {
    var onChange: ((KeyboardSettings) -> Void)?
    var onClose: (() -> Void)?
    var onOpenApp: (() -> Void)?

    private var settings: KeyboardSettings
    private let theme: KeyboardTheme
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let bar = UIStackView()
    private var hasAppeared = false
    private static let barHeight: CGFloat = 38
    private static let spacing: CGFloat = 10

    private struct Toggle {
        let title: String
        let symbol: String
        let keyPath: WritableKeyPath<KeyboardSettings, Bool>
    }

    private static let typing: [Toggle] = [
        Toggle(title: "Autocorrect", symbol: "textformat.abc.dottedunderline", keyPath: \.autocorrect),
        Toggle(title: "Capitals", symbol: "shift", keyPath: \.autoCapitalization),
        Toggle(title: "Predictive", symbol: "text.bubble", keyPath: \.predictiveText),
        Toggle(title: "Suggestions", symbol: "rectangle.split.3x1", keyPath: \.wordSuggestions),
    ]

    private static let keys: [Toggle] = [
        Toggle(title: "Swipe up", symbol: "arrow.up.square", keyPath: \.swipeUpSecondaries),
        Toggle(title: "Key extras", symbol: "number.square", keyPath: \.keySecondaries),
        Toggle(title: "Popups", symbol: "bubble.middle.bottom", keyPath: \.keyPopups),
        Toggle(title: "Space .", symbol: "space", keyPath: \.doubleSpacePeriod),
        Toggle(title: "Trackpad", symbol: "arrow.left.and.right", keyPath: \.spaceBarCursor),
        Toggle(title: "Left hand", symbol: "hand.raised", keyPath: \.leftHandedWheel),
        Toggle(title: "Flick only", symbol: "hand.draw", keyPath: \.flickOnly),
        Toggle(title: "Auto kanji", symbol: "character.textbox", keyPath: \.liveConversion),
    ]

    private static let show: [Toggle] = [
        Toggle(title: "Emoji", symbol: "face.smiling", keyPath: \.emojiSuggestions),
        Toggle(title: "Meanings", symbol: "book", keyPath: \.showMeanings),
        Toggle(title: "Romaji", symbol: "character", keyPath: \.showRomaji),
    ]

    private static let feel: [Toggle] = [
        Toggle(title: "Sounds", symbol: "speaker.wave.2", keyPath: \.keySounds),
        Toggle(title: "Haptics", symbol: "iphone.radiowaves.left.and.right", keyPath: \.haptics),
        Toggle(title: "Motion", symbol: "wand.and.rays", keyPath: \.animations),
    ]

    /// `sharesWithApp` is false without Full Access: changes then stay on this keyboard.
    init(settings: KeyboardSettings, theme: KeyboardTheme, sharesWithApp: Bool) {
        self.settings = settings
        self.theme = theme
        super.init(frame: .zero)

        content.axis = .vertical
        content.spacing = Self.spacing
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -20),
        ])

        content.addArrangedSubview(GlassCard(theme: theme, title: nil, content: grid(Self.typing, columns: 4, size: 46)))
        content.addArrangedSubview(pair(
            slider(title: "Text size", names: ["Small", "Standard", "Large"],
                   stop: KeyboardSettings.TextSize.allCases.firstIndex(of: settings.textSize) ?? 1,
                   low: "textformat.size.smaller", high: "textformat.size.larger") { [weak self] stop in
                self?.change { $0.textSize = KeyboardSettings.TextSize.allCases[stop] }
            },
            slider(title: "Height", names: ["Compact", "Standard", "Tall"],
                   stop: KeyboardSettings.Height.allCases.firstIndex(of: settings.height) ?? 1,
                   low: "rectangle.compress.vertical", high: "rectangle.expand.vertical") { [weak self] stop in
                self?.change { $0.height = KeyboardSettings.Height.allCases[stop] }
            }
        ))
        let ai = AITile(theme: theme, provider: settings.aiProvider)
        ai.addAction(UIAction { [weak self, weak ai] _ in
            guard let ai else { return }
            self?.change { $0.aiProvider = ai.provider }
        }, for: .valueChanged)
        content.addArrangedSubview(ai)
        content.addArrangedSubview(GlassCard(theme: theme, title: "Keys", content: grid(Self.keys, columns: 4, size: 46)))
        content.addArrangedSubview(pair(
            GlassCard(theme: theme, title: "Show", content: grid(Self.show, columns: 3, size: 40)),
            GlassCard(theme: theme, title: "Feel", content: grid(Self.feel, columns: 3, size: 40))
        ))
        if !sharesWithApp {
            let note = UILabel()
            note.numberOfLines = 0
            note.font = .systemFont(ofSize: 11)
            note.textColor = theme.secondaryText
            note.textAlignment = .center
            note.text = "Saved on this keyboard only. Turn on Allow Full Access to share settings with the RomaKey app."
            content.addArrangedSubview(note)
        }

        bar.axis = .horizontal
        bar.alignment = .center
        bar.spacing = 4
        var done = UIButton.Configuration.plain()
        done.baseForegroundColor = theme.text
        var title = AttributedString("ABC")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        done.attributedTitle = title
        let abc = UIButton(configuration: done, primaryAction: UIAction { [weak self] _ in self?.onClose?() })
        abc.widthAnchor.constraint(equalToConstant: 64).isActive = true
        bar.addArrangedSubview(abc)
        let heading = UILabel()
        heading.text = "設定 · Settings"
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = theme.secondaryText
        heading.textAlignment = .center
        heading.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(heading)
        bar.addArrangedSubview(openAppButton())
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.barHeight)
        bar.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 12, height: Self.barHeight)
    }

    /// The modules settle up into place one after another, the first time the panel shows.
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !hasAppeared else { return }
        hasAppeared = true
        guard theme.animates else { return }
        for (index, module) in content.arrangedSubviews.enumerated() {
            let rise = CASpringAnimation(keyPath: "transform.translation.y")
            rise.fromValue = 10
            rise.toValue = 0
            rise.damping = 22
            rise.stiffness = 260
            rise.duration = rise.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.22
            for animation in [rise, fade] as [CAAnimation] {
                animation.beginTime = CACurrentMediaTime() + Double(index) * 0.03
                animation.fillMode = .backwards
                module.layer.add(animation, forKey: animation === rise ? "rise" : "fade")
            }
        }
    }

    private func change(_ edit: (inout KeyboardSettings) -> Void) {
        edit(&settings)
        onChange?(settings)
    }

    // MARK: - Modules

    private func pair(_ left: UIView, _ right: UIView) -> UIView {
        let row = UIStackView(arrangedSubviews: [left, right])
        row.spacing = Self.spacing
        row.distribution = .fillEqually
        return row
    }

    private func grid(_ toggles: [Toggle], columns: Int, size: CGFloat) -> UIView {
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 8
        for start in stride(from: 0, to: toggles.count, by: columns) {
            let row = UIStackView()
            row.distribution = .fillEqually
            for index in start..<start + columns {
                if index < toggles.count {
                    row.addArrangedSubview(tile(toggles[index], size: size))
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            rows.addArrangedSubview(row)
        }
        return rows
    }

    private func tile(_ toggle: Toggle, size: CGFloat) -> UIView {
        let tile = ToggleTile(title: toggle.title, symbol: toggle.symbol, theme: theme, size: size,
                              isOn: settings[keyPath: toggle.keyPath])
        tile.addAction(UIAction { [weak self, weak tile] _ in
            guard let tile else { return }
            self?.change { $0[keyPath: toggle.keyPath] = tile.isOn }
        }, for: .valueChanged)
        return tile
    }

    /// A glass module with a three-stop slider, like Control Centre's brightness, and the
    /// current value named in its corner.
    private func slider(title: String, names: [String], stop: Int, low: String, high: String,
                        onStop: @escaping (Int) -> Void) -> UIView {
        let heading = UILabel()
        heading.text = title
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = theme.text.withAlphaComponent(0.62)
        let value = UILabel()
        value.text = names[stop]
        value.font = .systemFont(ofSize: 11, weight: .semibold)
        value.textColor = theme.text.withAlphaComponent(0.85)
        value.textAlignment = .right
        let header = UIStackView(arrangedSubviews: [heading, value])

        let slider = StopSlider(stops: names.count, stop: stop)
        slider.minimumTrackTintColor = theme.accent
        slider.maximumTrackTintColor = theme.text.withAlphaComponent(0.14)
        let symbol = UIImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        slider.minimumValueImage = UIImage(systemName: low, withConfiguration: symbol)?
            .withTintColor(theme.secondaryText, renderingMode: .alwaysOriginal)
        slider.maximumValueImage = UIImage(systemName: high, withConfiguration: symbol)?
            .withTintColor(theme.secondaryText, renderingMode: .alwaysOriginal)
        slider.accessibilityLabel = title
        slider.onStop = { stop in
            value.text = names[stop]
            onStop(stop)
        }
        slider.accessibilityValueFor = { names[$0] }

        let stack = UIStackView(arrangedSubviews: [header, slider])
        stack.axis = .vertical
        stack.spacing = 4
        return GlassCard(theme: theme, title: nil, content: stack)
    }

    private func openAppButton() -> UIButton {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
            configuration.cornerStyle = .capsule
        }
        configuration.baseForegroundColor = theme.text
        configuration.image = UIImage(systemName: "arrow.up.right",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 5
        var title = AttributedString("RomaKey")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        configuration.attributedTitle = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.onOpenApp?() })
        button.accessibilityLabel = "Open RomaKey settings"
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }
}

// MARK: - Glass

/// Liquid Glass on iOS 26, and the thinnest blur material before it.
private enum Glass {
    static func effect(tint: UIColor? = nil) -> UIVisualEffect {
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.tintColor = tint
            return glass
        }
        return UIBlurEffect(style: .systemUltraThinMaterial)
    }

    /// Before iOS 26 the blur has no tint of its own, so a coloured layer stands in for it.
    static var tintsItself: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }

    static func view(cornerRadius: CGFloat, tint: UIColor? = nil) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect(tint: tint))
        view.layer.cornerRadius = cornerRadius
        view.layer.cornerCurve = .continuous
        view.clipsToBounds = true
        view.isUserInteractionEnabled = false
        return view
    }
}

/// A Control Centre module: a rounded pane of glass, with an optional small title above its content.
private final class GlassCard: UIView {
    private let glass = Glass.view(cornerRadius: 24)
    private let rim = CAShapeLayer()

    init(theme: KeyboardTheme, title: String?, content: UIView) {
        super.init(frame: .zero)
        addSubview(glass)
        if !Glass.tintsItself {
            // A bright edge and a soft shadow, as Liquid Glass draws on iOS 26.
            glass.contentView.backgroundColor = theme.panel.withAlphaComponent(0.28)
            rim.fillColor = nil
            rim.strokeColor = UIColor.white.withAlphaComponent(0.3).cgColor
            rim.lineWidth = 0.5
            layer.addSublayer(rim)
            layer.shadowColor = UIColor.black.cgColor
            layer.shadowOpacity = 0.14
            layer.shadowRadius = 12
            layer.shadowOffset = CGSize(width: 0, height: 6)
        }
        let stack = UIStackView(arrangedSubviews: [content])
        stack.axis = .vertical
        stack.spacing = 8
        if let title {
            let label = UILabel()
            label.text = title
            label.font = .systemFont(ofSize: 11, weight: .semibold)
            label.textColor = theme.text.withAlphaComponent(0.62)
            let inset = UIView()
            label.translatesAutoresizingMaskIntoConstraints = false
            inset.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: inset.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: inset.trailingAnchor),
                label.topAnchor.constraint(equalTo: inset.topAnchor),
                label.bottomAnchor.constraint(equalTo: inset.bottomAnchor),
            ])
            stack.insertArrangedSubview(inset, at: 0)
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -9),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        let path = UIBezierPath(roundedRect: bounds, cornerRadius: 24).cgPath
        rim.path = path
        layer.shadowPath = path
    }
}

/// A round toggle with its name underneath. On, the glass takes the accent colour.
private final class ToggleTile: UIControl {
    private let circle: UIVisualEffectView
    private let tintLayer = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let theme: KeyboardTheme
    private(set) var isOn: Bool

    init(title: String, symbol: String, theme: KeyboardTheme, size: CGFloat, isOn: Bool) {
        self.theme = theme
        self.isOn = isOn
        circle = Glass.view(cornerRadius: size / 2)
        super.init(frame: .zero)
        tintLayer.isUserInteractionEnabled = false
        tintLayer.layer.cornerRadius = size / 2
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size > 42 ? 17 : 15, weight: .medium))
        icon.contentMode = .center
        label.text = title
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = theme.text.withAlphaComponent(0.78)
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        circle.contentView.addSubview(tintLayer)
        circle.contentView.addSubview(icon)
        for view in [circle, tintLayer, icon, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
        }
        addSubview(circle)
        addSubview(label)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: size),
            circle.heightAnchor.constraint(equalToConstant: size),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.topAnchor.constraint(equalTo: topAnchor),
            tintLayer.leadingAnchor.constraint(equalTo: circle.contentView.leadingAnchor),
            tintLayer.trailingAnchor.constraint(equalTo: circle.contentView.trailingAnchor),
            tintLayer.topAnchor.constraint(equalTo: circle.contentView.topAnchor),
            tintLayer.bottomAnchor.constraint(equalTo: circle.contentView.bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            label.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 5),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        updateLook(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// The glass gives a little under the finger and springs back, like Control Centre.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue, theme.animates else { return }
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.circle.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.9, y: 0.9) : .identity
            }
        }
    }

    private func toggle() {
        isOn.toggle()
        updateLook(animated: theme.animates)
        sendActions(for: .valueChanged)
    }

    private func updateLook(animated: Bool) {
        let changes = {
            if Glass.tintsItself {
                self.circle.effect = Glass.effect(tint: self.isOn ? self.theme.accent : nil)
                self.tintLayer.backgroundColor = .clear
            } else {
                self.tintLayer.backgroundColor = self.isOn ? self.theme.accent : self.theme.text.withAlphaComponent(0.08)
            }
            self.icon.tintColor = self.isOn ? .white : self.theme.text
        }
        if animated {
            UIView.animate(withDuration: 0.25, animations: changes)
        } else {
            changes()
        }
        accessibilityValue = isOn ? "On" : "Off"
    }
}

/// A slider that settles on whole stops (0, 1, 2), reporting each new stop as it's reached.
private final class StopSlider: UISlider {
    var onStop: ((Int) -> Void)?
    var accessibilityValueFor: ((Int) -> String)?
    private var stop: Int

    init(stops: Int, stop: Int) {
        self.stop = stop
        super.init(frame: .zero)
        minimumValue = 0
        maximumValue = Float(stops - 1)
        value = Float(stop)
        addAction(UIAction { [weak self] _ in self?.moved() }, for: .valueChanged)
        addAction(UIAction { [weak self] _ in self?.settle() }, for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var accessibilityValue: String? {
        get { accessibilityValueFor?(stop) }
        set {}
    }

    private func moved() {
        let nearest = Int(value.rounded())
        guard nearest != stop else { return }
        stop = nearest
        UISelectionFeedbackGenerator().selectionChanged()
        onStop?(stop)
    }

    private func settle() {
        setValue(Float(stop), animated: true)
    }

    // VoiceOver swipes move a whole stop.
    override func accessibilityIncrement() {
        value = min(Float(stop + 1), maximumValue)
        moved()
    }

    override func accessibilityDecrement() {
        value = max(Float(stop - 1), minimumValue)
        moved()
    }
}

/// The ✨ AI provider, shaped like Control Centre's Focus button: tap to switch between Apple
/// Intelligence and Claude.
private final class AITile: UIControl {
    private(set) var provider: KeyboardSettings.AIProvider
    private let glass = Glass.view(cornerRadius: 28)
    private let badge = UIView()
    private let gradient = CAGradientLayer()
    private let icon = UIImageView()
    private let caption = UILabel()
    private let name = UILabel()
    private let swap = UILabel()
    private let theme: KeyboardTheme

    init(theme: KeyboardTheme, provider: KeyboardSettings.AIProvider) {
        self.theme = theme
        self.provider = provider
        super.init(frame: .zero)
        addSubview(glass)
        if !Glass.tintsItself {
            glass.contentView.backgroundColor = theme.panel.withAlphaComponent(0.28)
        }
        gradient.colors = [UIColor(hex: 0xC9A7FF).cgColor, UIColor(hex: 0x8B5CF6).cgColor, UIColor(hex: 0x6D3FD8).cgColor]
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        badge.layer.addSublayer(gradient)
        badge.layer.cornerRadius = 20
        badge.clipsToBounds = true
        icon.image = UIImage(systemName: "sparkle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .semibold))
        icon.tintColor = .white
        icon.contentMode = .center
        badge.addSubview(icon)
        caption.text = "✨ AI answers with"
        caption.font = .systemFont(ofSize: 11, weight: .semibold)
        caption.textColor = theme.secondaryText
        name.font = .systemFont(ofSize: 15, weight: .semibold)
        name.textColor = theme.text
        swap.font = .systemFont(ofSize: 11, weight: .semibold)
        swap.textColor = theme.secondaryText
        swap.textAlignment = .center
        swap.backgroundColor = theme.text.withAlphaComponent(0.08)
        swap.layer.cornerRadius = 11
        swap.clipsToBounds = true
        for view in [glass, badge, caption, name, swap] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        addAction(UIAction { [weak self] _ in self?.switchProvider() }, for: .touchUpInside)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 56)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        glass.frame = bounds
        glass.layer.cornerRadius = bounds.height / 2
        badge.frame = CGRect(x: 8, y: (bounds.height - 40) / 2, width: 40, height: 40)
        gradient.frame = badge.bounds
        icon.frame = badge.bounds
        let swapWidth = swap.intrinsicContentSize.width + 20
        swap.frame = CGRect(x: bounds.width - swapWidth - 12, y: (bounds.height - 24) / 2, width: swapWidth, height: 24)
        let textX = badge.frame.maxX + 10
        let textWidth = swap.frame.minX - textX - 8
        caption.frame = CGRect(x: textX, y: bounds.midY - 17, width: textWidth, height: 14)
        name.frame = CGRect(x: textX, y: bounds.midY - 2, width: textWidth, height: 20)
    }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue, theme.animates else { return }
            UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.65, initialSpringVelocity: 0,
                           options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.97, y: 0.97) : .identity
            }
        }
    }

    private func switchProvider() {
        provider = provider == .apple ? .claude : .apple
        if theme.animates {
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            name.layer.add(fade, forKey: "name")
            swap.layer.add(fade, forKey: "swap")
        }
        refresh()
        sendActions(for: .valueChanged)
    }

    private func refresh() {
        let apple = provider == .apple
        name.text = apple ? "Apple Intelligence" : "Claude"
        swap.text = apple ? "Use Claude" : "Use Apple"
        accessibilityLabel = "AI answers with \(apple ? "Apple Intelligence" : "Claude")"
        accessibilityHint = "Switches to \(apple ? "Claude" : "Apple Intelligence")"
        setNeedsLayout()
    }
}
