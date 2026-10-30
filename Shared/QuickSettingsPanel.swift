import KeyboardCore
import UIKit

/// The typing settings, shown in place of the keys from the toolbar's ⚙︎, so autocorrect,
/// auto-capitals and the rest can be switched without leaving the app you're typing in.
/// Looks, photo and GIF settings stay in the RomaKey app.
final class QuickSettingsPanel: UIView {
    var onChange: ((KeyboardSettings) -> Void)?
    var onClose: (() -> Void)?

    private var settings: KeyboardSettings
    private let theme: KeyboardTheme
    private let scrollView = UIScrollView()
    private let rows = UIStackView()
    private let bar = UIStackView()
    private static let barHeight: CGFloat = 38

    private static let toggles: [(title: String, keyPath: WritableKeyPath<KeyboardSettings, Bool>)] = [
        ("Autocorrect", \.autocorrect),
        ("Auto-capitalisation", \.autoCapitalization),
        ("Predictive text", \.predictiveText),
        ("Word suggestions", \.wordSuggestions),
        ("Emoji suggestions", \.emojiSuggestions),
        ("Double-space for full stop", \.doubleSpacePeriod),
        ("Hold top row for numbers", \.holdForNumbers),
        ("Key popups", \.keyPopups),
        ("Show English meanings", \.showMeanings),
        ("Show romaji readings", \.showRomaji),
        ("Space bar moves cursor", \.spaceBarCursor),
        ("Left-handed mode wheel", \.leftHandedWheel),
        ("Flick only (かな)", \.flickOnly),
        ("Key sounds", \.keySounds),
        ("Haptics", \.haptics),
    ]

    /// `sharesWithApp` is false without Full Access: changes then stay on this keyboard.
    init(settings: KeyboardSettings, theme: KeyboardTheme, sharesWithApp: Bool) {
        self.settings = settings
        self.theme = theme
        super.init(frame: .zero)

        rows.axis = .vertical
        rows.spacing = 0
        rows.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(rows)
        addSubview(scrollView)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 12),
            rows.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -12),
            rows.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 4),
            rows.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -4),
            rows.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -24),
        ])

        for (index, toggle) in Self.toggles.enumerated() {
            rows.addArrangedSubview(row(title: toggle.title, isOn: settings[keyPath: toggle.keyPath], tag: index))
        }
        let note = UILabel()
        note.numberOfLines = 0
        note.font = .systemFont(ofSize: 12)
        note.textColor = theme.secondaryText
        note.text = sharesWithApp
            ? "Themes, photo, height and GIFs are in the RomaKey app."
            : "Saved on this keyboard only. Turn on Allow Full Access to share settings with the RomaKey app."
        rows.addArrangedSubview(note)

        bar.axis = .horizontal
        bar.alignment = .center
        var done = UIButton.Configuration.plain()
        done.baseForegroundColor = theme.text
        var title = AttributedString("ABC")
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        done.attributedTitle = title
        bar.addArrangedSubview(UIButton(configuration: done, primaryAction: UIAction { [weak self] _ in self?.onClose?() }))
        let heading = UILabel()
        heading.text = "設定 · Keyboard settings"
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

    private func row(title: String, isOn: Bool, tag: Int) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = theme.text
        let toggle = UISwitch()
        toggle.isOn = isOn
        toggle.onTintColor = theme.accent
        toggle.tag = tag
        toggle.accessibilityLabel = title
        toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, toggle])
        row.alignment = .center
        row.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return row
    }

    @objc private func toggled(_ sender: UISwitch) {
        settings[keyPath: Self.toggles[sender.tag].keyPath] = sender.isOn
        onChange?(settings)
    }
}
