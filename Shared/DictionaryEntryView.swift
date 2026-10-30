import KeyboardCore
import UIKit

/// A full dictionary entry shown over the keys: the word, its reading, every meaning, and
/// buttons to insert it as kanji, hiragana or katakana.
final class DictionaryEntryView: UIView {
    var onInsert: ((String) -> Void)?
    var onClose: (() -> Void)?

    init(entry: DictionaryEntry, theme: KeyboardTheme) {
        super.init(frame: .zero)
        backgroundColor = theme.key
        layer.cornerRadius = 10

        let word = UILabel()
        word.text = entry.word
        word.font = .systemFont(ofSize: 28, weight: .medium)
        word.textColor = theme.text

        let reading = UILabel()
        reading.text = [entry.reading, entry.partOfSpeech].filter { !$0.isEmpty }.joined(separator: "  ·  ")
        reading.font = .systemFont(ofSize: 14)
        reading.textColor = theme.secondaryText

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        close.tintColor = theme.secondaryText
        close.addAction(UIAction { [weak self] _ in self?.onClose?() }, for: .touchUpInside)
        close.setContentHuggingPriority(.required, for: .horizontal)

        let titles = UIStackView(arrangedSubviews: [word, reading])
        titles.axis = .vertical
        let header = UIStackView(arrangedSubviews: [titles, close])
        header.alignment = .top

        let senses = UILabel()
        senses.numberOfLines = 0
        senses.font = .systemFont(ofSize: 15)
        senses.textColor = theme.text
        senses.text = entry.senses.enumerated()
            .map { index, glosses in "\(index + 1). " + glosses.joined(separator: "; ") }
            .joined(separator: "\n")
        let scroll = UIScrollView()
        scroll.addSubview(senses)
        senses.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            senses.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            senses.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            senses.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            senses.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            senses.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])

        // Insert buttons: the usual spelling first, then the other forms.
        var forms: [String] = []
        for form in [entry.word, entry.kanji, entry.reading, KanaConverter.katakana(from: entry.reading)]
        where !form.isEmpty && !forms.contains(form) {
            forms.append(form)
        }
        let buttons = UIStackView(arrangedSubviews: forms.enumerated().map { index, form -> UIButton in
            var configuration = index == 0 ? UIButton.Configuration.filled() : UIButton.Configuration.tinted()
            var title = AttributedString(form)
            title.font = .systemFont(ofSize: 17, weight: index == 0 ? .semibold : .regular)
            configuration.attributedTitle = title
            configuration.baseBackgroundColor = theme.accent
            configuration.baseForegroundColor = index == 0 ? .white : theme.accent
            configuration.cornerStyle = .medium
            return UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                self?.onInsert?(form)
            })
        })
        buttons.spacing = 8
        buttons.distribution = .fillProportionally

        let content = UIStackView(arrangedSubviews: [header, scroll, buttons])
        content.axis = .vertical
        content.spacing = 8
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            buttons.heightAnchor.constraint(equalToConstant: 40),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
