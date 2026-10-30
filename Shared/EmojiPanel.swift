import KeyboardCore
import UIKit

/// Emoji and 顔文字, shown in place of the keys. Tabs along the bottom, like the system keyboard:
/// ABC (back to typing), search, recents, the emoji groups, 顔文字 and delete.
/// Long-press an emoji with skin tones to pick one; the choice is remembered for all emoji.
final class EmojiPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    enum Tab: Hashable {
        case recent
        case group(EmojiGroup)
        case kaomoji
    }

    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onClose: (() -> Void)?
    var onSearch: (() -> Void)?
    /// A new default skin tone was picked (0 = yellow, 1–5 = light to dark).
    var onSkinTone: ((Int) -> Void)?

    private let catalog: EmojiCatalog?
    private let recents: RecentEmoji?
    private let theme: KeyboardTheme
    private var skinTone: Int
    private var tab: Tab
    /// For the current tab: one section per 顔文字 category, otherwise a single section.
    private var sections: [(title: String?, items: [String])] = []
    /// Emoji by character, for skin tones.
    private var emojiByCharacter: [String: Emoji] = [:]

    private let collection: UICollectionView
    private let bar = UIStackView()
    private var tabButtons: [Tab: UIButton] = [:]
    private let deleteRepeater = KeyRepeater()
    private var tonePicker: UIStackView?

    private static let barHeight: CGFloat = 38

    init(catalog: EmojiCatalog?, recents: RecentEmoji?, theme: KeyboardTheme, skinTone: Int, tab: Tab) {
        self.catalog = catalog
        self.recents = recents
        self.theme = theme
        self.skinTone = skinTone
        self.tab = tab
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 0
        layout.minimumLineSpacing = 0
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        for item in catalog?.emoji ?? [] where !item.skinTones.isEmpty {
            emojiByCharacter[item.character] = item
        }

        collection.backgroundColor = .clear
        collection.dataSource = self
        collection.delegate = self
        collection.register(EmojiCell.self, forCellWithReuseIdentifier: "cell")
        collection.register(SectionHeader.self, forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                            withReuseIdentifier: "header")
        collection.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(longPressed(_:))))
        addSubview(collection)

        buildBar()
        addSubview(bar)
        select(tab)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        collection.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.barHeight)
        bar.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 8, height: Self.barHeight)
        collection.collectionViewLayout.invalidateLayout()
    }

    // MARK: - Tabs

    private func buildBar() {
        bar.axis = .horizontal
        bar.distribution = .fillEqually

        bar.addArrangedSubview(barButton(title: "ABC", symbol: nil) { [weak self] in self?.onClose?() })
        bar.addArrangedSubview(barButton(title: nil, symbol: "magnifyingglass") { [weak self] in self?.onSearch?() })

        let tabs: [Tab] = [.recent] + EmojiGroup.allCases.map { .group($0) } + [.kaomoji]
        for tab in tabs {
            let button: UIButton
            switch tab {
            case .recent: button = barButton(title: nil, symbol: "clock") { [weak self] in self?.select(tab) }
            case .group(let group): button = barButton(title: group.icon, symbol: nil) { [weak self] in self?.select(tab) }
            case .kaomoji: button = barButton(title: "顔", symbol: nil) { [weak self] in self?.select(tab) }
            }
            tabButtons[tab] = button
            bar.addArrangedSubview(button)
        }

        let delete = barButton(title: nil, symbol: "delete.left") {}
        delete.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        delete.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        bar.addArrangedSubview(delete)
    }

    private func barButton(title: String?, symbol: String?, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.baseForegroundColor = theme.text
        configuration.contentInsets = .zero
        if let symbol {
            configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15))
        }
        if let title {
            var text = AttributedString(title)
            text.font = .systemFont(ofSize: title.count > 1 ? 13 : 17, weight: .medium)
            configuration.attributedTitle = text
        }
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.layer.cornerRadius = 6
        return button
    }

    private func select(_ tab: Tab) {
        self.tab = tab
        for (key, button) in tabButtons {
            button.backgroundColor = key == tab ? theme.pressedKey : .clear
        }
        switch tab {
        case .recent:
            let recent = recents?.items ?? []
            sections = [("よく使う · Recent", recent.isEmpty ? ["😊", "👍", "🙏", "😂", "❤️", "🎉"] : recent)]
        case .group(let group):
            sections = [(nil, catalog?.emoji(in: group).map(\.character) ?? [])]
        case .kaomoji:
            sections = Kaomoji.categories.map { (title: Optional($0.name), items: $0.faces) }
        }
        collection.reloadData()
        collection.setContentOffset(.zero, animated: false)
    }

    private func display(_ item: String) -> String {
        emojiByCharacter[item]?.withSkinTone(skinTone) ?? item
    }

    // MARK: - Collection

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        sections.count
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        sections[section].items.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! EmojiCell
        cell.configure(text: display(sections[indexPath.section].items[indexPath.item]), isKaomoji: tab == .kaomoji, theme: theme)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! SectionHeader
        header.label.text = sections[indexPath.section].title
        header.label.textColor = theme.secondaryText
        return header
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        referenceSizeForHeaderInSection section: Int) -> CGSize {
        sections[section].title == nil ? .zero : CGSize(width: collectionView.bounds.width, height: 22)
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        if tab == .kaomoji {
            let text = sections[indexPath.section].items[indexPath.item] as NSString
            let width = text.size(withAttributes: [.font: UIFont.systemFont(ofSize: 16)]).width + 24
            return CGSize(width: min(ceil(width), collectionView.bounds.width), height: 40)
        }
        let columns = max(floor(collectionView.bounds.width / 46), 1)
        return CGSize(width: floor(collectionView.bounds.width / columns), height: 44)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        tonePicker?.removeFromSuperview()
        tonePicker = nil
        let item = display(sections[indexPath.section].items[indexPath.item])
        recents?.use(item)
        onInsert?(item)
    }

    // MARK: - Skin tones

    @objc private func longPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let indexPath = collection.indexPathForItem(at: gesture.location(in: collection)),
              let item = emojiByCharacter[sections[indexPath.section].items[indexPath.item]],
              let cell = collection.cellForItem(at: indexPath) else { return }
        showTonePicker(for: item, above: cell.convert(cell.bounds, to: self))
    }

    private func showTonePicker(for item: Emoji, above cellFrame: CGRect) {
        tonePicker?.removeFromSuperview()
        let picker = UIStackView()
        picker.axis = .horizontal
        picker.distribution = .fillEqually
        picker.backgroundColor = theme.panel
        picker.layer.cornerRadius = 10
        picker.layer.shadowColor = UIColor.black.cgColor
        picker.layer.shadowOpacity = 0.3
        picker.layer.shadowRadius = 4
        for tone in 0...5 {
            var configuration = UIButton.Configuration.plain()
            var title = AttributedString(item.withSkinTone(tone))
            title.font = .systemFont(ofSize: 28)
            configuration.attributedTitle = title
            picker.addArrangedSubview(UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                self.skinTone = tone
                self.onSkinTone?(tone)
                let choice = item.withSkinTone(tone)
                self.recents?.use(choice)
                self.onInsert?(choice)
                self.tonePicker?.removeFromSuperview()
                self.tonePicker = nil
                self.collection.reloadData()
            }))
        }
        let width = min(bounds.width - 16, 300)
        let x = min(max(cellFrame.midX - width / 2, 8), bounds.width - width - 8)
        picker.frame = CGRect(x: x, y: max(cellFrame.minY - 52, 0), width: width, height: 48)
        addSubview(picker)
        tonePicker = picker
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Tapping anywhere else closes the skin tone picker.
        tonePicker?.removeFromSuperview()
        tonePicker = nil
        super.touchesBegan(touches, with: event)
    }

    @objc private func deleteDown() {
        deleteRepeater.start { [weak self] _ in self?.onDelete?() }
    }

    @objc private func deleteUp() {
        deleteRepeater.stop()
    }
}

private final class EmojiCell: UICollectionViewCell {
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.textAlignment = .center
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = contentView.bounds
    }

    func configure(text: String, isKaomoji: Bool, theme: KeyboardTheme) {
        label.text = text
        label.font = .systemFont(ofSize: isKaomoji ? 16 : 30)
        label.textColor = theme.text
        contentView.backgroundColor = isKaomoji ? theme.key : .clear
    }

    override var isHighlighted: Bool {
        didSet { contentView.alpha = isHighlighted ? 0.5 : 1 }
    }
}

private final class SectionHeader: UICollectionReusableView {
    let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 8, dy: 0)
    }
}
