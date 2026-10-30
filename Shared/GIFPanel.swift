import ImageIO
import KeyboardCore
import UIKit
import UniformTypeIdentifiers

struct GIFResult: Hashable, Codable {
    let id: String
    let slug: String
    let title: String
    /// A small GIF for the grid, played a frame at a time so it stays light on memory.
    let previewURL: URL
    /// The GIF to share.
    let gifURL: URL
    let width: Int
    let height: Int

    /// Height over width, kept within reason so one odd GIF can't take over the grid.
    var aspect: CGFloat {
        guard width > 0, height > 0 else { return 0.75 }
        return min(max(CGFloat(height) / CGFloat(width), 0.5), 1.5)
    }
}

/// KLIPY search, with the user's own free API key (Settings → GIF). Search terms go to KLIPY,
/// so this is off until a key is added, and needs Full Access.
///
/// GET https://api.klipy.com/api/v1/{key}/gifs/search?q=…, or /gifs/trending. The answer is
/// `{result, data: {data: [...], current_page, per_page, has_next}}`; each GIF has `id`, `slug`,
/// `title` and `file.{hd,md,sm,xs}.{gif,webp,mp4}` with `url`, `width` and `height`. Ads come
/// back as items without a `file` and are skipped. Decoding is lenient, so a missing size or
/// field skips that GIF rather than failing the search.
final class KlipyClient {
    struct Page {
        let results: [GIFResult]
        let hasNext: Bool
    }

    enum Failure: LocalizedError {
        case keyRejected
        case server(Int)

        var errorDescription: String? {
            switch self {
            case .keyRejected: return "KLIPY didn't accept the API key. Check it in the app: Settings → GIF."
            case .server(let status): return "KLIPY answered with an error (\(status)). Try again in a moment."
            }
        }
    }

    private let apiKey: String
    private let contentFilter: String

    /// `rating` is the setting's g / pg / pg-13 / r, as KLIPY's content filter.
    init(apiKey: String, rating: String) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        switch rating {
        case "g": contentFilter = "high"
        case "pg-13": contentFilter = "low"
        case "r": contentFilter = "off"
        default: contentFilter = "medium"
        }
    }

    /// KLIPY asks for a per-user ID: a random one, made once and kept on this phone.
    private static var customerID: String {
        let key = "klipyCustomerID"
        if let saved = UserDefaults.standard.string(forKey: key) {
            return saved
        }
        let made = UUID().uuidString
        UserDefaults.standard.set(made, forKey: key)
        return made
    }

    private func endpoint(_ path: String, _ items: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(string: "https://api.klipy.com/api/v1/\(apiKey)/gifs/\(path)")
        components?.queryItems = items.isEmpty ? nil : items
        return components?.url
    }

    /// Trending GIFs when `query` is nil.
    func fetch(query: String?, page: Int) async throws -> Page {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: "24"),
            URLQueryItem(name: "customer_id", value: Self.customerID),
            URLQueryItem(name: "content_filter", value: contentFilter),
        ]
        if let query {
            items.append(URLQueryItem(name: "q", value: query))
        }
        guard let url = endpoint(query == nil ? "trending" : "search", items) else { throw Failure.keyRejected }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw [401, 403, 404].contains(http.statusCode) ? Failure.keyRejected : Failure.server(http.statusCode)
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let results: [GIFResult] = (decoded.data?.data ?? []).compactMap { item in
            let files = item.file ?? [:]
            guard let small = files["xs"]?.gif ?? files["sm"]?.gif,
                  let preview = small.url.flatMap(URL.init),
                  let gif = (files["md"]?.gif ?? files["sm"]?.gif ?? files["hd"]?.gif)?.url.flatMap(URL.init) else { return nil }
            return GIFResult(id: item.id?.value ?? gif.absoluteString, slug: item.slug ?? "", title: item.title ?? "",
                             previewURL: preview, gifURL: gif, width: small.width ?? 4, height: small.height ?? 3)
        }
        return Page(results: results, hasNext: decoded.data?.has_next ?? false)
    }

    /// Tells KLIPY a GIF was shared, as its API asks, so it can rank and keep a Recent list.
    func reportShare(_ result: GIFResult, query: String?) {
        guard !result.slug.isEmpty, let url = endpoint("share/\(result.slug)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["customer_id": Self.customerID, "q": query ?? ""])
        URLSession.shared.dataTask(with: request).resume()
    }

    private struct Response: Decodable {
        let data: Page?

        struct Page: Decodable {
            let data: [Item]?
            let has_next: Bool?
        }
    }

    private struct Item: Decodable {
        let id: FlexibleID?
        let slug: String?
        let title: String?
        let file: [String: Size]?
    }

    private struct Size: Decodable {
        let gif: Media?
    }

    private struct Media: Decodable {
        let url: String?
        let width: Int?
        let height: Int?
    }

    /// KLIPY ids may be numbers or strings.
    private struct FlexibleID: Decodable {
        let value: String

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Int.self) {
                value = String(number)
            } else {
                value = try container.decode(String.self)
            }
        }
    }
}

/// The GIFs you sent most recently, newest first, kept on this phone.
enum RecentGIFs {
    private static let key = "recentGIFs"
    private static let capacity = 24

    static var all: [GIFResult] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([GIFResult].self, from: data)) ?? []
    }

    static func add(_ result: GIFResult) {
        let updated = [result] + all.filter { $0.id != result.id }
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(updated.prefix(capacity))), forKey: key)
    }
}

/// GIFs in place of the keys: a row of moods along the top, then a two-column grid of moving
/// GIFs at their own shapes, which loads more as you scroll.
///
/// iOS doesn't let keyboards put images into a message, so a tap either puts the GIF's link in
/// straight away (messaging apps show it as the GIF) or copies the GIF itself to paste. The
/// bar's 🔗/📋 switch picks which, and holding a GIF does the other one.
final class GIFPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegate {
    var onClose: (() -> Void)?
    var onSearch: (() -> Void)?
    var onMessage: ((String) -> Void)?
    /// Puts text (the GIF's link) into the document.
    var onInsert: ((String) -> Void)?
    /// The 🔗/📋 switch changed. True = insert links.
    var onInsertsLinkChange: ((Bool) -> Void)?

    private struct Category {
        let emoji: String
        let title: String
        /// nil = trending; "" = recent.
        let query: String?
    }

    private static let categories: [Category] = [
        Category(emoji: "🔥", title: "Trending", query: nil),
        Category(emoji: "😂", title: "Haha", query: "haha"),
        Category(emoji: "❤️", title: "Love", query: "love"),
        Category(emoji: "👍", title: "Yes", query: "yes"),
        Category(emoji: "🙅", title: "No", query: "no"),
        Category(emoji: "👋", title: "Hi", query: "hello"),
        Category(emoji: "🙏", title: "Thanks", query: "thank you"),
        Category(emoji: "🎉", title: "Yay", query: "celebrate"),
        Category(emoji: "😢", title: "Sad", query: "sad"),
        Category(emoji: "😮", title: "Wow", query: "wow"),
        Category(emoji: "🤔", title: "Hmm", query: "thinking"),
        Category(emoji: "😴", title: "Sleepy", query: "sleepy"),
        Category(emoji: "🐱", title: "Cats", query: "cat"),
        Category(emoji: "🐶", title: "Dogs", query: "dog"),
    ]
    private static let recentCategory = Category(emoji: "🕘", title: "Recent", query: "")

    private let client: KlipyClient?
    private let theme: KeyboardTheme
    private var insertsLink: Bool
    private var categories: [Category]
    private var selectedCategory = 0
    private var results: [GIFResult] = []
    private var page = 1
    private var hasNext = false
    private var isLoading = false
    private var loadID = 0
    private let layout: WaterfallLayout
    private let collection: UICollectionView
    private let chipScroll = UIScrollView()
    private let chipRow = UIStackView()
    private var chips: [UIButton] = []
    private let messageLabel = UILabel()
    private let bar = UIStackView()
    private var modeButton: UIButton?
    private static let chipHeight: CGFloat = 40
    private static let barHeight: CGFloat = 38
    private static let placeholderAspects: [CGFloat] = [0.75, 1, 0.6, 0.9, 1.1, 0.7, 0.85, 1]

    private var query: String? { categories[selectedCategory].query }

    /// `unavailableReason` explains why GIFs are off (no key, no Full Access) instead of searching.
    init(client: KlipyClient?, query: String?, theme: KeyboardTheme, insertsLink: Bool, unavailableReason: String?) {
        self.client = client
        self.theme = theme
        self.insertsLink = insertsLink
        var categories = Self.categories
        if !RecentGIFs.all.isEmpty {
            categories.insert(Self.recentCategory, at: 0)
        }
        if let query {
            categories.insert(Category(emoji: "🔍", title: query, query: query), at: 0)
        } else if let trending = categories.firstIndex(where: { $0.query == nil }) {
            selectedCategory = trending
        }
        self.categories = categories
        let layout = WaterfallLayout()
        self.layout = layout
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)

        layout.aspect = { [weak self] item in
            guard let self else { return 0.75 }
            return self.results.isEmpty ? Self.placeholderAspects[item % Self.placeholderAspects.count] : self.results[item].aspect
        }
        collection.backgroundColor = .clear
        collection.removeEdgeEffects()
        collection.showsVerticalScrollIndicator = false
        collection.alwaysBounceVertical = true
        collection.dataSource = self
        collection.delegate = self
        collection.register(GIFCell.self, forCellWithReuseIdentifier: "cell")
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(held(_:)))
        hold.minimumPressDuration = 0.4
        collection.addGestureRecognizer(hold)
        addSubview(collection)

        chipRow.axis = .horizontal
        chipRow.spacing = 6
        chipRow.alignment = .center
        chipRow.translatesAutoresizingMaskIntoConstraints = false
        chipScroll.showsHorizontalScrollIndicator = false
        chipScroll.removeEdgeEffects()
        chipScroll.addSubview(chipRow)
        NSLayoutConstraint.activate([
            chipRow.leadingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.leadingAnchor, constant: 8),
            chipRow.trailingAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.trailingAnchor, constant: -8),
            chipRow.topAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.topAnchor),
            chipRow.bottomAnchor.constraint(equalTo: chipScroll.contentLayoutGuide.bottomAnchor),
            chipRow.heightAnchor.constraint(equalTo: chipScroll.frameLayoutGuide.heightAnchor),
        ])
        addSubview(chipScroll)

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = theme.secondaryText
        messageLabel.isUserInteractionEnabled = false
        addSubview(messageLabel)

        buildBar()
        addSubview(bar)

        if let unavailableReason {
            messageLabel.text = unavailableReason
            chipScroll.isHidden = true
            collection.isHidden = true
        } else {
            buildChips()
            load(reset: true)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        chipScroll.frame = CGRect(x: 0, y: 2, width: bounds.width, height: Self.chipHeight)
        let gridTop = chipScroll.isHidden ? 0 : chipScroll.frame.maxY
        let grid = CGRect(x: 0, y: gridTop, width: bounds.width, height: bounds.height - Self.barHeight - gridTop)
        collection.frame = grid
        layout.columns = bounds.width > 520 ? 3 : 2
        messageLabel.frame = grid.insetBy(dx: 28, dy: 12)
        bar.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 8, height: Self.barHeight)
    }

    // MARK: - Moods and bar

    private func buildChips() {
        for (index, category) in categories.enumerated() {
            let chip = UIButton(configuration: chipConfiguration(category, selected: index == selectedCategory),
                                primaryAction: UIAction { [weak self] _ in self?.selectCategory(index) })
            chip.accessibilityLabel = category.title
            chipRow.addArrangedSubview(chip)
            chips.append(chip)
        }
    }

    private func chipConfiguration(_ category: Category, selected: Bool) -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = selected ? .prominentGlass() : .glass()
        } else {
            configuration = .filled()
            configuration.baseBackgroundColor = selected ? theme.accent : theme.key
        }
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = selected ? .white : theme.text
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 11, bottom: 6, trailing: 12)
        var title = AttributedString("\(category.emoji) \(category.title)")
        title.font = theme.font(13, weight: .medium)
        configuration.attributedTitle = title
        configuration.titleLineBreakMode = .byTruncatingTail
        return configuration
    }

    private func selectCategory(_ index: Int) {
        guard index != selectedCategory else {
            collection.setContentOffset(.zero, animated: theme.animates)
            return
        }
        selectedCategory = index
        for (chipIndex, chip) in chips.enumerated() {
            chip.configuration = chipConfiguration(categories[chipIndex], selected: chipIndex == index)
        }
        load(reset: true)
    }

    private func buildBar() {
        bar.axis = .horizontal
        bar.spacing = 4
        bar.alignment = .center

        func button(_ title: String?, symbol: String?, label: String, action: @escaping () -> Void) -> UIButton {
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = theme.text
            if let symbol {
                configuration.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .medium))
            }
            if let title {
                var text = AttributedString(title)
                text.font = .systemFont(ofSize: 14, weight: .semibold)
                configuration.attributedTitle = text
            }
            let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
            button.accessibilityLabel = label
            return button
        }
        bar.addArrangedSubview(button("ABC", symbol: nil, label: "Back to the keys") { [weak self] in self?.onClose?() })
        bar.addArrangedSubview(button(nil, symbol: "magnifyingglass", label: "Search GIFs") { [weak self] in self?.onSearch?() })
        let mode = UIButton(configuration: modeConfiguration(), primaryAction: UIAction { [weak self] _ in self?.toggleMode() })
        mode.setContentHuggingPriority(.required, for: .horizontal)
        modeButton = mode
        updateModeLabel()
        bar.addArrangedSubview(mode)
        let spacer = UIView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(spacer)
        let attribution = UILabel()
        attribution.text = "Powered by KLIPY"
        attribution.font = .systemFont(ofSize: 10, weight: .semibold)
        attribution.textColor = theme.secondaryText
        attribution.setContentHuggingPriority(.required, for: .horizontal)
        bar.addArrangedSubview(attribution)
    }

    /// A small capsule: 🔗 Link puts the link in, 📋 Copy copies the GIF.
    private func modeConfiguration() -> UIButton.Configuration {
        var configuration: UIButton.Configuration
        if #available(iOS 26.0, *) {
            configuration = .glass()
        } else {
            configuration = .gray()
        }
        configuration.cornerStyle = .capsule
        configuration.baseForegroundColor = theme.text
        configuration.image = UIImage(systemName: insertsLink ? "link" : "doc.on.doc",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        configuration.imagePadding = 4
        var title = AttributedString(insertsLink ? "Link" : "Copy")
        title.font = .systemFont(ofSize: 12, weight: .semibold)
        configuration.attributedTitle = title
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 10, bottom: 5, trailing: 10)
        return configuration
    }

    private func updateModeLabel() {
        modeButton?.accessibilityLabel = insertsLink ? "Tapping a GIF adds its link" : "Tapping a GIF copies it"
        modeButton?.accessibilityHint = "Switches between adding the link and copying the GIF"
    }

    private func toggleMode() {
        insertsLink.toggle()
        modeButton?.configuration = modeConfiguration()
        updateModeLabel()
        onInsertsLinkChange?(insertsLink)
        onMessage?(insertsLink ? "Tap a GIF: its link goes straight in" : "Tap a GIF: it's copied, then paste it")
    }

    // MARK: - Loading

    private func load(reset: Bool) {
        guard let client else { return }
        loadID += 1
        let id = loadID
        if reset {
            page = 1
            hasNext = false
            results = []
            messageLabel.text = nil
            collection.setContentOffset(.zero, animated: false)
        }
        if query == "" {
            // Recent: no network needed.
            isLoading = false
            results = RecentGIFs.all
            messageLabel.text = results.isEmpty ? "GIFs you send show up here." : nil
            collection.reloadData()
            return
        }
        isLoading = true
        if reset {
            collection.reloadData()
        }
        let query = query
        let page = page
        Task { @MainActor [weak self] in
            do {
                let fetched = try await client.fetch(query: query, page: page)
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                let known = Set(self.results.map(\.id))
                self.results += fetched.results.filter { !known.contains($0.id) }
                self.hasNext = fetched.hasNext && !fetched.results.isEmpty
                self.page = page + 1
                self.messageLabel.text = self.results.isEmpty ? "No GIFs found" : nil
                self.collection.reloadData()
            } catch {
                guard let self, self.loadID == id else { return }
                self.isLoading = false
                if self.results.isEmpty {
                    self.messageLabel.text = (error as? KlipyClient.Failure)?.errorDescription
                        ?? "Couldn't reach KLIPY. Check your connection."
                    self.collection.reloadData()
                }
            }
        }
    }

    // MARK: - Grid

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // Grey shapes pulse in the grid's place while the first page loads.
        results.isEmpty && isLoading ? Self.placeholderAspects.count : results.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GIFCell
        if results.isEmpty {
            cell.showPlaceholder(theme: theme)
        } else {
            cell.show(results[indexPath.item], theme: theme)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // Fade each GIF in as it arrives, and fetch the next page before the end.
        if !results.isEmpty, theme.animates {
            cell.alpha = 0
            UIView.animate(withDuration: 0.25) { cell.alpha = 1 }
        }
        if hasNext, !isLoading, indexPath.item >= results.count - 6 {
            load(reset: false)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        (cell as? GIFCell)?.stop()
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        !results.isEmpty
    }

    func collectionView(_ collectionView: UICollectionView, didHighlightItemAt indexPath: IndexPath) {
        guard theme.animates, let cell = collectionView.cellForItem(at: indexPath) else { return }
        UIView.animate(withDuration: 0.2) { cell.transform = CGAffineTransform(scaleX: 0.95, y: 0.95) }
    }

    func collectionView(_ collectionView: UICollectionView, didUnhighlightItemAt indexPath: IndexPath) {
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0) { cell.transform = .identity }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !results.isEmpty else { return }
        send(at: indexPath, asLink: insertsLink)
    }

    @objc private func held(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, !results.isEmpty,
              let indexPath = collection.indexPathForItem(at: gesture.location(in: collection)) else { return }
        send(at: indexPath, asLink: !insertsLink)
    }

    private func send(at indexPath: IndexPath, asLink: Bool) {
        let result = results[indexPath.item]
        let cell = collection.cellForItem(at: indexPath) as? GIFCell
        let query = query
        let finish = { [weak self] in
            RecentGIFs.add(result)
            if query != "" {
                self?.client?.reportShare(result, query: query)
            }
        }
        if asLink {
            onInsert?(result.gifURL.absoluteString)
            cell?.showDone(symbol: "link", theme: theme)
            onMessage?("GIF link added: most apps show it as the GIF")
            finish()
            return
        }
        cell?.showBusy()
        Task { @MainActor [weak self] in
            do {
                let data = try await GIFData.load(result.gifURL)
                UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
                cell?.showDone(symbol: "doc.on.doc", theme: self?.theme)
                self?.onMessage?("GIF copied: tap the message box, then Paste")
                finish()
            } catch {
                cell?.hideOverlay()
                self?.onMessage?("Couldn't download that GIF")
            }
        }
    }
}

/// Downloaded GIF data, kept briefly so scrolling back doesn't download again.
enum GIFData {
    private static let cache: NSCache<NSURL, NSData> = {
        let cache = NSCache<NSURL, NSData>()
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    static func cached(_ url: URL) -> Data? {
        cache.object(forKey: url as NSURL) as Data?
    }

    static func load(_ url: URL) async throws -> Data {
        if let data = cached(url) {
            return data
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        cache.setObject(data as NSData, forKey: url as NSURL, cost: data.count)
        return data
    }
}

/// A masonry grid: each GIF keeps its shape, and goes in whichever column is shortest.
private final class WaterfallLayout: UICollectionViewLayout {
    var columns = 2 {
        didSet { if columns != oldValue { invalidateLayout() } }
    }
    var aspect: (Int) -> CGFloat = { _ in 0.75 }
    private let spacing: CGFloat = 6
    private let insets = UIEdgeInsets(top: 4, left: 8, bottom: 10, right: 8)
    private var attributes: [UICollectionViewLayoutAttributes] = []
    private var contentHeight: CGFloat = 0

    override func prepare() {
        super.prepare()
        attributes = []
        guard let collectionView, collectionView.numberOfSections > 0 else { return }
        let width = collectionView.bounds.width - insets.left - insets.right
        let columnWidth = ((width - spacing * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down)
        var heights = Array(repeating: insets.top, count: columns)
        for item in 0..<collectionView.numberOfItems(inSection: 0) {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let frame = CGRect(x: insets.left + CGFloat(column) * (columnWidth + spacing), y: heights[column],
                               width: columnWidth, height: (columnWidth * aspect(item)).rounded())
            let attribute = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: item, section: 0))
            attribute.frame = frame
            attributes.append(attribute)
            heights[column] = frame.maxY + spacing
        }
        contentHeight = (heights.max() ?? 0) + insets.bottom
    }

    override var collectionViewContentSize: CGSize {
        CGSize(width: collectionView?.bounds.width ?? 0, height: contentHeight)
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        attributes.filter { $0.frame.intersects(rect) }
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil
    }

    override func shouldInvalidateLayout(forBoundsChange newBounds: CGRect) -> Bool {
        newBounds.width != collectionView?.bounds.width
    }
}

/// Stops a GIF's frames from ImageIO, which plays them off the main thread.
private final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false

    var isStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
    }
}

private final class GIFCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private let overlay = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let doneView = UIImageView()
    private var url: URL?
    private var playing: StopFlag?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        contentView.addSubview(imageView)
        overlay.isHidden = true
        spinner.color = .white
        doneView.tintColor = .white
        doneView.contentMode = .center
        overlay.contentView.addSubview(spinner)
        overlay.contentView.addSubview(doneView)
        contentView.addSubview(overlay)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
        overlay.frame = contentView.bounds
        spinner.center = CGPoint(x: overlay.bounds.midX, y: overlay.bounds.midY)
        doneView.frame = overlay.bounds
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        stop()
        url = nil
        imageView.image = nil
        imageView.layer.removeAllAnimations()
        imageView.alpha = 1
        transform = .identity
        hideOverlay()
    }

    func stop() {
        playing?.stop()
        playing = nil
    }

    func showPlaceholder(theme: KeyboardTheme) {
        accessibilityLabel = nil
        imageView.image = nil
        imageView.backgroundColor = theme.key.withAlphaComponent(0.6)
        guard theme.animates else { return }
        let pulse = CABasicAnimation(keyPath: "opacity")
        pulse.fromValue = 1
        pulse.toValue = 0.45
        pulse.duration = 0.8
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        imageView.layer.add(pulse, forKey: "pulse")
    }

    func show(_ result: GIFResult, theme: KeyboardTheme) {
        imageView.layer.removeAllAnimations()
        url = result.previewURL
        imageView.backgroundColor = theme.key.withAlphaComponent(0.6)
        isAccessibilityElement = true
        accessibilityLabel = result.title.isEmpty ? "GIF" : result.title
        accessibilityTraits = .button
        let animates = theme.animates
        if let data = GIFData.cached(result.previewURL) {
            play(data, animates: animates)
            return
        }
        Task { @MainActor [weak self] in
            guard let data = try? await GIFData.load(result.previewURL), self?.url == result.previewURL else { return }
            self?.play(data, animates: animates)
        }
    }

    /// Plays the GIF one decoded frame at a time, so a screenful of them stays light. With
    /// animations off (or Reduce Motion), just its first frame.
    private func play(_ data: Data, animates: Bool) {
        stop()
        guard animates else {
            imageView.image = UIImage(data: data)
            return
        }
        let flag = StopFlag()
        playing = flag
        let status = CGAnimateImageDataWithBlock(data as CFData, nil) { [weak self] _, image, stop in
            guard !flag.isStopped else {
                stop.pointee = true
                return
            }
            let frame = UIImage(cgImage: image)
            DispatchQueue.main.async {
                guard !flag.isStopped else { return }
                self?.imageView.image = frame
            }
        }
        if status != 0 {
            imageView.image = UIImage(data: data)
        }
    }

    func showBusy() {
        overlay.isHidden = false
        doneView.isHidden = true
        spinner.startAnimating()
    }

    /// A tick-like symbol over the GIF for a moment.
    func showDone(symbol: String, theme: KeyboardTheme?) {
        spinner.stopAnimating()
        overlay.isHidden = false
        doneView.isHidden = false
        doneView.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 22, weight: .bold))
        overlay.alpha = 1
        if theme?.animates == true {
            doneView.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.55, initialSpringVelocity: 0) {
                self.doneView.transform = .identity
            }
        }
        UIView.animate(withDuration: 0.3, delay: 0.9, options: []) {
            self.overlay.alpha = 0
        } completion: { _ in
            self.hideOverlay()
        }
    }

    func hideOverlay() {
        spinner.stopAnimating()
        overlay.isHidden = true
        overlay.alpha = 1
    }
}
