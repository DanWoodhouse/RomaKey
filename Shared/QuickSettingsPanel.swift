import KeyboardCore
import UIKit

/// The keyboard's own settings, shown in place of the keys from the toolbar's ⚙︎, laid out like
/// Control Centre: rounded modules of round toggles, so the common switches are one tap away
/// without leaving the app you're typing in. Everything else is in the RomaKey app, one tap
/// away on the Open RomaKey button.
final class QuickSettingsPanel: UIView {
    var onChange: ((KeyboardSettings) -> Void)?
    var onClose: (() -> Void)?
    var onOpenApp: (() -> Void)?

    private var settings: KeyboardSettings
    private let theme: KeyboardTheme
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let bar = UIStackView()
    private static let barHeight: CGFloat = 38
    private static let spacing: CGFloat = 8

    private struct Toggle {
        let title: String
        let symbol: String
        let keyPath: WritableKeyPath<KeyboardSettings, Bool>
    }

    /// The big module, top left, like Control Centre's connectivity block.
    private static let essentials: [Toggle] = [
        Toggle(title: "Autocorrect", symbol: "textformat.abc.dottedunderline", keyPath: \.autocorrect),
        Toggle(title: "Capitals", symbol: "shift", keyPath: \.autoCapitalization),
        Toggle(title: "Predictive", symbol: "text.bubble", keyPath: \.predictiveText),
        Toggle(title: "Suggestions", symbol: "text.badge.checkmark", keyPath: \.wordSuggestions),
    ]

    private static let more: [Toggle] = [
        Toggle(title: "Swipe up", symbol: "arrow.up.square", keyPath: \.swipeUpSecondaries),
        Toggle(title: "Key extras", symbol: "number.square", keyPath: \.keySecondaries),
        Toggle(title: "Emoji", symbol: "face.smiling", keyPath: \.emojiSuggestions),
        Toggle(title: "Double space", symbol: "space", keyPath: \.doubleSpacePeriod),
        Toggle(title: "Popups", symbol: "bubble.middle.bottom", keyPath: \.keyPopups),
        Toggle(title: "Meanings", symbol: "book", keyPath: \.showMeanings),
        Toggle(title: "Romaji", symbol: "character", keyPath: \.showRomaji),
        Toggle(title: "Space cursor", symbol: "arrow.left.and.right", keyPath: \.spaceBarCursor),
        Toggle(title: "Left hand", symbol: "hand.raised", keyPath: \.leftHandedWheel),
        Toggle(title: "Flick only", symbol: "hand.draw", keyPath: \.flickOnly),
        Toggle(title: "Sounds", symbol: "speaker.wave.2", keyPath: \.keySounds),
        Toggle(title: "Haptics", symbol: "iphone.radiowaves.left.and.right", keyPath: \.haptics),
        Toggle(title: "Animations", symbol: "wand.and.rays", keyPath: \.animations),
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
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 10),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -10),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 6),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -8),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -20),
        ])

        // Top: essentials on the left; AI and height stacked on the right.
        let right = UIStackView(arrangedSubviews: [
            pickerModule(title: "✨ AI", items: ["Apple", "Claude"],
                         selected: KeyboardSettings.AIProvider.allCases.firstIndex(of: settings.aiProvider) ?? 0) { [weak self] index in
                self?.change { $0.aiProvider = KeyboardSettings.AIProvider.allCases[index] }
            },
            pickerModule(title: "Height", items: ["Low", "Mid", "Tall"],
                         selected: KeyboardSettings.Height.allCases.firstIndex(of: settings.height) ?? 1) { [weak self] index in
                self?.change { $0.height = KeyboardSettings.Height.allCases[index] }
            },
        ])
        right.axis = .vertical
        right.spacing = Self.spacing
        right.distribution = .fillEqually
        let top = UIStackView(arrangedSubviews: [module(grid(Self.essentials, columns: 2)), right])
        top.spacing = Self.spacing
        top.distribution = .fillEqually
        content.addArrangedSubview(top)

        content.addArrangedSubview(pickerModule(title: "Text size", items: ["A", "A", "A"],
                                                selected: KeyboardSettings.TextSize.allCases.firstIndex(of: settings.textSize) ?? 1,
                                                growingFonts: true) { [weak self] index in
            self?.change { $0.textSize = KeyboardSettings.TextSize.allCases[index] }
        })
        content.addArrangedSubview(module(grid(Self.more, columns: 4)))
        content.addArrangedSubview(openAppButton())

        let note = UILabel()
        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 11)
        note.textColor = theme.secondaryText
        note.textAlignment = .center
        note.text = sharesWithApp
            ? "Looks, fonts, each key's extras, AI keys and GIFs are in the app."
            : "Saved on this keyboard only. Turn on Allow Full Access to share settings with the RomaKey app."
        content.addArrangedSubview(note)

        bar.axis = .horizontal
        bar.alignment = .center
        var done = UIButton.Configuration.plain()
        done.baseForegroundColor = theme.text
        var title = AttributedString("ABC")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        done.attributedTitle = title
        bar.addArrangedSubview(UIButton(configuration: done, primaryAction: UIAction { [weak self] _ in self?.onClose?() }))
        let heading = UILabel()
        heading.text = "設定 · Settings"
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = theme.secondaryText
        heading.textAlignment = .center
        bar.addArrangedSubview(heading)
        addSubview(bar)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scrollView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.barHeight)
        bar.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 8, height: Self.barHeight)
    }

    private func change(_ edit: (inout KeyboardSettings) -> Void) {
        edit(&settings)
        onChange?(settings)
    }

    // MARK: - Modules

    /// A rounded card, like a Control Centre module.
    private func module(_ inside: UIView) -> UIView {
        let card = UIView()
        card.backgroundColor = theme.key
        card.layer.cornerRadius = 18
        card.layer.cornerCurve = .continuous
        inside.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inside)
        NSLayoutConstraint.activate([
            inside.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
            inside.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
            inside.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
            inside.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -8),
        ])
        return card
    }

    private func grid(_ toggles: [Toggle], columns: Int) -> UIView {
        let rows = UIStackView()
        rows.axis = .vertical
        rows.spacing = 6
        for start in stride(from: 0, to: toggles.count, by: columns) {
            let row = UIStackView()
            row.distribution = .fillEqually
            for index in start..<start + columns {
                if index < toggles.count {
                    row.addArrangedSubview(tile(toggles[index]))
                } else {
                    row.addArrangedSubview(UIView())
                }
            }
            rows.addArrangedSubview(row)
        }
        return rows
    }

    private func tile(_ toggle: Toggle) -> UIView {
        let tile = ToggleTile(title: toggle.title, symbol: toggle.symbol, theme: theme,
                              isOn: settings[keyPath: toggle.keyPath])
        tile.addAction(UIAction { [weak self, weak tile] _ in
            guard let tile else { return }
            self?.change { $0[keyPath: toggle.keyPath] = tile.isOn }
        }, for: .valueChanged)
        return tile
    }

    /// A titled module with a segmented choice.
    private func pickerModule(title: String, items: [String], selected: Int, growingFonts: Bool = false,
                              onSelect: @escaping (Int) -> Void) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = theme.secondaryText
        let picker = UISegmentedControl(items: items)
        picker.selectedSegmentIndex = selected
        picker.selectedSegmentTintColor = theme.accent
        picker.setTitleTextAttributes([.foregroundColor: theme.text], for: .normal)
        picker.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .selected)
        if growingFonts {
            // A A A, small to large, like the Text Size control.
            for (index, size) in [11, 14, 17].enumerated() {
                let text = NSAttributedString(string: "A", attributes: [.font: UIFont.systemFont(ofSize: CGFloat(size), weight: .semibold)])
                picker.setImage(text.templateImage, forSegmentAt: index)
                picker.setTitle(nil, forSegmentAt: index)
            }
            picker.accessibilityLabel = "Text size"
        }
        picker.addAction(UIAction { [weak picker] _ in
            guard let picker else { return }
            onSelect(picker.selectedSegmentIndex)
        }, for: .valueChanged)
        let stack = UIStackView(arrangedSubviews: [label, picker])
        stack.axis = .vertical
        stack.spacing = 6
        return module(stack)
    }

    private func openAppButton() -> UIView {
        var configuration = UIButton.Configuration.filled()
        configuration.baseBackgroundColor = theme.accent
        configuration.baseForegroundColor = .white
        configuration.cornerStyle = .large
        configuration.image = UIImage(systemName: "arrow.up.forward.app")
        configuration.imagePadding = 8
        var title = AttributedString("Open RomaKey · アプリを開く")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        configuration.attributedTitle = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12)
        return UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in self?.onOpenApp?() })
    }
}

/// A round Control Centre toggle with its name underneath: the accent colour when on.
private final class ToggleTile: UIControl {
    private let circle = UIView()
    private let icon = UIImageView()
    private let label = UILabel()
    private let theme: KeyboardTheme
    private(set) var isOn: Bool
    private static let size: CGFloat = 40

    init(title: String, symbol: String, theme: KeyboardTheme, isOn: Bool) {
        self.theme = theme
        self.isOn = isOn
        super.init(frame: .zero)
        circle.isUserInteractionEnabled = false
        circle.layer.cornerRadius = Self.size / 2
        icon.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 16, weight: .medium))
        icon.contentMode = .center
        label.text = title
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = theme.text
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.8
        for view in [circle, icon, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.isUserInteractionEnabled = false
        }
        addSubview(circle)
        circle.addSubview(icon)
        addSubview(label)
        NSLayoutConstraint.activate([
            circle.widthAnchor.constraint(equalToConstant: Self.size),
            circle.heightAnchor.constraint(equalToConstant: Self.size),
            circle.centerXAnchor.constraint(equalTo: centerXAnchor),
            circle.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            icon.centerXAnchor.constraint(equalTo: circle.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: circle.centerYAnchor),
            label.topAnchor.constraint(equalTo: circle.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .button
        addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isHighlighted: Bool {
        didSet { circle.alpha = isHighlighted ? 0.7 : 1 }
    }

    private func toggle() {
        isOn.toggle()
        updateColors()
        if theme.animates {
            let pop = CASpringAnimation(keyPath: "transform.scale")
            pop.fromValue = 0.9
            pop.toValue = 1
            pop.damping = 14
            pop.stiffness = 380
            pop.duration = pop.settlingDuration
            circle.layer.add(pop, forKey: "pop")
        }
        sendActions(for: .valueChanged)
    }

    private func updateColors() {
        circle.backgroundColor = isOn ? theme.accent : theme.specialKey
        icon.tintColor = isOn ? .white : theme.text
        accessibilityValue = isOn ? "On" : "Off"
    }
}

private extension NSAttributedString {
    /// The text drawn as a template image, for segmented controls that need mixed font sizes.
    var templateImage: UIImage {
        UIGraphicsImageRenderer(size: size()).image { _ in draw(at: .zero) }.withRenderingMode(.alwaysTemplate)
    }
}
