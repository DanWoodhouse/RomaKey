import KeyboardCore
import UIKit
import UniformTypeIdentifiers

struct GIFResult: Hashable {
    let id: String
    let title: String
    /// A small still frame: animated previews would use too much of the keyboard's memory.
    let previewURL: URL
    /// The GIF to share.
    let gifURL: URL
}

/// GIPHY search, with the user's own API key (Settings → GIFs). Tenor's API closed in June 2026.
/// Search terms go to GIPHY, so this is off until a key is added, and needs Full Access.
final class GiphyClient {
    private let apiKey: String
    private let rating: String
    private let language: String

    init(apiKey: String, rating: String, language: String) {
        self.apiKey = apiKey
        self.rating = rating
        self.language = language
    }

    /// Trending GIFs when `query` is nil.
    func fetch(query: String?) async throws -> [GIFResult] {
        var components = URLComponents(string: query == nil
            ? "https://api.giphy.com/v1/gifs/trending"
            : "https://api.giphy.com/v1/gifs/search")!
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: "30"),
            URLQueryItem(name: "rating", value: rating),
        ]
        if let query {
            components.queryItems! += [URLQueryItem(name: "q", value: query), URLQueryItem(name: "lang", value: language)]
        }
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(http.statusCode == 401 || http.statusCode == 403 ? .userAuthenticationRequired : .badServerResponse)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Response.self, from: data).data.compactMap { item in
            guard let preview = (item.images.fixedWidthSmallStill ?? item.images.fixedWidthStill)?.url.flatMap(URL.init),
                  let gif = (item.images.downsized ?? item.images.fixedWidth)?.url.flatMap(URL.init) else { return nil }
            return GIFResult(id: item.id, title: item.title ?? "", previewURL: preview, gifURL: gif)
        }
    }

    private struct Response: Decodable {
        let data: [Item]
    }

    private struct Item: Decodable {
        let id: String
        let title: String?
        let images: Images
    }

    private struct Images: Decodable {
        let fixedWidthSmallStill: Rendition?
        let fixedWidthStill: Rendition?
        let fixedWidth: Rendition?
        let downsized: Rendition?
    }

    private struct Rendition: Decodable {
        let url: String?
    }
}

/// GIF results in place of the keys. Tap one to copy it, then paste it into the message:
/// iOS doesn't let keyboards insert images directly.
final class GIFPanel: UIView, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var onClose: (() -> Void)?
    var onSearch: (() -> Void)?
    var onMessage: ((String) -> Void)?

    private let client: GiphyClient?
    private let theme: KeyboardTheme
    private var results: [GIFResult] = []
    private let collection: UICollectionView
    private let messageLabel = UILabel()
    private let bar = UIStackView()
    private static let previews = NSCache<NSURL, UIImage>()
    private static let barHeight: CGFloat = 38

    /// `unavailableReason` explains why GIFs are off (no key, no Full Access) instead of searching.
    init(client: GiphyClient?, query: String?, theme: KeyboardTheme, unavailableReason: String?) {
        self.client = client
        self.theme = theme
        let layout = UICollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4
        layout.sectionInset = UIEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
        collection = UICollectionView(frame: .zero, collectionViewLayout: layout)
        super.init(frame: .zero)
        Self.previews.countLimit = 60

        collection.backgroundColor = .clear
        collection.removeEdgeEffects()
        collection.dataSource = self
        collection.delegate = self
        collection.register(GIFCell.self, forCellWithReuseIdentifier: "cell")
        addSubview(collection)

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .center
        messageLabel.font = .systemFont(ofSize: 14)
        messageLabel.textColor = theme.secondaryText
        addSubview(messageLabel)

        buildBar(title: query.map { "“\($0)”" } ?? "Trending")
        addSubview(bar)

        if let unavailableReason {
            messageLabel.text = unavailableReason
        } else {
            load(query: query)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let content = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.barHeight)
        collection.frame = content
        messageLabel.frame = content.insetBy(dx: 24, dy: 12)
        bar.frame = CGRect(x: 4, y: bounds.height - Self.barHeight, width: bounds.width - 8, height: Self.barHeight)
        collection.collectionViewLayout.invalidateLayout()
    }

    private func buildBar(title: String) {
        bar.axis = .horizontal
        bar.spacing = 8
        bar.alignment = .center

        func button(_ title: String?, symbol: String?, action: @escaping () -> Void) -> UIButton {
            var configuration = UIButton.Configuration.plain()
            configuration.baseForegroundColor = theme.text
            if let symbol { configuration.image = UIImage(systemName: symbol) }
            if let title {
                var text = AttributedString(title)
                text.font = .systemFont(ofSize: 14, weight: .medium)
                configuration.attributedTitle = text
            }
            return UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        }
        bar.addArrangedSubview(button("ABC", symbol: nil) { [weak self] in self?.onClose?() })
        bar.addArrangedSubview(button(nil, symbol: "magnifyingglass") { [weak self] in self?.onSearch?() })
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = theme.text
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(titleLabel)
        let attribution = UILabel()
        attribution.text = "Powered by GIPHY"
        attribution.font = .systemFont(ofSize: 10, weight: .semibold)
        attribution.textColor = theme.secondaryText
        attribution.setContentHuggingPriority(.required, for: .horizontal)
        bar.addArrangedSubview(attribution)
    }

    private func load(query: String?) {
        guard let client else { return }
        messageLabel.text = "Loading…"
        Task { @MainActor [weak self] in
            do {
                let results = try await client.fetch(query: query)
                self?.results = results
                self?.messageLabel.text = results.isEmpty ? "No GIFs found" : nil
                self?.collection.reloadData()
            } catch let error as URLError where error.code == .userAuthenticationRequired {
                self?.messageLabel.text = "GIPHY didn't accept the API key. Check it in the app's settings."
            } catch {
                self?.messageLabel.text = "Couldn't reach GIPHY. Check your connection."
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        results.count
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GIFCell
        let result = results[indexPath.item]
        cell.show(result, cache: Self.previews, placeholder: theme.key)
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {
        let width = floor((collectionView.bounds.width - 16) / 3)
        return CGSize(width: width, height: width * 0.75)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let result = results[indexPath.item]
        onMessage?("Copying GIF…")
        Task { @MainActor [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: result.gifURL)
                UIPasteboard.general.setData(data, forPasteboardType: UTType.gif.identifier)
                self?.onMessage?("GIF copied: paste it into your message")
            } catch {
                self?.onMessage?("Couldn't download that GIF")
            }
        }
    }
}

private final class GIFCell: UICollectionViewCell {
    private let imageView = UIImageView()
    private var url: URL?

    override init(frame: CGRect) {
        super.init(frame: frame)
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 6
        contentView.addSubview(imageView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = contentView.bounds
    }

    func show(_ result: GIFResult, cache: NSCache<NSURL, UIImage>, placeholder: UIColor) {
        url = result.previewURL
        imageView.backgroundColor = placeholder
        accessibilityLabel = result.title
        if let image = cache.object(forKey: result.previewURL as NSURL) {
            imageView.image = image
            return
        }
        imageView.image = nil
        Task { @MainActor [weak self] in
            guard let download = try? await URLSession.shared.data(from: result.previewURL),
                  let image = UIImage(data: download.0) else { return }
            cache.setObject(image, forKey: result.previewURL as NSURL)
            if self?.url == result.previewURL {
                self?.imageView.image = image
            }
        }
    }
}
